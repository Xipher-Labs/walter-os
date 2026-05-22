#!/usr/bin/env bats
# tests/oss/lite-format.bats
#
# Verifies the Walter-OS Lite entry-tier files conform to spec.
# Spec: docs/specs/walter-os-lite-entry-tier.md (AC-7)
#
# Critical contract:
# - lite.md fenced block must be self-contained (no shell, no fetches)
# - lite.md fenced block fits in a single context paste
# - lite.md + lite-persist.md both exist + are structured

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LITE="$REPO_ROOT/setup/agent-install/lite.md"
  LITE_PERSIST="$REPO_ROOT/setup/agent-install/lite-persist.md"
}

# Extract the contents of the first fenced block (between ``` lines) into
# stdout. Strips the fence lines themselves.
_extract_block() {
  local file="$1"
  awk '/^```$/{flag=!flag; next} flag' "$file"
}

# ---------------------------------------------------------------------------
# lite.md presence + structure
# ---------------------------------------------------------------------------

@test "AC-1: setup/agent-install/lite.md exists" {
  [[ -f "$LITE" ]]
}

@test "AC-7: lite.md contains exactly one fenced block" {
  local count
  count="$(grep -c '^```$' "$LITE")"
  # An opening + closing fence = 2 markers for 1 block.
  [[ "$count" -eq 2 ]]
}

@test "AC-7: lite.md fenced block is under 600 lines" {
  local block_lines
  block_lines="$(_extract_block "$LITE" | wc -l | tr -d ' ')"
  [[ "$block_lines" -lt 600 ]]
}

@test "AC-2: lite.md fenced block is roughly under 500 tokens (~ 2000 chars)" {
  # Rough token estimate: 4 chars per token. Spec target: <= 500 tokens.
  # Allow 600-token headroom (2400 chars) to avoid bikeshedding on minor
  # wording changes — the intent is "fits in one paste", not "exactly 500".
  local block_chars
  block_chars="$(_extract_block "$LITE" | wc -c | tr -d ' ')"
  [[ "$block_chars" -lt 2400 ]] || {
    echo "block char count: $block_chars (target: <2400, ~600 tokens)" >&2
    return 1
  }
}

@test "AC-7: lite.md fenced block contains no tool-requiring shell commands" {
  local block
  block="$(_extract_block "$LITE")"
  # The Lite contract is install-free. The fenced block must not require
  # the operator (or the agent) to invoke any external tool.
  if echo "$block" | grep -qE '^[[:space:]]*(brew install|apt-get|apt install|pip install|pip3 install|npm install|pnpm install|yarn install|cargo install|curl|wget|git clone)'; then
    echo "lite.md block contains an external-tool invocation" >&2
    echo "$block" | grep -nE '^[[:space:]]*(brew install|apt-get|apt install|pip install|pip3 install|npm install|pnpm install|yarn install|cargo install|curl|wget|git clone)' >&2
    return 1
  fi
}

@test "AC-1: lite.md installs all 6 discipline categories" {
  local block
  block="$(_extract_block "$LITE")"
  echo "$block" | grep -qi "rigor"
  echo "$block" | grep -qi "TDD"
  echo "$block" | grep -qi "conventional commit"
  echo "$block" | grep -qi "branch flow"
  echo "$block" | grep -qi "self-review"
  echo "$block" | grep -qi "Hard nevers"
}

@test "AC-3: lite.md references the Tier I upgrade path" {
  grep -q "tier-1.md" "$LITE"
}

# ---------------------------------------------------------------------------
# lite-persist.md presence + structure
# ---------------------------------------------------------------------------

@test "AC-4: setup/agent-install/lite-persist.md exists" {
  [[ -f "$LITE_PERSIST" ]]
}

@test "AC-4: lite-persist.md fenced block writes to .walter-os-lite/AGENTS.md" {
  grep -q "\.walter-os-lite/AGENTS.md" "$LITE_PERSIST"
}

@test "AC-4: lite-persist.md adds .walter-os-lite/ to .gitignore" {
  # The persist flow must propose the gitignore update — Lite-persist is
  # not for team-wide enforcement, the directory should not be committed
  # by accident.
  grep -q "gitignore" "$LITE_PERSIST"
  grep -q "\.walter-os-lite/" "$LITE_PERSIST"
}

@test "AC-4: lite-persist.md contains exactly one fenced block" {
  local count
  count="$(grep -c '^```$' "$LITE_PERSIST")"
  [[ "$count" -eq 2 ]]
}

@test "AC-4: lite-persist.md template covers all 6 discipline categories" {
  # Reviewer R2 caught that lite-persist.md's persisted-contract template
  # is structurally distinct from lite.md and needs its own coverage test.
  # All 6 disciplines must appear (same as lite.md) so the persisted file
  # is not a stripped-down version.
  grep -qi "rigor" "$LITE_PERSIST"
  grep -qi "TDD" "$LITE_PERSIST"
  grep -qi "conventional commit" "$LITE_PERSIST"
  grep -qi "branch flow" "$LITE_PERSIST"
  grep -qi "self-review" "$LITE_PERSIST"
  grep -qi "Hard nevers" "$LITE_PERSIST"
}

@test "AC-4: lite-persist.md uses unambiguous BEGIN/END markers (no bare ---)" {
  # Reviewer R2 caught that the prior version used bare `---` lines as
  # content markers inside the fenced block — an agent parsing this
  # literally could mistake them for YAML frontmatter delimiters and
  # truncate the file. Verify the unambiguous markers are present.
  grep -q "BEGIN .walter-os-lite/AGENTS.md" "$LITE_PERSIST"
  grep -q "END .walter-os-lite/AGENTS.md" "$LITE_PERSIST"
}
