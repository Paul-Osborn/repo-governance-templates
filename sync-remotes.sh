#!/bin/sh
# Safely converge one branch across a repository's remotes without force-pushing.
set -eu

repo=.
branch=
dry_run=false

usage() { echo "usage: $0 [--repo DIR] [--branch NAME] [--dry-run]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --branch) branch=$2; shift 2 ;;
    --dry-run|--plan) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || { echo "Not a Git repository: $repo" >&2; exit 2; }
remotes=$(git -C "$root" remote)
[ -n "$remotes" ] || { echo "No remotes configured. Nothing to synchronize."; exit 0; }
if printf '%s\n' "$remotes" | grep -qx origin; then authoritative=origin
else authoritative=$(printf '%s\n' "$remotes" | sed -n '1p')
fi

rev() { git -C "$root" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null || true; }
ancestor() { git -C "$root" merge-base --is-ancestor "$1" "$2" >/dev/null 2>&1; }

if [ -z "$branch" ]; then
  remote_head=$(git -C "$root" symbolic-ref --short -q "refs/remotes/$authoritative/HEAD" 2>/dev/null || true)
  branch=${remote_head#"$authoritative"/}
  if [ -z "$branch" ]; then
    if [ -n "$(rev "refs/remotes/$authoritative/main")" ]; then branch=main; else branch=master; fi
  fi
fi

echo "Repository: $root"
echo "Branch: $branch"
echo "Authoritative: $authoritative"
[ "$dry_run" = true ] && echo "Mode: DRY RUN -- nothing will be pushed"

for remote in $remotes; do
  if ! git -C "$root" fetch "$remote" --prune --quiet; then
    echo "Refused: could not read remote '$remote'; nothing was changed." >&2
    exit 1
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
copies="$tmp/copies"
local_sha=$(rev "refs/heads/$branch")
[ -z "$local_sha" ] || printf 'local|local|%s\n' "$local_sha" >> "$copies"
for remote in $remotes; do
  sha=$(rev "refs/remotes/$remote/$branch")
  [ -z "$sha" ] || printf '%s|remote|%s\n' "$remote" "$sha" >> "$copies"
done
[ -s "$copies" ] || { echo "Branch '$branch' does not exist locally or remotely." >&2; exit 1; }

newest=
newest_name=
while IFS='|' read -r name kind sha; do
  printf '  %-12s %.8s\n' "$name" "$sha"
  if [ -z "$newest" ]; then newest=$sha; newest_name=$name; continue; fi
  [ "$sha" = "$newest" ] && continue
  if ancestor "$newest" "$sha"; then newest=$sha; newest_name=$name
  elif ancestor "$sha" "$newest"; then :
  else
    echo "REFUSED: '$name' and '$newest_name' contain divergent work. Nothing was changed." >&2
    exit 1
  fi
done < "$copies"

behind="$tmp/behind"
while IFS='|' read -r name kind sha; do
  [ "$sha" = "$newest" ] || printf '%s|%s|%s\n' "$name" "$kind" "$sha" >> "$behind"
done < "$copies"
for remote in $remotes; do
  if ! awk -F '|' -v wanted="$remote" '$1 == wanted { found=1 } END { exit !found }' "$copies"; then
    printf '%s|remote|\n' "$remote" >> "$behind"
  fi
done

if [ ! -s "$behind" ]; then echo "All copies are already at the same commit."; exit 0; fi
while IFS='|' read -r name kind sha; do
  if [ -n "$sha" ]; then echo "  fast-forward $name"; else echo "  create $name"; fi
done < "$behind"
[ "$dry_run" = true ] && { echo "Dry run: nothing pushed."; exit 0; }

failed=
while IFS='|' read -r name kind sha; do
  if [ "$kind" = local ]; then
    current=$(git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null || true)
    if [ "$current" = "$branch" ]; then
      if [ -n "$(git -C "$root" status --porcelain)" ]; then
        echo "Refused: local '$branch' is checked out with uncommitted changes." >&2
        failed="$failed local"
        continue
      fi
      git -C "$root" merge --ff-only --quiet "$newest" || failed="$failed local"
    else
      git -C "$root" update-ref "refs/heads/$branch" "$newest" || failed="$failed local"
    fi
  else
    git -C "$root" push "$name" "$newest:refs/heads/$branch" >/dev/null || failed="$failed $name"
  fi
done < "$behind"

[ -z "$failed" ] || { echo "Failed to update:$failed. Nothing was forced." >&2; exit 1; }
echo "All copies of '$branch' now agree at $(printf '%.8s' "$newest")."
