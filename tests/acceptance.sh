#!/bin/sh
# V3 acceptance suite. Everything mutable lives in disposable repositories.
set -u

kit=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=${GOVERNANCE_TEST_WORKDIR:-$(mktemp -d)}
keep=${GOVERNANCE_TEST_KEEP:-false}
pass=0
fail=0

cleanup() { [ "$keep" = true ] || rm -rf "$work"; }
trap cleanup EXIT HUP INT TERM

check() {
  name=$1
  shift
  if "$@"; then pass=$((pass + 1)); printf 'PASS  %s\n' "$name"
  else fail=$((fail + 1)); printf 'FAIL  %s\n' "$name" >&2
  fi
}
contains() { printf '%s' "$1" | grep -Eq "$2"; }
not_contains() { ! contains "$1" "$2"; }
exists() { [ -e "$1" ]; }
not_exists() { [ ! -e "$1" ]; }
equals() { [ "$1" = "$2" ]; }
fails() { ! "$@"; }

reachable_metadata_is_clean() {
  metadata_repo=$1
  metadata_pattern=$2
  metadata=$(
    git -C "$metadata_repo" log --all --format='%an%n%ae%n%cn%n%ce%n%B' || exit 1
    for tag_object in $(git -C "$metadata_repo" for-each-ref --format='%(objectname)' refs/tags); do
      [ "$(git -C "$metadata_repo" cat-file -t "$tag_object")" = tag ] || continue
      git -C "$metadata_repo" cat-file tag "$tag_object" || exit 1
    done
  ) || return 2
  ! printf '%s\n' "$metadata" | grep -Eiq "$metadata_pattern"
}

reachable_content_is_clean() {
  content_repo=$1
  content_pattern=$2
  for object in $(git -C "$content_repo" rev-list --objects --all | awk '{print $1}' | sort -u); do
    [ "$(git -C "$content_repo" cat-file -t "$object")" = blob ] || continue
    git -C "$content_repo" cat-file blob "$object" | grep -Eiq "$content_pattern" && return 1
  done
  return 0
}

for tool in git jq sha256sum gitleaks lefthook; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing test prerequisite: $tool" >&2; exit 2; }
done

echo "Workspace: $work"
repo="$work/scaffold"
"$kit/new-governed-repo.sh" --target "$repo" --name 'Acceptance Project' --owner test-owner >/dev/null
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name 'Governance Acceptance'

check 'Linux bootstrap creates canonical AGENTS.md' exists "$repo/AGENTS.md"
check 'Linux bootstrap installs the machine policy' exists "$repo/.governance/policy.json"
check 'Linux bootstrap installs core CI' exists "$repo/.github/workflows/governance.yml"
check 'Linux bootstrap installs exact-head review gate' exists "$repo/.github/workflows/review-gate.yml"
check 'Linux bootstrap binds CODEOWNERS to the human owner' contains "$(cat "$repo/.github/CODEOWNERS")" '@test-owner'
check 'trust root identifies governance updaters and manifests' jq -e '.trustRootPaths | index("governance-manifest.json") and index("update-governance.sh")' "$repo/.governance/policy.json"
check 'CODEOWNERS targets trust roots without forcing all prose through review' sh -c "grep -q '^/governance-manifest.json @test-owner$' '$repo/.github/CODEOWNERS' && ! grep -q '^\\* ' '$repo/.github/CODEOWNERS'"
check 'Claude executable hooks are not core-installed' not_exists "$repo/.claude/hooks"
check 'V3 generation is stamped' equals "$(tr -d '\r\n ' < "$repo/.governance-version")" '3.0.0'
check 'Lefthook installs the Git hook' exists "$repo/.git/hooks/pre-commit"
check 'remote profile uses exact-head review while prose stays exempt' jq -e '.review.requiredApprovals == 0 and .review.requireCodeOwnerReview == true and .review.statusContext == "governance/exact-head-review"' "$repo/.github/governance-profile.json"
check 'remote profile defaults extra approval for unattributed changes to true' jq -e '.review.requireExtraApprovalForUnattributedChanges == true' "$repo/.github/governance-profile.json"
check 'review workflow runs protected-base logic without checkout' sh -c "grep -q 'pull_request_target' '$repo/.github/workflows/review-gate.yml' && ! grep -q 'actions/checkout' '$repo/.github/workflows/review-gate.yml'"
repeat_output=$("$kit/new-governed-repo.sh" --target "$repo" --name 'Wrong path' 2>&1); repeat_status=$?
check 'bootstrap refuses to restamp an already governed repository' test "$repeat_status" -ne 0
check 'bootstrap points existing repositories to safe updater' contains "$repeat_output" 'update-governance.sh --dry-run'

