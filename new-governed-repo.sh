#!/bin/sh
# Bootstrap Repo Governance V3 on Linux/Omarchy or any POSIX environment.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
target=.
name=
owner='<owner>'
with_optional=false
force=false
no_git=false
no_lefthook=false

usage() {
  echo "usage: $0 [--target DIR] [--name NAME] [--owner GITHUB_LOGIN] [--with-optional] [--force] [--no-git] [--no-lefthook]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    --owner) owner=$2; shift 2 ;;
    --with-optional) with_optional=true; shift ;;
    --force) force=true; shift ;;
    --no-git) no_git=true; shift ;;
    --no-lefthook) no_lefthook=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$target"
target=$(CDPATH='' cd -- "$target" && pwd)
if { [ -f "$target/AGENTS.md" ] || [ -f "$target/.governance-version" ]; } && [ "$force" != true ]; then
  echo "Refused: $target is already governed. Use update-governance.sh --dry-run instead." >&2
  exit 1
fi
echo "Scaffolding governance into: $target"

copy_one() {
  source_rel=$1
  dest_rel=$2
  source_path="$script_dir/$source_rel"
  dest_path="$target/$dest_rel"
  [ -f "$source_path" ] || { echo "Missing template: $source_rel" >&2; exit 1; }
  if [ -e "$dest_path" ] && [ "$force" != true ]; then
    echo "  skip (exists): $dest_rel"
    return
  fi
  mkdir -p "$(dirname -- "$dest_path")"
  cp "$source_path" "$dest_path"
  echo "  + $dest_rel"
}

while IFS='|' read -r source_rel dest_rel; do
  [ -n "$source_rel" ] || continue
  copy_one "$source_rel" "$dest_rel"
done <<'MAP'
AGENTS.template.md|AGENTS.md
CLAUDE.template.md|CLAUDE.md
GEMINI.template.md|GEMINI.md
REPO_RULES.template.md|REPO_RULES.md
PRD.template.md|PRD.md
WORKLOG.template.md|WORKLOG.md
SPEC.template.md|SPEC.template.md
gitignore.template|.gitignore
gitattributes.template|.gitattributes
lefthook.template.yml|lefthook.yml
no-commit-on-main.template.sh|scripts/hooks/no-commit-on-main.sh
check-large-files.template.sh|scripts/hooks/check-large-files.sh
check-lockfiles.template.sh|scripts/hooks/check-lockfiles.sh
check-commit-message.template.sh|scripts/hooks/check-commit-message.sh
gitleaks.template.toml|.gitleaks.toml
governance-policy.template.json|.governance/policy.json
review-attestation.template.json|.governance/review-attestation.example.json
scripts/ci/classify-change.template.sh|scripts/ci/classify-change.sh
scripts/ci/verify-review.template.sh|scripts/ci/verify-review.sh
scripts/ci/validate-governance.template.sh|scripts/ci/validate-governance.sh
project-checks.template.sh|scripts/ci/project-checks.sh
github/workflows/governance.template.yml|.github/workflows/governance.yml
github/workflows/review-gate.template.yml|.github/workflows/review-gate.yml
github/CODEOWNERS.template|.github/CODEOWNERS
github/governance-profile.json|.github/governance-profile.json
cursor-rules.template.mdc|.cursor/rules/agents.mdc
MAP

version=$(sed -n 's/.*"governanceVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$script_dir/governance-manifest.json" | sed -n '1p')
[ -n "$version" ] || { echo "Could not read governance version." >&2; exit 1; }
printf '%s\n' "$version" > "$target/.governance-version"

if [ -n "$name" ]; then
  escaped=$(printf '%s' "$name" | sed 's/[\\&|]/\\&/g')
  for path in AGENTS.md CLAUDE.md GEMINI.md REPO_RULES.md PRD.md WORKLOG.md .gitleaks.toml; do
    [ -f "$target/$path" ] || continue
    tmp="$target/$path.tmp.$$"
    sed "s|<PROJECT_NAME>|$escaped|g" "$target/$path" > "$tmp"
    mv "$tmp" "$target/$path"
  done
fi

escaped_owner=$(printf '%s' "$owner" | sed 's/[\\&|]/\\&/g')
for path in .github/CODEOWNERS .github/governance-profile.json; do
  [ -f "$target/$path" ] || continue
  tmp="$target/$path.tmp.$$"
  sed "s|<owner>|$escaped_owner|g" "$target/$path" > "$tmp"
  mv "$tmp" "$target/$path"
done

chmod +x "$target"/scripts/hooks/*.sh "$target"/scripts/ci/*.sh

if [ "$with_optional" = true ]; then
  mkdir -p "$target/optional"
  cp -R "$script_dir/optional/." "$target/optional/"
  echo "  + optional/"
fi

if [ "$no_git" != true ] && [ ! -d "$target/.git" ]; then
  command -v git >/dev/null 2>&1 || { echo "git is required unless --no-git is used." >&2; exit 1; }
  git -C "$target" init -q -b main 2>/dev/null || {
    git -C "$target" init -q
    git -C "$target" symbolic-ref HEAD refs/heads/main
  }
  echo "  git initialized (branch: main)"
fi

if [ "$no_git" != true ] && [ "$no_lefthook" != true ]; then
  if command -v lefthook >/dev/null 2>&1; then
    (cd "$target" && lefthook install >/dev/null)
    echo "  lefthook installed"
  else
    echo "  warning: lefthook is not installed; install it, then run 'lefthook install' in the project." >&2
  fi
fi

echo "Done. Fill the project brief and placeholders, configure project checks, branch, and commit governance before product code."
