#!/usr/bin/env bash
# scripts/wiki/wiki-validator.sh — validate wiki page frontmatter before write.
#
# Usage:
#   wiki-validator.sh <filepath>
#
# Validates that <filepath> has valid YAML frontmatter per wiki/SCHEMA.md:
#   - Has a frontmatter block (---)
#   - YAML is parseable (uses uvx+pyyaml if available, heuristic otherwise)
#   - Required fields present: type, title, created, tags
#
# Exit codes:
#   0   Valid frontmatter — write allowed
#   1   Invalid frontmatter — write blocked (error message on stderr)
#   2   Usage error
#
# Agents call this before writing any file to ~/sync/wiki/**
# No silent fixes — agent must repair frontmatter explicitly.
#
# Refs: docs/specs/walter-council-v2.md — T-M-1

set -uo pipefail

REQUIRED_FIELDS=(type title created tags)

usage() {
  echo "Usage: wiki-validator.sh <filepath>" >&2
  echo "  Validates wiki page frontmatter. Exits 0 if valid, 1 if invalid." >&2
  exit 2
}

# Check if file starts with frontmatter block
_has_frontmatter() {
  local filepath="$1"
  head -1 "$filepath" | grep -q '^---$'
}

# Extract frontmatter block (between first and second ---)
_extract_frontmatter() {
  local filepath="$1"
  awk '/^---$/{if(++c==1){p=1;next}else{p=0;exit}} p{print}' "$filepath"
}

# Validate YAML using uvx+pyyaml or heuristic
_validate_yaml() {
  local yaml_block="$1"
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$yaml_block" > "$tmp"

  local rc=0
  if command -v uvx >/dev/null 2>&1; then
    if ! uvx --from pyyaml python3 - "$tmp" 2>/dev/null <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    try:
        yaml.safe_load(f.read())
        sys.exit(0)
    except Exception:
        sys.exit(1)
PYEOF
    then
      rc=1
    fi
  else
    # Heuristic: unbalanced bracket with embedded colon = likely malformed
    if grep -qE '^\s*[a-z_]+\s*:\s*\[[^]]*:[^]]*$' "$tmp" 2>/dev/null; then
      rc=1
    fi
  fi

  rm -f "$tmp"
  return $rc
}

# Check if a YAML field exists
_yaml_has_field() {
  local yaml_text="$1"
  local field="$2"
  printf '%s\n' "$yaml_text" | grep -qE "^${field}[[:space:]]*:"
}

# Main validation — returns 0 if valid, 1 if not (with errors to stderr)
validate_file() {
  local filepath="$1"

  if [[ ! -f "$filepath" ]]; then
    echo "wiki-validator: file not found: $filepath" >&2
    return 1
  fi

  if ! _has_frontmatter "$filepath"; then
    echo "wiki-validator: '$filepath' has no YAML frontmatter block." >&2
    echo "  Add a frontmatter block starting with --- at line 1." >&2
    echo "  Required fields: ${REQUIRED_FIELDS[*]}" >&2
    return 1
  fi

  local fm
  fm="$(_extract_frontmatter "$filepath")"

  if ! _validate_yaml "$fm"; then
    echo "wiki-validator: '$filepath' has malformed YAML frontmatter." >&2
    echo "  Fix the YAML syntax and retry." >&2
    return 1
  fi

  local missing=()
  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! _yaml_has_field "$fm" "$field"; then
      missing+=("$field")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "wiki-validator: '$filepath' is missing required frontmatter fields: ${missing[*]}" >&2
    echo "  Add the missing fields before writing." >&2
    echo "  Required fields: ${REQUIRED_FIELDS[*]}" >&2
    echo "  Tip: run scripts/wiki/normalize-frontmatter.sh to auto-fix infer-able fields." >&2
    return 1
  fi

  return 0
}

if [[ $# -eq 0 ]]; then
  usage
fi

validate_file "$1"
