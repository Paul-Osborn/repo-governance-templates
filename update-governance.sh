#!/bin/sh
# Safely migrate/update manifest-owned governance controls on POSIX systems.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
target=.
dry_run=false
no_backup=false
backup_dir=

usage() { echo "usage: $0 [--target DIR] [--dry-run] [--backup-dir DIR] [--no-backup]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target=$2; shift 2 ;;
    --dry-run|--plan) dry_run=true; shift ;;
    --backup-dir) backup_dir=$2; shift 2 ;;
    --no-backup) no_backup=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required for safe manifest parsing." >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required." >&2; exit 2; }
[ -f "$script_dir/governance-manifest.json" ] || { echo "Missing governance-manifest.json." >&2; exit 2; }
[ -d "$target" ] || { echo "Target not found: $target" >&2; exit 2; }
target=$(CDPATH='' cd -- "$target" && pwd)

if [ ! -e "$target/AGENTS.md" ] && [ ! -e "$target/lefthook.yml" ] && [ ! -e "$target/.governance-version" ]; then
  echo "$target does not look like a governed repository; use new-governed-repo.sh." >&2
  exit 1
fi

normalize_hash() {
  sed 's/\r$//' "$1" | sha256sum | awk '{print $1}'
}

tmp_dir=$(mktemp -d)
apply_active=false
finish() {
  status=$?
  if [ "$apply_active" = true ] && [ "$status" -ne 0 ]; then rollback; fi
  rm -rf "$tmp_dir"
  exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
plan="$tmp_dir/plan"
version=$(jq -r .governanceVersion "$script_dir/governance-manifest.json")
installed=unknown
[ -f "$target/.governance-version" ] && installed=$(tr -d '\r\n ' < "$target/.governance-version")

echo "Target: $target"
echo "Installed: $installed"
echo "Available: $version"
[ "$dry_run" = true ] && echo "Mode: DRY RUN -- nothing will be written"

jq -c '.files[]' "$script_dir/governance-manifest.json" > "$tmp_dir/entries"
while IFS= read -r entry; do
  template=$(printf '%s' "$entry" | jq -r .template)
  dest=$(printf '%s' "$entry" | jq -r .dest)
  source_path="$script_dir/$template"
  target_path="$target/$dest"
  [ -f "$source_path" ] || { echo "Manifest template missing: $template" >&2; exit 1; }
  shipped=$(normalize_hash "$source_path")
  mode=$(printf '%s' "$entry" | jq -r '.mode // "managed"')
  if [ ! -e "$target_path" ]; then
    action=ADD
  elif [ "$mode" = add-only ]; then
    action=CURRENT
  else
    current=$(normalize_hash "$target_path")
    if [ "$current" = "$shipped" ]; then
      action=CURRENT
    elif printf '%s' "$entry" | jq -e --arg hash "$current" '.knownHashes | index($hash) != null' >/dev/null; then
      action=UPGRADE
    else
      action=CONFLICT
    fi
  fi
  printf '%s\t%s\t%s\n' "$action" "$template" "$dest" >> "$plan"
  printf '  %-9s %s\n' "$action" "$dest"
done < "$tmp_dir/entries"

adds=$(awk -F '\t' '$1=="ADD" {n++} END {print n+0}' "$plan")
upgrades=$(awk -F '\t' '$1=="UPGRADE" {n++} END {print n+0}' "$plan")
conflicts=$(awk -F '\t' '$1=="CONFLICT" {n++} END {print n+0}' "$plan")

if [ "$conflicts" -gt 0 ]; then
  echo "$conflicts customized file(s) were left alone. Reconcile them manually; no force mode exists."
fi
if [ "$dry_run" = true ]; then
  echo "Dry run: nothing was written. $adds add, $upgrades upgrade, $conflicts conflict."
  exit 0
fi
if [ "$adds" -eq 0 ] && [ "$upgrades" -eq 0 ]; then
  if [ "$conflicts" -eq 0 ]; then
    printf '%s\n' "$version" > "$target/.governance-version"
    echo "Already current. Nothing to do."
  else
    echo "Nothing to update automatically."
  fi
  exit 0
fi

if [ -z "$backup_dir" ]; then
  backup_dir="$target/.governance-backup/$(date -u +%Y%m%d-%H%M%S)"
fi
restore_list="$tmp_dir/restore"
added_list="$tmp_dir/added"
: > "$restore_list"
: > "$added_list"

rollback() {
  echo "Update failed; restoring replaced files." >&2
  while IFS='|' read -r path backup; do [ -n "$path" ] && cp "$backup" "$path"; done < "$restore_list"
  while IFS= read -r path; do [ -n "$path" ] && rm -f "$path"; done < "$added_list"
}
apply_active=true

while IFS="$(printf '\t')" read -r action template dest; do
  case "$action" in ADD|UPGRADE) ;; *) continue ;; esac
  source_path="$script_dir/$template"
  target_path="$target/$dest"
  mkdir -p "$(dirname -- "$target_path")"
  if [ "$action" = UPGRADE ] && [ "$no_backup" != true ]; then
    backup_path="$backup_dir/$dest"
    mkdir -p "$(dirname -- "$backup_path")"
    cp "$target_path" "$backup_path"
    printf '%s|%s\n' "$target_path" "$backup_path" >> "$restore_list"
  elif [ "$action" = ADD ]; then
    printf '%s\n' "$target_path" >> "$added_list"
  fi
  cp "$source_path" "$target_path"
  case "$target_path" in *.sh) chmod +x "$target_path" ;; esac
  echo "  $(printf '%s' "$action" | tr '[:upper:]' '[:lower:]'): $dest"
done < "$plan"

if [ "$conflicts" -eq 0 ]; then
  printf '%s\n' "$version" > "$target/.governance-version"
  echo "Updated to governance version $version."
else
  echo "Controls updated, but .governance-version was not advanced while conflicts remain."
fi
[ -s "$restore_list" ] && [ "$no_backup" != true ] && echo "Backups: $backup_dir"
apply_active=false