# Trust-root consistency: one canonical policy drives CODEOWNERS, the classifier, and the
# legacy git-guard fallback. Drift in either direction must fail closed, and a path added only
# to the canonical policy must reach the classifier with no code edits.
trust_repo="$work/trust-root"
"$kit/new-governed-repo.sh" --target "$trust_repo" --name 'Trust Root Fixture' --owner test-owner >/dev/null
check 'trust root includes the governance ruleset profile' jq -e '.trustRootPaths | index(".github/governance-profile.json")' "$trust_repo/.governance/policy.json"
check 'installed governance structure passes trust-root consistency' sh -c "cd '$trust_repo' && sh scripts/ci/validate-governance.sh >/dev/null"

cp "$trust_repo/.github/CODEOWNERS" "$work/codeowners.orig"
sed -i '/^\/CLAUDE\.md /d' "$trust_repo/.github/CODEOWNERS"
check 'CODEOWNERS missing a trust-root entry fails validation' fails sh -c "cd '$trust_repo' && sh scripts/ci/validate-governance.sh >/dev/null 2>&1"
cp "$work/codeowners.orig" "$trust_repo/.github/CODEOWNERS"

printf '/EXTRA.md @test-owner\n' >> "$trust_repo/.github/CODEOWNERS"
check 'CODEOWNERS with an extra untracked entry fails validation' fails sh -c "cd '$trust_repo' && sh scripts/ci/validate-governance.sh >/dev/null 2>&1"
cp "$work/codeowners.orig" "$trust_repo/.github/CODEOWNERS"
check 'restored CODEOWNERS passes trust-root consistency again' sh -c "cd '$trust_repo' && sh scripts/ci/validate-governance.sh >/dev/null"

git -C "$trust_repo" config user.email test@example.invalid
git -C "$trust_repo" config user.name 'Trust Root Acceptance'
git -C "$trust_repo" switch -q -c feat/trust-root-baseline
git -C "$trust_repo" add -A
git -C "$trust_repo" commit -q -m 'chore: establish trust-root baseline'
git -C "$trust_repo" branch -f main HEAD
jq '.trustRootPaths += ["SECURITY.md"]' "$trust_repo/.governance/policy.json" > "$work/policy.json"
mv "$work/policy.json" "$trust_repo/.governance/policy.json"
printf '/SECURITY.md @test-owner\n' >> "$trust_repo/.github/CODEOWNERS"
git -C "$trust_repo" add -A
git -C "$trust_repo" commit -q -m 'chore: add SECURITY.md as a trust root'
git -C "$trust_repo" branch -f main HEAD
git -C "$trust_repo" switch -q -c feat/edit-security-policy
printf 'security contact policy\n' > "$trust_repo/SECURITY.md"
git -C "$trust_repo" add SECURITY.md
git -C "$trust_repo" commit -q -m 'docs: edit SECURITY.md'
new_trust_root=$(cd "$trust_repo" && sh scripts/ci/classify-change.sh main HEAD)
check 'a policy-only trust-root addition reaches the classifier without code edits' equals "$new_trust_root" 'SECURITY.md'

git -C "$trust_repo" switch -q main
git -C "$trust_repo" switch -q -c feat/attack-shrink-policy
jq '.trustRootPaths -= ["AGENTS.md"]' "$trust_repo/.governance/policy.json" > "$work/policy.json"
mv "$work/policy.json" "$trust_repo/.governance/policy.json"
printf '\nmalicious rule change\n' >> "$trust_repo/AGENTS.md"
git -C "$trust_repo" add -A
git -C "$trust_repo" commit -q -m 'docs: shrink policy and edit AGENTS.md on the same branch'
attack_output=$(cd "$trust_repo" && sh scripts/ci/classify-change.sh main HEAD)
check 'a branch cannot shrink its own trust-root policy to hide its own AGENTS.md edit' contains "$attack_output" '^AGENTS\.md$'

printf 'first\n' > "$repo/first.txt"
git -C "$repo" add first.txt
branch_output=$(cd "$repo" && sh scripts/hooks/no-commit-on-main.sh 2>&1); branch_status=$?
check 'direct commit on protected default branch is refused' test "$branch_status" -ne 0
check 'branch refusal explains the fix' contains "$branch_output" 'Branch first'

git -C "$repo" switch -q -c feat/acceptance
git -C "$repo" add -A
git -C "$repo" commit -q -m 'chore: establish governed baseline'
git -C "$repo" branch -f main HEAD

printf 'not conventional\n' > "$work/message"
(cd "$repo" && sh scripts/hooks/check-commit-message.sh "$work/message" >/dev/null 2>&1); bad_status=$?
check 'non-Conventional commit subject is refused' test "$bad_status" -ne 0
printf 'fix(parser): reject an empty value\n' > "$work/message"
check 'valid Conventional commit subject is accepted' sh -c "cd '$repo' && sh scripts/hooks/check-commit-message.sh '$work/message'"

