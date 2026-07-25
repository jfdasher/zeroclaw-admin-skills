#!/usr/bin/env bash
# Symlink every skill in this repo into ~/.claude/skills/.
# Usage: ./install.sh [--force] [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/skills"
DEST_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

force=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --force)   force=1 ;;
    --dry-run) dry_run=1 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

[ -d "$SRC_DIR" ] || { printf 'no skills/ directory at %s\n' "$SRC_DIR" >&2; exit 1; }
mkdir -p "$DEST_DIR"

status=0
for src in "$SRC_DIR"/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  src="${src%/}"
  dest="$DEST_DIR/$name"

  if [ -L "$dest" ]; then
    current="$(readlink "$dest")"
    if [ "$current" = "$src" ]; then
      printf 'ok       %s (already linked)\n' "$name"
      continue
    fi
    if [ "$force" -eq 1 ]; then
      [ "$dry_run" -eq 1 ] || { rm "$dest"; ln -s "$src" "$dest"; }
      printf 'relinked %s -> %s\n' "$name" "$src"
      continue
    fi
    printf 'SKIP     %s: stale symlink to %s (use --force)\n' "$name" "$current" >&2
    status=1
    continue
  fi

  if [ -e "$dest" ]; then
    printf 'SKIP     %s: exists and is not a symlink; refusing to replace\n' "$name" >&2
    status=1
    continue
  fi

  [ "$dry_run" -eq 1 ] || ln -s "$src" "$dest"
  printf 'linked   %s -> %s\n' "$name" "$src"
done

exit "$status"
