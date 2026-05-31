#!/usr/bin/env bash
# pre-commit-tests.sh
# Runs project lint/typecheck/tests before allowing a `git commit`.
#
# Branch-aware scaling:
# - On feature/*, fix/*, chore/*: lint + typecheck only (fast, every commit).
# - On dev, staging, main: full suite including tests (slow, but rare).
# - Override with WALTER_PRECOMMIT_FULL=1 to force full on any branch.
#
# Hooked into Claude Code's PreToolUse for Bash matching `git commit`.

set -uo pipefail

WALTER_HOOK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALTER_OS_HOME="$WALTER_HOOK_REPO_ROOT"
if [[ -f "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" ]]; then
  # shellcheck source=/dev/null
  source "${WALTER_OS_HOME}/scripts/walter/lib/audit-chain.sh" || true
fi

audit_precommit_decision() {
  local decision="$1" reason="${2:-}" input_summary="${3:-${CMD:-}}"
  if declare -F walter_audit_append >/dev/null 2>&1; then
    walter_audit_append Bash "$input_summary" "$decision" "pre-commit-tests" "$reason" >/dev/null 2>&1 || {
      printf '%s\n' '{"decision":"block","reason":"pre-commit-tests: audit-chain append failed; refusing unaudited decision"}'
      exit 0
    }
  else
    printf '%s\n' '{"decision":"block","reason":"pre-commit-tests: audit-chain writer unavailable; refusing unaudited decision"}'
    exit 0
  fi
}

INPUT="$(cat)"

if command -v jq >/dev/null 2>&1; then
  CMD="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
fi

# Only act on `git commit` (not commit-tree, commit-graph, etc.)
if ! echo "$CMD" | grep -qE '^[[:space:]]*git[[:space:]]+commit([[:space:]]|$)'; then
  audit_precommit_decision allow "not a git commit"
  echo '{"decision":"allow"}'
  exit 0
fi

# Skip if --no-verify is in the command (operator's explicit override)
if echo "$CMD" | grep -q -- '--no-verify'; then
  audit_precommit_decision allow "git commit --no-verify"
  echo '{"decision":"allow"}'
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[[ -z "$REPO_ROOT" ]] && { audit_precommit_decision allow "outside git repository"; echo '{"decision":"allow"}'; exit 0; }

cd "$REPO_ROOT" || { audit_precommit_decision allow "cannot enter repository"; echo '{"decision":"allow"}'; exit 0; }

block() {
  local reason="$1"
  audit_precommit_decision block "$reason"
  echo "{\"decision\":\"block\",\"reason\":\"${reason//\"/\\\"}\"}"
  exit 0
}

# ---------- branch-aware scaling ----------

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# Default: feature/* → fast (lint + typecheck only)
# dev|staging|main → full (lint + typecheck + tests)
RUN_TESTS=0
case "$BRANCH" in
  dev|staging|main|master|production) RUN_TESTS=1 ;;
esac

# Override
if [[ "${WALTER_PRECOMMIT_FULL:-0}" == "1" ]]; then
  RUN_TESTS=1
fi

FAILED=()

# JS/TS
if [[ -f "package.json" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    PM="pnpm"
  elif command -v npm >/dev/null 2>&1; then
    PM="npm"
  else
    PM=""
  fi

  if [[ -n "$PM" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
      $PM run lint >/dev/null 2>&1 || FAILED+=("lint")
    fi
    if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
      $PM run typecheck >/dev/null 2>&1 || FAILED+=("typecheck")
    fi
    if [[ "$RUN_TESTS" == "1" ]] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      $PM run test -- --run >/dev/null 2>&1 || FAILED+=("test")
    fi
  fi
fi

# Rust
if [[ -f "Cargo.toml" ]]; then
  cargo fmt --check >/dev/null 2>&1 || FAILED+=("cargo fmt")
  cargo clippy --all-targets -- -D warnings >/dev/null 2>&1 || FAILED+=("cargo clippy")
  if [[ "$RUN_TESTS" == "1" ]]; then
    cargo test --quiet >/dev/null 2>&1 || FAILED+=("cargo test")
  fi
fi

# Python
if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
  if command -v ruff >/dev/null 2>&1; then
    ruff check . >/dev/null 2>&1 || FAILED+=("ruff")
  fi
  if command -v mypy >/dev/null 2>&1 && [[ -f "mypy.ini" || -f "pyproject.toml" ]]; then
    mypy . >/dev/null 2>&1 || FAILED+=("mypy")
  fi
  if [[ "$RUN_TESTS" == "1" ]] && { [[ -d "tests" ]] || [[ -d "test" ]]; }; then
    if command -v pytest >/dev/null 2>&1; then
      pytest -q >/dev/null 2>&1 || FAILED+=("pytest")
    fi
  fi
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  if [[ "$RUN_TESTS" == "1" ]]; then
    block "Pre-commit (full, branch=${BRANCH}) failed: ${FAILED[*]}. Fix or use --no-verify."
  else
    block "Pre-commit (fast, branch=${BRANCH}) failed: ${FAILED[*]}. Fix or use --no-verify. Tests skipped on this branch (set WALTER_PRECOMMIT_FULL=1 to include)."
  fi
fi

audit_precommit_decision allow "pre-commit checks passed"
echo '{"decision":"allow"}'