fake="ghp_$(printf '%s' "acceptance-$$-$(date +%s)" | sha256sum | cut -c1-36)"
printf 'GITHUB_TOKEN=%s\n' "$fake" > "$repo/secret.txt"
git -C "$repo" add secret.txt
secret_output=$(cd "$repo" && gitleaks protect --staged --redact --config .gitleaks.toml 2>&1); secret_status=$?
check 'staged fake credential is refused' test "$secret_status" -ne 0
check 'secret scanner redacts the value' not_contains "$secret_output" "$fake"
git -C "$repo" reset -q HEAD -- secret.txt
rm -f "$repo/secret.txt"

dd if=/dev/zero of="$repo/large.bin" bs=1024 count=2050 2>/dev/null
git -C "$repo" add large.bin
large_output=$(cd "$repo" && sh scripts/hooks/check-large-files.sh 2>&1); large_status=$?
check 'oversized newly added file is refused' test "$large_status" -ne 0
check 'large-file refusal names the limit' contains "$large_output" '2048 KB limit'
git -C "$repo" reset -q HEAD -- large.bin
rm -f "$repo/large.bin"

zero_sha=0000000000000000000000000000000000000000
range_output=$(cd "$repo" && sh scripts/hooks/check-large-files.sh --range "$zero_sha" HEAD 2>&1); range_status=$?
check 'large-file range fails closed for an all-zero base SHA' test "$range_status" -ne 0
check 'large-file range failure explains the invalid comparison' contains "$range_output" 'unable to inspect added files for range'

printf '{"name":"fixture"}\n' > "$repo/package.json"
printf '{"lockfileVersion":3}\n' > "$repo/package-lock.json"
git -C "$repo" add package.json package-lock.json
lock_both=$(cd "$repo" && sh scripts/hooks/check-lockfiles.sh 2>&1)
check 'manifest plus lockfile has no warning' not_contains "$lock_both" 'changed but'
git -C "$repo" commit -q -m 'chore: add dependency fixture'
printf '{"lockfileVersion":3,"drift":true}\n' > "$repo/package-lock.json"
git -C "$repo" add package-lock.json
lock_only=$(cd "$repo" && sh scripts/hooks/check-lockfiles.sh 2>&1)
check 'lockfile-only change is surfaced' contains "$lock_only" 'changed but'
check 'lockfile-only check remains advisory' sh -c "cd '$repo' && sh scripts/hooks/check-lockfiles.sh >/dev/null"
git -C "$repo" reset -q HEAD -- package-lock.json
git -C "$repo" checkout -q -- package-lock.json

git -C "$repo" switch -q main
git -C "$repo" switch -q -c feat/review-state
printf 'print("one")\n' > "$repo/app.py"
git -C "$repo" add app.py
git -C "$repo" commit -q -m 'feat: add behavior'
digest1=$(cd "$repo" && scripts/ci/verify-review.sh --base main --print-digest)
printf 'prose\n' > "$repo/NOTES.md"
git -C "$repo" add NOTES.md
git -C "$repo" commit -q -m 'docs: add notes'
digest2=$(cd "$repo" && scripts/ci/verify-review.sh --base main --print-digest)
check 'prose-only follow-up preserves reviewed code digest' equals "$digest1" "$digest2"
printf 'print("two")\n' >> "$repo/app.py"
git -C "$repo" add app.py
git -C "$repo" commit -q -m 'feat: extend behavior'
digest3=$(cd "$repo" && scripts/ci/verify-review.sh --base main --print-digest)
check 'behavior change invalidates reviewed code digest' test "$digest2" != "$digest3"

cat > "$repo/.governance/review-attestation.json" <<EOF
{"schemaVersion":1,"reviewer":"reviewer-b","implementationAgent":"agent-a","verdict":"PASS","reviewedCommit":"$(git -C "$repo" rev-parse HEAD)","codeDigest":"$digest3","reviewedAt":"2026-09-18T00:00:00Z","findings":"none"}
EOF
review_output=$(cd "$repo" && scripts/ci/verify-review.sh --mode local-attestation --base main 2>&1); review_status=$?
check 'local fallback binds independent identity and exact digest' test "$review_status" -eq 0
check 'local fallback states its trust limitation' contains "$review_output" 'not cryptographically independent'
printf '\npolicy proposal\n' >> "$repo/AGENTS.md"
git -C "$repo" add AGENTS.md
git -C "$repo" commit -q -m 'docs: propose policy change'
(cd "$repo" && scripts/ci/verify-review.sh --mode local-attestation --base main >/dev/null 2>&1); stale_status=$?
check 'governance Markdown is substantive and invalidates review' test "$stale_status" -ne 0

