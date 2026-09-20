#!/bin/sh
# Inspect or apply the desired GitHub governance profile. Plan-only is the default.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=
profile="$script_dir/github/governance-profile.json"
apply=false

usage() { echo "usage: $0 --repo OWNER/REPO [--profile FILE] [--apply]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --profile) profile=$2; shift 2 ;;
    --apply) apply=true; shift ;;
    --dry-run|--plan) apply=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$repo" ] || { usage >&2; exit 2; }
[ -f "$profile" ] || { echo "Profile not found: $profile" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh is required." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 2; }

repo_json=$(gh api "repos/$repo") || { echo "Cannot inspect $repo. Check gh auth and repository access." >&2; exit 1; }
default_branch=$(printf '%s' "$repo_json" | jq -r .default_branch)
visibility=$(printf '%s' "$repo_json" | jq -r .visibility)
owner=$(jq -r .governanceOwner "$profile")
ruleset_name=$(jq -r .rulesetName "$profile")
review_context=$(jq -r '.review.statusContext' "$profile")
default_integration_id=$(jq -r '.review.preferredTrustedIntegrationId' "$profile")
reviewer_app_id=$(jq -r '.review.externalReviewerAppId // empty' "$profile")
require_review=$(jq -r '.review.requireIndependentReview as $v | if $v == null then true else $v end' "$profile")
required_approving_review_count=$(jq -r '.review.requiredApprovals // 0' "$profile")
dismiss_stale_reviews=$(jq -r '.review.dismissStaleApprovals as $v | if $v == null then true else $v end' "$profile")
require_code_owner_review=$(jq -r '.review.requireCodeOwnerReview as $v | if $v == null then true else $v end' "$profile")
require_last_push_approval=$(jq -r '.review.requireLastPushApproval as $v | if $v == null then true else $v end' "$profile")
require_extra_approval_unattributed=$(jq -r '.review.requireExtraApprovalForUnattributedChanges as $v | if $v == null then true else $v end' "$profile")

rulesets_tmp=$(mktemp)
err_tmp=$(mktemp)
payload_tmp=$(mktemp)
trap 'rm -f "$rulesets_tmp" "$err_tmp" "$payload_tmp"' EXIT HUP INT TERM

capability=rulesets
if ! gh api "repos/$repo/rulesets" >"$rulesets_tmp" 2>"$err_tmp"; then
  capability=branch-protection-fallback
fi

echo "GitHub governance plan"
echo "  repository: $repo ($visibility)"
echo "  default branch: $default_branch"
echo "  governance owner: $owner"
echo "  preferred control: GitHub rulesets"
echo "  detected capability: $capability"
echo "  required checks:"
while IFS= read -r check; do
  [ -n "$check" ] || continue
  if [ "$check" = "$review_context" ]; then
    if [ "$require_review" = "false" ]; then
      echo "    - $check (independent review not required by policy; this check always succeeds)"
    elif [ -n "$reviewer_app_id" ]; then
      echo "    - $check (integration_id $reviewer_app_id, dedicated reviewer App)"
    else
      echo "    - $check (integration_id $default_integration_id, default Actions identity; no reviewer App configured yet)"
    fi
  else
    echo "    - $check (integration_id $default_integration_id)"
  fi
done <<CHECKS
$(jq -r '.requiredStatusChecks[]' "$profile")
CHECKS
echo "  pull requests: required; approving reviews required: $required_approving_review_count; stale approvals dismissed: $dismiss_stale_reviews; code owner review: $require_code_owner_review; last-push approval: $require_last_push_approval; extra approval for unattributed changes: $require_extra_approval_unattributed"
if [ "$capability" != rulesets ]; then
  echo "  limitation: classic branch protection has no equivalent of require_extra_approval_for_unattributed_changes; the profile's value ($require_extra_approval_unattributed) cannot be enforced under this fallback."
fi
echo "  history: force pushes and deletion blocked; linear history required"
echo "  workflow token default: read; Actions cannot approve PRs"

if [ "$capability" = rulesets ]; then
  existing=$(jq --arg name "$ruleset_name" -r '.[] | select(.name == $name) | .id' "$rulesets_tmp" | sed -n '1p')
  if [ -n "$existing" ]; then echo "  action: update ruleset $existing"; else echo "  action: create ruleset '$ruleset_name'"; fi
else
  echo "  action: use classic branch protection fallback"
  echo "  capability detail: $(tr '\n' ' ' < "$err_tmp" | sed 's/[[:space:]][[:space:]]*/ /g')"
  echo "  limitation: CODEOWNERS/review features depend on the repository plan and visibility."
fi

if [ "$apply" != true ]; then
  echo "PLAN ONLY: no repository settings were changed. Re-run with --apply after review."
  exit 0
fi

case "$owner" in '<owner>'|'@<owner>'|'') echo "Refused: replace <owner> in the profile before applying." >&2; exit 1 ;; esac

