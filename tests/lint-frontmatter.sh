#!/usr/bin/env bash
# lint-frontmatter.sh — validate YAML frontmatter in SKILL.md and agent files.
#
# Rules:
#   skills/<name>/SKILL.md must have:    name, description
#   agents/<name>.md       must have:    name, description, tools, model
#   commands/<name>.md     must have:    description
#
# Exit 0 if all OK, 1 if any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { echo "lint-frontmatter: cannot cd to $REPO_ROOT" >&2; exit 1; }

c_g=$'\033[32m'; c_r=$'\033[31m'; c_0=$'\033[0m'

failures=0

extract_frontmatter() {
  local file="$1"
  awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$file"
}

has_field() {
  local fm="$1" field="$2"
  # Accept either `field: value` (inline) or `field:` followed by indented value
  # (multi-line YAML scalar). Use heredoc to avoid SIGPIPE on early grep match.
  grep -qE "^${field}:([[:space:]]+\S|[[:space:]]*$)" <<< "$fm"
}

check_skill() {
  local f="$1"
  local fm; fm="$(extract_frontmatter "$f")"
  if [[ -z "$fm" ]]; then
    printf "${c_r}✗${c_0} %s — missing frontmatter\n" "$f"
    ((failures++))
    return
  fi
  for field in name description; do
    if ! has_field "$fm" "$field"; then
      printf "${c_r}✗${c_0} %s — missing '%s' in frontmatter\n" "$f" "$field"
      ((failures++))
      return
    fi
  done
  # Check description length (Claude Code recommends concise; warn if too short).
  # Handles both `description: value` (inline) and multi-line YAML scalars:
  #   description:
  #     line one
  #     line two
  # Extracts from first description line through last continuation (indented) line.
  local desc_text
  desc_text="$(awk '
    /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      print
      in_desc = 1
      next
    }
    in_desc && /^[[:space:]]+/ { sub(/^[[:space:]]+/, ""); print; next }
    in_desc { in_desc = 0 }
  ' <<< "$fm")"
  local desc_len="${#desc_text}"
  if [[ "$desc_len" -lt 50 ]]; then
    printf "${c_r}✗${c_0} %s — description suspiciously short (%s chars)\n" "$f" "$desc_len"
    ((failures++))
    return
  fi
  printf "${c_g}✓${c_0} %s\n" "$f"
}

check_agent() {
  local f="$1"
  local fm; fm="$(extract_frontmatter "$f")"
  if [[ -z "$fm" ]]; then
    printf "${c_r}✗${c_0} %s — missing frontmatter\n" "$f"
    ((failures++))
    return
  fi
  for field in name description tools model; do
    if ! has_field "$fm" "$field"; then
      printf "${c_r}✗${c_0} %s — missing '%s'\n" "$f" "$field"
      ((failures++))
      return
    fi
  done
  printf "${c_g}✓${c_0} %s\n" "$f"
}

check_command() {
  local f="$1"
  local fm; fm="$(extract_frontmatter "$f")"
  if [[ -z "$fm" ]]; then
    printf "${c_r}✗${c_0} %s — missing frontmatter\n" "$f"
    ((failures++))
    return
  fi
  if ! has_field "$fm" "description"; then
    printf "${c_r}✗${c_0} %s — missing 'description'\n" "$f"
    ((failures++))
    return
  fi
  printf "${c_g}✓${c_0} %s\n" "$f"
}

echo "Linting skills/*/SKILL.md..."
for f in skills/*/SKILL.md; do
  [[ -f "$f" ]] || continue
  check_skill "$f"
done

echo
echo "Linting agents/*.md..."
for f in agents/*.md; do
  [[ -f "$f" ]] || continue
  check_agent "$f"
done

echo
echo "Linting commands/*.md..."
for f in commands/*.md; do
  [[ -f "$f" ]] || continue
  check_command "$f"
done

echo
if [[ $failures -gt 0 ]]; then
  printf "${c_r}%s frontmatter failure(s).${c_0}\n" "$failures"
  exit 1
fi
echo "${c_g}All frontmatter clean.${c_0}"