# Pinned V2 fixtures exercise known-hash migration without depending on a moving branch.
legacy="$work/v2-project"
mkdir -p "$legacy/scripts/hooks"
printf 'legacy policy\n' > "$legacy/AGENTS.md"
printf 'project source\n' > "$legacy/source.txt"
cp "$kit/tests/fixtures/v2/no-commit-on-main.sh" "$legacy/scripts/hooks/no-commit-on-main.sh"
cp "$kit/tests/fixtures/v2/lefthook.yml" "$legacy/lefthook.yml"
printf '2.0.0\n' > "$legacy/.governance-version"
dry_output=$("$kit/update-governance.sh" --target "$legacy" --dry-run 2>&1); dry_status=$?
check 'V2 migration dry-run succeeds' test "$dry_status" -eq 0
check 'V2 gate is recognized as upgradeable' contains "$dry_output" 'UPGRADE.*scripts/hooks/no-commit-on-main.sh'
check 'V3 remote workflow is planned as an addition' contains "$dry_output" 'ADD.*.github/workflows/governance.yml'
check 'dry-run performs no write' not_exists "$legacy/.github/workflows/governance.yml"
"$kit/update-governance.sh" --target "$legacy" >/dev/null
check 'migration installs V3 workflow' exists "$legacy/.github/workflows/governance.yml"
check 'migration leaves project source untouched' equals "$(cat "$legacy/source.txt")" 'project source'
check 'migration backs up replaced V2 gate' sh -c "find '$legacy/.governance-backup' -name no-commit-on-main.sh -type f | grep -q ."
second_output=$("$kit/update-governance.sh" --target "$legacy" 2>&1); second_status=$?
check 'second migration run is idempotent' test "$second_status" -eq 0
check 'second run reports current' contains "$second_output" 'Already current'

custom="$work/v2-customized"
mkdir -p "$custom/scripts/hooks"
printf 'legacy policy\n' > "$custom/AGENTS.md"
cp "$kit/tests/fixtures/v2/no-commit-on-main.sh" "$custom/scripts/hooks/no-commit-on-main.sh"
printf '\n# project-specific branch policy\n' >> "$custom/scripts/hooks/no-commit-on-main.sh"
printf '2.0.0\n' > "$custom/.governance-version"
custom_before=$(sha256sum "$custom/scripts/hooks/no-commit-on-main.sh" | awk '{print $1}')
custom_plan=$("$kit/update-governance.sh" --target "$custom" --dry-run 2>&1)
check 'migration detects a customized known V2 gate' contains "$custom_plan" 'CONFLICT.*scripts/hooks/no-commit-on-main.sh'
"$kit/update-governance.sh" --target "$custom" >/dev/null
custom_after=$(sha256sum "$custom/scripts/hooks/no-commit-on-main.sh" | awk '{print $1}')
check 'migration preserves customized gate byte-for-byte' equals "$custom_before" "$custom_after"
check 'migration does not claim V3 while conflicts remain' equals "$(tr -d '\r\n ' < "$custom/.governance-version")" '2.0.0'

fake_home="$work/home"
mkdir -p "$fake_home/.codex"
printf 'personal instruction\n' > "$fake_home/.codex/AGENTS.md"
global_plan=$(HOME="$fake_home" "$kit/update-global-rules.sh" --agent codex --dry-run 2>&1)
check 'global bootstrap dry-run writes nothing' not_contains "$(cat "$fake_home/.codex/AGENTS.md")" 'BEGIN repo-governance'
check 'global bootstrap dry-run reports its mode' contains "$global_plan" 'Dry run: nothing was written'
HOME="$fake_home" "$kit/update-global-rules.sh" --agent codex >/dev/null
global_once=$(sha256sum "$fake_home/.codex/AGENTS.md" | awk '{print $1}')
HOME="$fake_home" "$kit/update-global-rules.sh" --agent codex >/dev/null
global_twice=$(sha256sum "$fake_home/.codex/AGENTS.md" | awk '{print $1}')
check 'global bootstrap preserves personal instructions' contains "$(cat "$fake_home/.codex/AGENTS.md")" 'personal instruction'
check 'global bootstrap is idempotent' equals "$global_once" "$global_twice"
check 'global bootstrap creates a recoverable backup' sh -c "find '$fake_home/.codex' -name 'AGENTS.md.bak-*' -type f | grep -q ."