# Least-privilege Actions defaults are independent of ruleset availability.
gh api --method PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null

if [ "$capability" = rulesets ]; then
  checks=$(jq --arg reviewContext "$review_context" \
              --argjson defaultId "$default_integration_id" \
              --argjson appId "$(jq -r '.review.externalReviewerAppId // "null"' "$profile")" '
    [.requiredStatusChecks[] |
      { context: .,
        integration_id: (if . == $reviewContext and $appId != null then $appId else $defaultId end)
      }
    ]' "$profile")
  jq --arg name "$ruleset_name" --argjson checks "$checks" \
     --argjson approvals "$required_approving_review_count" \
     --argjson dismissStale "$dismiss_stale_reviews" \
     --argjson codeOwner "$require_code_owner_review" \
     --argjson lastPush "$require_last_push_approval" \
     --argjson extraApprovalUnattributed "$require_extra_approval_unattributed" '
    .name = $name |
    (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) = $checks |
    (.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = $approvals |
    (.rules[] | select(.type == "pull_request") | .parameters.dismiss_stale_reviews_on_push) = $dismissStale |
    (.rules[] | select(.type == "pull_request") | .parameters.require_code_owner_review) = $codeOwner |
    (.rules[] | select(.type == "pull_request") | .parameters.require_last_push_approval) = $lastPush |
    (.rules[] | select(.type == "pull_request") | .parameters.require_extra_approval_for_unattributed_changes) = $extraApprovalUnattributed
  ' "$script_dir/github/rulesets/default-branch.json" > "$payload_tmp"
  if [ -n "${existing:-}" ]; then
    gh api --method PUT "repos/$repo/rulesets/$existing" --input "$payload_tmp" >/dev/null
  else
    gh api --method POST "repos/$repo/rulesets" --input "$payload_tmp" >/dev/null
  fi
  echo "Applied GitHub ruleset '$ruleset_name'."
else
  contexts=$(jq '.requiredStatusChecks' "$profile")
  jq -n --argjson contexts "$contexts" \
        --argjson approvals "$required_approving_review_count" \
        --argjson dismissStale "$dismiss_stale_reviews" \
        --argjson codeOwner "$require_code_owner_review" \
        --argjson lastPush "$require_last_push_approval" '{
    required_status_checks: {strict: true, contexts: $contexts},
    enforce_admins: true,
    required_pull_request_reviews: {
      dismissal_restrictions: {}, dismiss_stale_reviews: $dismissStale,
      require_code_owner_reviews: $codeOwner, required_approving_review_count: $approvals,
      require_last_push_approval: $lastPush, bypass_pull_request_allowances: {}
    },
    restrictions: null, required_linear_history: true,
    allow_force_pushes: false, allow_deletions: false,
    required_conversation_resolution: true, lock_branch: false,
    allow_fork_syncing: true
  }' > "$payload_tmp"
  if ! gh api --method PUT "repos/$repo/branches/$default_branch/protection" --input "$payload_tmp" >/dev/null; then
    echo "GitHub rejected classic branch protection. This plan/visibility needs manual owner enforcement." >&2
    exit 1
  fi
  echo "Applied classic branch protection fallback. Verify CODEOWNERS review in repository settings."
fi
