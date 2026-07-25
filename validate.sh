#!/usr/bin/env bash
# Structural validation for the zeroclaw-admin-skills repo.
# Exits 0 if every skill is well-formed, 1 otherwise.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
PIN="ZeroClaw v0.8.3"
EXPECTED_SKILLS=(
  zeroclaw-orientation
  zeroclaw-introspect
  zeroclaw-agents
  zeroclaw-mcp
  zeroclaw-skills-tools
)

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

[ -d "$SKILLS_DIR" ] || { err "skills/ directory does not exist"; exit 1; }

for name in "${EXPECTED_SKILLS[@]}"; do
  dir="$SKILLS_DIR/$name"
  skill_md="$dir/SKILL.md"

  if [ ! -d "$dir" ]; then
    err "$name: directory missing"
    continue
  fi
  if [ ! -f "$skill_md" ]; then
    err "$name: SKILL.md missing"
    continue
  fi

  # Frontmatter must be delimited by --- on line 1 and a later ---.
  if [ "$(head -n 1 "$skill_md")" != "---" ]; then
    err "$name: SKILL.md does not start with '---'"
    continue
  fi
  fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$skill_md")"
  if [ -z "$fm_end" ]; then
    err "$name: SKILL.md frontmatter is not terminated"
    continue
  fi
  fm="$(sed -n "2,$((fm_end - 1))p" "$skill_md")"

  fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1)"
  fm_desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n 1)"

  [ -n "$fm_name" ] || err "$name: frontmatter missing 'name'"
  [ -n "$fm_desc" ] || err "$name: frontmatter missing 'description'"
  [ "$fm_name" = "$name" ] || err "$name: frontmatter name '$fm_name' != directory name"

  # Description must be substantial enough to drive triggering.
  if [ -n "$fm_desc" ] && [ "${#fm_desc}" -lt 40 ]; then
    err "$name: description is too short (${#fm_desc} chars, need >= 40)"
  fi

  # Version pin must appear in the body.
  if ! grep -qF "$PIN" "$skill_md"; then
    err "$name: body does not state the '$PIN' version pin"
  fi

  # Evals must exist and be valid JSON.
  evals="$dir/evals/evals.json"
  if [ ! -f "$evals" ]; then
    err "$name: evals/evals.json missing"
  elif ! jq empty "$evals" 2>/dev/null; then
    err "$name: evals/evals.json is not valid JSON"
  fi
done

# The forbidden-flag check: --skill does not exist on `skills install` at v0.8.3.
if grep -rn -- "skills install.*--skill " "$SKILLS_DIR" 2>/dev/null; then
  err "found 'skills install --skill', which does not exist at $PIN"
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: all %d skills valid\n' "${#EXPECTED_SKILLS[@]}"
fi
exit "$fail"