sync_repo="$work/sync"
sync_origin="$work/origin.git"
sync_mirror="$work/mirror.git"
git init -q --bare "$sync_origin"
git init -q --bare "$sync_mirror"
git init -q -b main "$sync_repo"
git -C "$sync_repo" config user.email test@example.invalid
git -C "$sync_repo" config user.name 'Remote Sync Acceptance'
printf 'one\n' > "$sync_repo/state.txt"
git -C "$sync_repo" add state.txt
git -C "$sync_repo" commit -q -m 'chore: initialize sync fixture'
git -C "$sync_repo" remote add origin "$sync_origin"
git -C "$sync_repo" remote add mirror "$sync_mirror"
git -C "$sync_repo" push -q origin main
git -C "$sync_repo" push -q mirror main
equal_sync=$("$kit/sync-remotes.sh" --repo "$sync_repo" --dry-run 2>&1)
check 'Linux remote sync is a no-op when copies agree' contains "$equal_sync" 'already at the same commit'
printf 'two\n' >> "$sync_repo/state.txt"
git -C "$sync_repo" add state.txt
git -C "$sync_repo" commit -q -m 'chore: advance authority'
git -C "$sync_repo" push -q origin main
mirror_before=$(git -C "$sync_mirror" rev-parse main)
sync_plan=$("$kit/sync-remotes.sh" --repo "$sync_repo" --dry-run 2>&1)
check 'remote sync dry-run plans the lagging mirror' contains "$sync_plan" 'fast-forward mirror'
check 'remote sync dry-run pushes nothing' equals "$(git -C "$sync_mirror" rev-parse main)" "$mirror_before"
"$kit/sync-remotes.sh" --repo "$sync_repo" >/dev/null
check 'remote sync fast-forwards without force' equals "$(git -C "$sync_mirror" rev-parse main)" "$(git -C "$sync_origin" rev-parse main)"

other="$work/other"
git clone -q --branch main "$sync_mirror" "$other"
git -C "$other" config user.email test@example.invalid
git -C "$other" config user.name 'Other Writer'
printf 'mirror-only\n' > "$other/mirror.txt"
git -C "$other" add mirror.txt
git -C "$other" commit -q -m 'chore: mirror-only work'
git -C "$other" push -q origin main
printf 'authority-only\n' > "$sync_repo/authority.txt"
git -C "$sync_repo" add authority.txt
git -C "$sync_repo" commit -q -m 'chore: authority-only work'
git -C "$sync_repo" push -q origin main
origin_before=$(git -C "$sync_origin" rev-parse main)
mirror_diverged_before=$(git -C "$sync_mirror" rev-parse main)
diverged_output=$("$kit/sync-remotes.sh" --repo "$sync_repo" 2>&1); diverged_status=$?
check 'remote sync refuses genuinely divergent histories' test "$diverged_status" -ne 0
check 'remote sync explains divergence' contains "$diverged_output" 'divergent work'
check 'divergence refusal leaves authoritative remote untouched' equals "$(git -C "$sync_origin" rev-parse main)" "$origin_before"
check 'divergence refusal leaves mirror untouched' equals "$(git -C "$sync_mirror" rev-parse main)" "$mirror_diverged_before"

# A fake gh proves plan mode is non-mutating without touching real repository settings.
fake_bin="$work/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  'api repos/example/project') printf '%s\n' '{"default_branch":"main","visibility":"public"}' ;;
  'api repos/example/project/rulesets') printf '%s\n' '[]' ;;
  *) printf '%s\n' "$*" >> "$GOVERNANCE_FAKE_GH_MUTATIONS"; printf '%s\n' '{}' ;;
esac
EOF
chmod +x "$fake_bin/gh"
mutation_log="$work/mutations"
: > "$mutation_log"
plan_output=$(PATH="$fake_bin:$PATH" GOVERNANCE_FAKE_GH_MUTATIONS="$mutation_log" "$kit/github-governance.sh" --repo example/project 2>&1); plan_status=$?
check 'GitHub policy command defaults to plan mode' test "$plan_status" -eq 0
check 'GitHub plan clearly says no settings changed' contains "$plan_output" 'PLAN ONLY'
check 'GitHub plan makes no mutation call' test ! -s "$mutation_log"
apply_output=$(PATH="$fake_bin:$PATH" GOVERNANCE_FAKE_GH_MUTATIONS="$mutation_log" "$kit/github-governance.sh" --repo example/project --apply 2>&1); apply_status=$?
check 'GitHub apply refuses an unresolved governance owner' test "$apply_status" -ne 0
check 'GitHub apply explains the unresolved owner' contains "$apply_output" 'replace <owner>|Replace <owner>'
check 'refused GitHub apply still makes no mutation call' test ! -s "$mutation_log"

# A second fake gh with a resolvable owner captures the ruleset payload itself, so explicit
# false/0 review settings can be proven to survive into the applied pull_request rule instead of
# being silently replaced by the static template's hardcoded true values (or, worse, by jq's `//`
# treating an explicit `false` as if it were missing).
fake_bin_ruleset="$work/fake-bin-ruleset"
mkdir -p "$fake_bin_ruleset"
cat > "$fake_bin_ruleset/gh" <<'EOF'
#!/bin/sh
input_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--input" ]; then input_file=$arg; fi
  prev=$arg
