#!/bin/sh
# Update only the managed bootstrap block in user-level agent instructions.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
agent=all
dry_run=false
no_backup=false

usage() { echo "usage: $0 [--agent claude|codex|gemini|opencode|all] [--dry-run] [--no-backup]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent) agent=$2; shift 2 ;;
    --dry-run|--plan) dry_run=true; shift ;;
    --no-backup) no_backup=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$agent" in claude|codex|gemini|opencode|all) ;; *) usage >&2; exit 2 ;; esac

begin='<!-- BEGIN repo-governance (managed) -->'
end='<!-- END repo-governance (managed) -->'
source_file="$script_dir/global/new-project-bootstrap.md"
[ -f "$source_file" ] || { echo "Missing $source_file" >&2; exit 2; }

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
managed="$tmp_dir/managed"
{
  printf '%s\n\n' "$begin"
  sed 's/\r$//' "$source_file"
  printf '\n%s\n' "$end"
} > "$managed"

update_one() {
  name=$1
  path=$2
  current="$tmp_dir/current-$name"
  updated="$tmp_dir/updated-$name"
  [ -f "$path" ] && sed 's/\r$//' "$path" > "$current" || : > "$current"

  begin_line=$(grep -n -F "$begin" "$current" | sed -n '1s/:.*//p')
  end_line=$(grep -n -F "$end" "$current" | sed -n '1s/:.*//p')
  if [ -n "$begin_line" ] || [ -n "$end_line" ]; then
    [ -n "$begin_line" ] && [ -n "$end_line" ] && [ "$begin_line" -lt "$end_line" ] || {
      echo "  $name: malformed managed markers in $path; skipping." >&2
      return 1
    }
    head_count=$((begin_line - 1))
    {
      [ "$head_count" -eq 0 ] || sed -n "1,${head_count}p" "$current"
      cat "$managed"
      sed -n "$((end_line + 1)),\$p" "$current"
    } > "$updated"
  else
    cp "$current" "$updated"
    [ ! -s "$updated" ] || printf '\n' >> "$updated"
    cat "$managed" >> "$updated"
  fi

  if cmp -s "$current" "$updated"; then
    echo "  $name: already current"
    return 0
  fi
  echo "  $name: update $path"
  [ "$dry_run" = true ] && return 0
  mkdir -p "$(dirname -- "$path")"
  if [ -f "$path" ] && [ "$no_backup" != true ]; then
    cp "$path" "$path.bak-$(date -u +%Y%m%d-%H%M%S)"
  fi
  cp "$updated" "$path"
}

run_target() {
  case "$1" in
    claude) update_one claude "$HOME/.claude/CLAUDE.md" ;;
    codex) update_one codex "$HOME/.codex/AGENTS.md" ;;
    gemini) update_one gemini "$HOME/.gemini/GEMINI.md" ;;
    opencode) update_one opencode "$HOME/.config/opencode/AGENTS.md" ;;
  esac
}

if [ "$agent" = all ]; then
  for item in claude codex gemini opencode; do run_target "$item"; done
else
  run_target "$agent"
fi

[ "$dry_run" = true ] && echo "Dry run: nothing was written."
echo "Cursor user rules remain a manual UI update; see global/cursor-user-rules.txt."
