#!/bin/sh
# Deterministically classify a branch diff. Governance is always substantive; prose is exempt
# by file type, never by directory name.
set -eu

base=${1:-}
head=${2:-HEAD}

if [ -z "$base" ]; then
  for ref in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      base=$(git merge-base "$head" "$ref")
      break
    fi
  done
fi

[ -n "$base" ] || {
  echo "Unable to determine the default-branch base; classification fails closed." >&2
  exit 2
}

is_trust_root() {
  case "$1" in
    AGENTS.md|REPO_RULES.md|.governance-version|.governance/*|governance-manifest.json|governance-policy.template.json|new-governed-repo.sh|new-governed-repo.ps1|update-governance.sh|update-governance.ps1|update-global-rules.sh|update-global-rules.ps1|github-governance.sh|github-governance.ps1|sync-remotes.sh|sync-remotes.ps1|github/*|lefthook.yml|.gitleaks.toml|scripts/hooks/*|scripts/ci/*|.github/workflows/*|.github/CODEOWNERS|.github/governance-profile.json|CLAUDE.md|GEMINI.md|.cursor/*|.claude/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_prose() {
  is_trust_root "$1" && return 1
  case "$1" in
    *.md|*.markdown|*.txt|*.rst|*.adoc|WORKLOG|CHANGELOG|CHANGES|NOTICE|LICENCE|LICENSE|AUTHORS|CONTRIBUTORS|README) return 0 ;;
    *) return 1 ;;
  esac
}

git -c core.quotePath=false diff --name-only "$base" "$head" | while IFS= read -r path; do
  [ -n "$path" ] || continue
  if ! is_prose "$path"; then
    printf '%s\n' "$path"
  fi
done