done
case "$*" in
  'api repos/owner/repo/rulesets')
    printf '%s\n' '[]' ;;
  'api repos/owner/repo')
    printf '%s\n' '{"default_branch":"main","visibility":"public"}' ;;
  *'repos/owner/repo/rulesets'*'--input'*)
    if [ -n "$input_file" ] && [ -n "${GOVERNANCE_FAKE_GH_RULESET_CAPTURE:-}" ]; then
      cp "$input_file" "$GOVERNANCE_FAKE_GH_RULESET_CAPTURE"
    fi
    printf '%s\n' '{}' ;;
  *)
    printf '%s\n' '{}' ;;
esac
EOF
chmod +x "$fake_bin_ruleset/gh"

explicit_false_profile="$work/profile-explicit-false.json"
jq -n '{
  schemaVersion: 1, profileName: "Test", defaultBranch: "main", governanceOwner: "owner",
  rulesetName: "test-ruleset",
  requiredStatusChecks: ["Governance / invariants", "governance/exact-head-review"],
  review: {
    requiredApprovals: 0, dismissStaleApprovals: false, requireCodeOwnerReview: false,
    requireLastPushApproval: false, requireExtraApprovalForUnattributedChanges: false,
    requireConversationResolution: true,
    statusContext: "governance/exact-head-review", preferredTrustedIntegrationId: 15368,
    externalReviewerAppId: null, requireIndependentReview: false
  },
  history: {requirePullRequest: true, requireLinearHistory: true, blockForcePush: true, blockDeletion: true},
  actions: {defaultWorkflowPermissions: "read", canApprovePullRequestReviews: false}
}' > "$explicit_false_profile"

explicit_true_profile="$work/profile-explicit-true.json"
jq -n '{
  schemaVersion: 1, profileName: "Test", defaultBranch: "main", governanceOwner: "owner",
  rulesetName: "test-ruleset",
  requiredStatusChecks: ["Governance / invariants", "governance/exact-head-review"],
  review: {
    requiredApprovals: 0, dismissStaleApprovals: false, requireCodeOwnerReview: false,
    requireLastPushApproval: false, requireExtraApprovalForUnattributedChanges: true,
    requireConversationResolution: true,
    statusContext: "governance/exact-head-review", preferredTrustedIntegrationId: 15368,
    externalReviewerAppId: null, requireIndependentReview: false
  },
  history: {requirePullRequest: true, requireLinearHistory: true, blockForcePush: true, blockDeletion: true},
  actions: {defaultWorkflowPermissions: "read", canApprovePullRequestReviews: false}
}' > "$explicit_true_profile"

missing_fields_profile="$work/profile-missing-fields.json"
jq -n '{
  schemaVersion: 1, profileName: "Test", defaultBranch: "main", governanceOwner: "owner",
  rulesetName: "test-ruleset",
  requiredStatusChecks: ["Governance / invariants", "governance/exact-head-review"],
  review: {
    statusContext: "governance/exact-head-review", preferredTrustedIntegrationId: 15368
  },
  history: {requirePullRequest: true, requireLinearHistory: true, blockForcePush: true, blockDeletion: true},
  actions: {defaultWorkflowPermissions: "read", canApprovePullRequestReviews: false}
}' > "$missing_fields_profile"

ruleset_capture_sh="$work/ruleset-explicit-false-sh.json"
PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_sh" \
  "$kit/github-governance.sh" --repo owner/repo --profile "$explicit_false_profile" --apply >/dev/null 2>&1
pr_params_sh() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_sh"; }
check 'sh: explicit requireCodeOwnerReview=false survives into the ruleset' equals "$(pr_params_sh require_code_owner_review)" 'false'
check 'sh: explicit requireLastPushApproval=false survives into the ruleset' equals "$(pr_params_sh require_last_push_approval)" 'false'
check 'sh: explicit dismissStaleApprovals=false survives into the ruleset' equals "$(pr_params_sh dismiss_stale_reviews_on_push)" 'false'
check 'sh: requiredApprovals=0 reaches the ruleset' equals "$(pr_params_sh required_approving_review_count)" '0'
check 'sh: explicit requireExtraApprovalForUnattributedChanges=false survives into the ruleset' equals "$(pr_params_sh require_extra_approval_for_unattributed_changes)" 'false'

ruleset_capture_sh_true="$work/ruleset-explicit-true-sh.json"
PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_sh_true" \
  "$kit/github-governance.sh" --repo owner/repo --profile "$explicit_true_profile" --apply >/dev/null 2>&1
