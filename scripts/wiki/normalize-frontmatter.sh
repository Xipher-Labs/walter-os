#!/usr/bin/env bash
# scripts/wiki/normalize-frontmatter.sh — normalize YAML frontmatter in wiki pages.
#
# Usage:
#   normalize-frontmatter.sh [<wiki-dir>]
#
# Environment:
#   WIKI_DIR                  Path to scan (default: ~/sync/wiki)
#   WIKI_NORMALIZE_REPORT     Report output path
#
# What it does (per file):
#   1. Parses YAML frontmatter block
#   2. If malformed YAML → adds to report as "needs manual fix"; skips
#   3. If missing required fields:
#      - type: infers from path (people/ → person, companies/ → company, etc.)
#        If inferable → auto-fixes in-place; otherwise adds to report
#      - created: infers from git log; falls back to today
#      - title: if no H1 heading found → adds to report (no auto-fix possible)
#   4. Writes fixed files in-place
#   5. Idempotent: running twice produces no changes after first pass
#
# Exit code: always 0 (findings go to report)
#
# Refs: docs/specs/walter-council-v2.md — T-M-0

set -uo pipefail

WIKI_DIR="${1:-${WIKI_DIR:-$HOME/sync/wiki}}"
REPORT_FILE="${WIKI_NORMALIZE_REPORT:-$HOME/.config/walter-os/wiki-normalize-report.txt}"

REPORT_LINES=()

