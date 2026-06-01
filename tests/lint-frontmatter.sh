#!/usr/bin/env bash
# lint-frontmatter.sh - validate YAML frontmatter in SKILL.md and agent files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v ruby >/dev/null 2>&1; then
  echo "lint-frontmatter: ruby is required to parse YAML frontmatter" >&2
  exit 1
fi

exec ruby "$REPO_ROOT/tests/lint-frontmatter.rb"