pr_params_sh_true() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_sh_true"; }
check 'sh: explicit requireExtraApprovalForUnattributedChanges=true survives into the ruleset' equals "$(pr_params_sh_true require_extra_approval_for_unattributed_changes)" 'true'

ruleset_capture_sh_defaults="$work/ruleset-missing-fields-sh.json"
PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_sh_defaults" \
  "$kit/github-governance.sh" --repo owner/repo --profile "$missing_fields_profile" --apply >/dev/null 2>&1
pr_params_sh_defaults() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_sh_defaults"; }
check 'sh: missing requireCodeOwnerReview defaults to true (fails closed)' equals "$(pr_params_sh_defaults require_code_owner_review)" 'true'
check 'sh: missing requireLastPushApproval defaults to true (fails closed)' equals "$(pr_params_sh_defaults require_last_push_approval)" 'true'
check 'sh: missing dismissStaleApprovals defaults to true (fails closed)' equals "$(pr_params_sh_defaults dismiss_stale_reviews_on_push)" 'true'
check 'sh: missing requireExtraApprovalForUnattributedChanges defaults to true (fails closed)' equals "$(pr_params_sh_defaults require_extra_approval_for_unattributed_changes)" 'true'

if command -v pwsh >/dev/null 2>&1 && pwsh -NoLogo -NoProfile -Command 'exit 0' >/dev/null 2>&1; then
  ruleset_capture_ps="$work/ruleset-explicit-false-ps.json"
  PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_ps" \
    pwsh -NoLogo -NoProfile -File "$kit/github-governance.ps1" -Repo owner/repo -Profile "$explicit_false_profile" -Apply >/dev/null 2>&1
  pr_params_ps() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_ps"; }
  check 'PowerShell: explicit requireCodeOwnerReview=false survives into the ruleset' equals "$(pr_params_ps require_code_owner_review)" 'false'
  check 'PowerShell: explicit requireLastPushApproval=false survives into the ruleset' equals "$(pr_params_ps require_last_push_approval)" 'false'
  check 'PowerShell: explicit requireExtraApprovalForUnattributedChanges=false survives into the ruleset' equals "$(pr_params_ps require_extra_approval_for_unattributed_changes)" 'false'
  check 'shell and PowerShell implementations agree on the pull_request rule parameters' \
    equals "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_sh")" \
           "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_ps")"

  ruleset_capture_ps_true="$work/ruleset-explicit-true-ps.json"
  PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_ps_true" \
    pwsh -NoLogo -NoProfile -File "$kit/github-governance.ps1" -Repo owner/repo -Profile "$explicit_true_profile" -Apply >/dev/null 2>&1
  pr_params_ps_true() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_ps_true"; }
  check 'PowerShell: explicit requireExtraApprovalForUnattributedChanges=true survives into the ruleset' equals "$(pr_params_ps_true require_extra_approval_for_unattributed_changes)" 'true'
  check 'sh and PowerShell agree on requireExtraApprovalForUnattributedChanges=true' \
    equals "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_sh_true")" \
           "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_ps_true")"

  ruleset_capture_ps_defaults="$work/ruleset-missing-fields-ps.json"
  PATH="$fake_bin_ruleset:$PATH" GOVERNANCE_FAKE_GH_RULESET_CAPTURE="$ruleset_capture_ps_defaults" \
    pwsh -NoLogo -NoProfile -File "$kit/github-governance.ps1" -Repo owner/repo -Profile "$missing_fields_profile" -Apply >/dev/null 2>&1
  pr_params_ps_defaults() { jq -r --arg key "$1" '.rules[] | select(.type == "pull_request") | .parameters[$key]' "$ruleset_capture_ps_defaults"; }
  check 'PowerShell: missing requireExtraApprovalForUnattributedChanges defaults to true (fails closed)' equals "$(pr_params_ps_defaults require_extra_approval_for_unattributed_changes)" 'true'
  check 'sh and PowerShell agree on missing-field defaults' \
    equals "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_sh_defaults")" \
           "$(jq -Sc '.rules[] | select(.type == "pull_request") | .parameters' "$ruleset_capture_ps_defaults")"
else
  echo 'PowerShell is unavailable; skipping the sh/PowerShell ruleset-equivalence check.' >&2
fi

ps_bootstrap=$(cat "$kit/new-governed-repo.ps1")
ps_updater=$(cat "$kit/update-governance.ps1")
ps_remote=$(cat "$kit/github-governance.ps1")
check '[static Windows] PowerShell bootstrap maps V3 policy, hooks, and both workflows' contains "$ps_bootstrap" 'review-gate.template.yml.*.github/workflows/review-gate.yml'
check '[static Windows] PowerShell bootstrap omits required Claude executable hooks' not_contains "$ps_bootstrap" "git-guard.template.ps1.*.claude/hooks"
check '[static Windows] PowerShell updater supports add-only project files' contains "$ps_updater" "mode -eq 'add-only'"
# The literal PowerShell variable is the assertion target.
# shellcheck disable=SC2016
check '[static Windows] GitHub mutation requires explicit Apply switch' contains "$ps_remote" 'if \(-not \$Apply\)'