# Infer page type from directory path relative to wiki root
_infer_type_from_path() {
  local filepath="$1"
  local rel_path="${filepath#"$WIKI_DIR"/}"
  case "$rel_path" in
    people/*)      echo "person"   ;;
    companies/*)   echo "company"  ;;
    concepts/*)    echo "concept"  ;;
    decisions/*)   echo "decision" ;;
    tools/*)       echo "tool"     ;;
    topics/*)      echo "topic"    ;;
    sources/*)     echo "source"   ;;
    projects/*)    echo "project"  ;;
    *)             echo ""         ;;
  esac
}

# Extract created date from git history (first commit date for file)
_git_created_date() {
  local filepath="$1"
  git -C "$(dirname "$filepath")" log --follow --format="%as" -- "$filepath" 2>/dev/null | tail -1
}

# Check if frontmatter block is valid YAML.
# Uses python3 + pyyaml if available (via uvx), otherwise falls back to
# a heuristic bash check: look for obviously unbalanced/invalid syntax.
_validate_yaml() {
  local yaml_block="$1"
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$yaml_block" > "$tmp"

  # Try uvx pyyaml first (preferred, precise)
  if command -v uvx >/dev/null 2>&1; then
    if uvx --from pyyaml python3 - "$tmp" 2>/dev/null <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    try:
        yaml.safe_load(f.read())
        sys.exit(0)
    except Exception:
        sys.exit(1)
PYEOF
    then
      rm -f "$tmp"
      return 0
    else
      rm -f "$tmp"
      return 1
    fi
  fi

  # Fallback: heuristic bash check — detect unbalanced [ that don't close on same line
  # and colon-after-bracket sequences that are invalid in YAML scalar context
  local rc=0
  if grep -qE '^\s*[a-z_]+\s*:\s*\[.*[^]]*$' "$tmp" 2>/dev/null; then
    # An opening [ without matching ] on the same line (multi-line sequence start
    # is valid YAML, but broken arrays like [this is not valid: ... are not)
    if grep -qE '^\s*[a-z_]+\s*:\s*\[[^]]*:[^]]*$' "$tmp" 2>/dev/null; then
      rc=1
    fi
  fi
  rm -f "$tmp"
  return $rc
}

# Extract frontmatter block from a file (content between first --- and second ---)
_extract_frontmatter() {
  local filepath="$1"
  awk '/^---$/{if(++c==1){p=1;next}else{p=0;exit}} p{print}' "$filepath"
}

# Check if file has frontmatter (starts with ---)
_has_frontmatter() {
  local filepath="$1"
  head -1 "$filepath" | grep -q '^---$'
}

# Check if a YAML field exists in the frontmatter text
_yaml_has_field() {
  local yaml_text="$1"
  local field="$2"
  printf '%s\n' "$yaml_text" | grep -qE "^${field}[[:space:]]*:"
}

# Check if page has an H1 heading (after the frontmatter)
_has_h1() {
  local filepath="$1"
  awk '/^---$/{if(++c==2){p=1;next}} p && /^#[[:space:]]/{found=1;exit} END{exit !found}' "$filepath"
}

# Add a field to frontmatter in-place (insert after opening ---)
_add_frontmatter_field() {
  local filepath="$1"
  local field="$2"
  local value="$3"
  local tmpfile
  tmpfile="$(mktemp)"
  awk -v field="$field" -v value="$value" '
    /^---$/ && NR==1 { print; printf "%s: %s\n", field, value; next }
    { print }
  ' "$filepath" > "$tmpfile"
  mv "$tmpfile" "$filepath"
}

process_file() {
  local filepath="$1"

  # --- Check frontmatter existence ---
  if ! _has_frontmatter "$filepath"; then
    # No frontmatter at all — try to add minimal frontmatter
    local inferred_type
    inferred_type="$(_infer_type_from_path "$filepath")"
    local inferred_date
    inferred_date="$(_git_created_date "$filepath")"
    inferred_date="${inferred_date:-$(date +%Y-%m-%d)}"

    if [[ -n "$inferred_type" ]]; then
      local tmpfile
      tmpfile="$(mktemp)"
      {
        printf -- '---\n'
        printf 'type: %s\n' "$inferred_type"
        printf 'created: %s\n' "$inferred_date"
        printf -- '---\n'
        cat "$filepath"
      } > "$tmpfile"
      mv "$tmpfile" "$filepath"
    else
      REPORT_LINES+=("NO_FRONTMATTER: $filepath")
    fi
  fi

  # Re-read after possible changes
  if ! _has_frontmatter "$filepath"; then
    return 0
  fi

  local fm
  fm="$(_extract_frontmatter "$filepath")"

  # --- Validate YAML ---
  if ! _validate_yaml "$fm"; then
    REPORT_LINES+=("MALFORMED_YAML: $filepath")
    return 0
  fi

  # --- Check required field: type ---
  if ! _yaml_has_field "$fm" "type"; then
    local inferred_type
    inferred_type="$(_infer_type_from_path "$filepath")"
    if [[ -n "$inferred_type" ]]; then
      _add_frontmatter_field "$filepath" "type" "$inferred_type"
      fm="$(_extract_frontmatter "$filepath")"
    else
      REPORT_LINES+=("MISSING_TYPE: $filepath")
    fi
  fi

  # --- Check required field: created ---
  if ! _yaml_has_field "$fm" "created"; then
    local inferred_date
    inferred_date="$(_git_created_date "$filepath")"
    inferred_date="${inferred_date:-$(date +%Y-%m-%d)}"
    _add_frontmatter_field "$filepath" "created" "$inferred_date"
    fm="$(_extract_frontmatter "$filepath")"
  fi

  # --- Check required field: tags ---
  # wiki-validator.sh requires tags. Normalize adds tags: [] as a safe default
  # so the validator won't block subsequent writes.
  if ! _yaml_has_field "$fm" "tags"; then
    _add_frontmatter_field "$filepath" "tags" "[]"
    fm="$(_extract_frontmatter "$filepath")"
  fi

  # --- Check for H1 title ---
  if ! _has_h1 "$filepath"; then
    REPORT_LINES+=("MISSING_TITLE: $filepath")
  fi

  return 0
}

main() {
  if [[ ! -d "$WIKI_DIR" ]]; then
    echo "normalize-frontmatter: wiki dir not found: $WIKI_DIR" >&2
    echo "  Set WIKI_DIR or pass path as argument." >&2
    exit 0
  fi

  REPORT_LINES=()

  # Process all markdown files recursively
  while IFS= read -r -d '' filepath; do
    process_file "$filepath"
  done < <(find "$WIKI_DIR" -name '*.md' -print0 | sort -z)

  # Write report
  mkdir -p "$(dirname "$REPORT_FILE")"
  if [[ "${#REPORT_LINES[@]}" -gt 0 ]]; then
    {
      printf '# Wiki Frontmatter Normalization Report — %s\n' "$(date +%Y-%m-%d)"
      printf '# Generated by scripts/wiki/normalize-frontmatter.sh\n'
      printf '# Files requiring manual review:\n'
      printf '\n'
      for line in "${REPORT_LINES[@]}"; do
        printf '  %s\n' "$line"
      done
    } > "$REPORT_FILE"
  else
    {
      printf '# Wiki Frontmatter Normalization Report — %s\n' "$(date +%Y-%m-%d)"
      printf '# All pages have valid frontmatter. No manual review needed.\n'
    } > "$REPORT_FILE"
  fi

  exit 0
}

main
