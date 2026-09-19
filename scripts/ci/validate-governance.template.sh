#!/bin/sh
# CI consistency checks for an installed governed repository and for this template kit.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

required='AGENTS.md
REPO_RULES.md
.governance-version
.governance/policy.json
lefthook.yml
.gitleaks.toml
scripts/hooks/no-commit-on-main.sh
scripts/hooks/check-large-files.sh
scripts/hooks/check-lockfiles.sh
scripts/hooks/check-commit-message.sh
scripts/ci/classify-change.sh
scripts/ci/verify-review.sh
.github/workflows/governance.yml
.github/workflows/review-gate.yml
.github/CODEOWNERS
.github/governance-profile.json'

# The kit stores templates rather than active installed names.
if [ -f governance-manifest.json ] && [ -f AGENTS.template.md ]; then
  required='AGENTS.template.md
REPO_RULES.template.md
governance-manifest.json
governance-policy.template.json
lefthook.template.yml
gitleaks.template.toml
no-commit-on-main.template.sh
check-large-files.template.sh
check-lockfiles.template.sh
check-commit-message.template.sh
scripts/ci/classify-change.template.sh
scripts/ci/verify-review.template.sh'
else
  version=$(tr -d '\r\n ' < .governance-version 2>/dev/null || true)
  case "$version" in 3.*) ;; *) echo "Expected governance generation 3.x, found '$version'." >&2; exit 1 ;; esac
fi

missing=0
printf '%s\n' "$required" | while IFS= read -r path; do
  [ -e "$path" ] || { echo "Missing governance file: $path" >&2; echo 1 > "${TMPDIR:-/tmp}/governance-missing-$$"; }
done
flag="${TMPDIR:-/tmp}/governance-missing-$$"
if [ -f "$flag" ]; then rm -f "$flag"; missing=1; fi
[ "$missing" -eq 0 ] || exit 1

if [ -f governance-manifest.json ] && [ -f AGENTS.template.md ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required to validate the kit manifest." >&2; exit 2; }
  command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required to validate the kit manifest." >&2; exit 2; }
  mismatch=0
  manifest_flag="${TMPDIR:-/tmp}/governance-manifest-mismatch-$$"
  jq -c '.files[]' governance-manifest.json | while IFS= read -r entry; do
    template=$(printf '%s' "$entry" | jq -r .template)
    expected=$(printf '%s' "$entry" | jq -r .sha256)
    if [ ! -f "$template" ]; then
      echo "Manifest template missing: $template" >&2
      echo 1 > "$manifest_flag"
      continue
    fi
    actual=$(sed 's/\r$//' "$template" | sha256sum | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
      echo "Manifest hash is stale for $template" >&2
      echo 1 > "$manifest_flag"
    fi
  done
  if [ -f "$manifest_flag" ]; then rm -f "$manifest_flag"; mismatch=1; fi
  [ "$mismatch" -eq 0 ] || exit 1
fi

if [ -f .github/workflows/governance.yml ]; then
  if grep -Eq 'uses:[[:space:]]+[^#[:space:]]+@(v[0-9]+|main|master)([[:space:]]+#.*)?$' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null; then
    echo "Workflow action is pinned to a movable ref instead of a commit SHA." >&2
    exit 1
  fi
fi

echo "Governance structure and version are consistent."