manifest_bad=0
jq -c '.files[]' "$kit/governance-manifest.json" | while IFS= read -r entry; do
  file=$(printf '%s' "$entry" | jq -r .template)
  expected=$(printf '%s' "$entry" | jq -r .sha256)
  actual=$(sed 's/\r$//' "$kit/$file" | sha256sum | awk '{print $1}')
  [ "$actual" = "$expected" ] || { echo "$file" > "$work/manifest-bad"; break; }
done
[ -f "$work/manifest-bad" ] && manifest_bad=1
check 'manifest hashes match every shipped template' test "$manifest_bad" -eq 0
private_pattern='tail[0-9a-z]+\.ts\.net|192\.168\.[0-9]+\.[0-9]+|mini''sforum|tail''scale|server-''router/[0-9A-Za-z]|/var/back''ups/|home por''tal|loopback dash''board'
check 'kit contains no private server topology markers' sh -c "! grep -R -Ei '$private_pattern' '$kit' --exclude-dir=.git >/dev/null"
check 'reachable Git blobs contain no private infrastructure markers' reachable_content_is_clean "$kit" "$private_pattern"
check 'reachable Git metadata contains no private infrastructure markers' reachable_metadata_is_clean "$kit" "$private_pattern"

metadata_repo="$work/metadata-leak"
git init -q -b main "$metadata_repo"
git -C "$metadata_repo" config user.name 'Metadata Acceptance'
git -C "$metadata_repo" config user.email test@example.invalid
printf 'baseline\n' > "$metadata_repo/state.txt"
git -C "$metadata_repo" add state.txt
git -C "$metadata_repo" commit -q -m 'chore: establish metadata fixture'
printf 'identity leak\n' >> "$metadata_repo/state.txt"
git -C "$metadata_repo" add state.txt
forbidden_metadata_host='fixture.''tailacceptance''.ts.net'
GIT_AUTHOR_NAME='Metadata Acceptance' GIT_AUTHOR_EMAIL="author@noreply.$forbidden_metadata_host" \
GIT_COMMITTER_NAME='Metadata Acceptance' GIT_COMMITTER_EMAIL="committer@noreply.$forbidden_metadata_host" \
  git -C "$metadata_repo" commit -q -m 'test: exercise forbidden identity metadata'
check 'forbidden author and committer metadata is rejected' fails reachable_metadata_is_clean "$metadata_repo" "$private_pattern"

tag_repo="$work/tag-metadata-leak"
git init -q -b main "$tag_repo"
git -C "$tag_repo" config user.name 'Metadata Acceptance'
git -C "$tag_repo" config user.email test@example.invalid
printf 'baseline\n' > "$tag_repo/state.txt"
git -C "$tag_repo" add state.txt
git -C "$tag_repo" commit -q -m 'chore: establish tag fixture'
GIT_COMMITTER_NAME='Metadata Acceptance' GIT_COMMITTER_EMAIL="tagger@noreply.$forbidden_metadata_host" \
  git -C "$tag_repo" tag -a metadata-fixture -m 'test: exercise forbidden tagger metadata'
check 'forbidden tagger metadata is rejected' fails reachable_metadata_is_clean "$tag_repo" "$private_pattern"

sibling_repo="$work/sibling-content-leak"
git init -q -b main "$sibling_repo"
git -C "$sibling_repo" config user.name 'Content Acceptance'
git -C "$sibling_repo" config user.email test@example.invalid
printf 'public baseline\n' > "$sibling_repo/state.txt"
git -C "$sibling_repo" add state.txt
git -C "$sibling_repo" commit -q -m 'chore: establish content fixture'
git -C "$sibling_repo" switch -q -c feat/stale-private-content
forbidden_content='private tail''scale ingress'
printf '%s\n' "$forbidden_content" > "$sibling_repo/private.txt"
git -C "$sibling_repo" add private.txt
git -C "$sibling_repo" commit -q -m 'test: exercise sibling branch content scan'
git -C "$sibling_repo" switch -q main
check 'forbidden content on a sibling branch is rejected' fails reachable_content_is_clean "$sibling_repo" "$private_pattern"
check 'all shell entry points parse' sh -c "sh -n '$kit'/*.sh '$kit'/*.template.sh '$kit'/scripts/ci/*.sh"

printf '\nPASS: %s  FAIL: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
