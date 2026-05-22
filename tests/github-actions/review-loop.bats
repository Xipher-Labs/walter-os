#!/usr/bin/env bats
# tests/github-actions/review-loop.bats
#
# Static-validation suite for the walter-review-loop composite action.
# We don't execute the action's shell steps end-to-end here — that
# requires GitHub-hosted runner context + real auth — but we validate
# the action's structure + invariants that make it usable.
#
# Spec: docs/specs/review-loop-as-action.md (AC-6)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ACTION_YML="$REPO_ROOT/.github/actions/walter-review-loop/action.yml"
  ACTION_README="$REPO_ROOT/.github/actions/walter-review-loop/README.md"
  WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
}

# ---------------------------------------------------------------------------
# Action file structure
# ---------------------------------------------------------------------------

@test "action.yml exists at the documented path" {
  [[ -f "$ACTION_YML" ]]
}

@test "action.yml is a composite action (not a Docker / JavaScript action)" {
  grep -qE "^[[:space:]]*using:[[:space:]]+composite[[:space:]]*$" "$ACTION_YML"
}

@test "action.yml has the SPDX-License-Identifier: Apache-2.0 header" {
  head -3 "$ACTION_YML" | grep -q "SPDX-License-Identifier: Apache-2.0"
}

# ---------------------------------------------------------------------------
# Required inputs (per spec AC-1)
# ---------------------------------------------------------------------------

@test "AC-1: action declares required input pr-number" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+pr-number:"
}

@test "AC-1: action declares required input base-branch" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+base-branch:"
}

@test "AC-1: action declares optional input severity-gate-config" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+severity-gate-config:"
}

@test "AC-1: action declares optional input run-codex" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+run-codex:"
}

@test "AC-1: action declares optional input run-copilot" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+run-copilot:"
}

# ---------------------------------------------------------------------------
# Required outputs (per spec AC-2)
# ---------------------------------------------------------------------------

@test "AC-2: action declares output findings-json" {
  awk '/^outputs:/,/^runs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+findings-json:"
}

@test "AC-2: action declares output rounds-completed" {
  awk '/^outputs:/,/^runs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+rounds-completed:"
}

@test "AC-2: action declares output status" {
  awk '/^outputs:/,/^runs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+status:"
}

# ---------------------------------------------------------------------------
# Round 1 (Copilot) — request via REST per AGENTS.md (AC-3)
# ---------------------------------------------------------------------------

@test "AC-3: Copilot step uses REST endpoint /requested_reviewers (not graphql)" {
  grep -q "pulls/.*requested_reviewers" "$ACTION_YML"
  # Verify it's NOT using the broken GraphQL path.
  ! grep -q "gh pr edit --add-reviewer" "$ACTION_YML"
}

@test "AC-3: Copilot step posts copilot-pull-request-reviewer[bot]" {
  grep -q "copilot-pull-request-reviewer" "$ACTION_YML"
}

@test "AC-3: Copilot step handles HTTP non-2xx as a warning, not a failure" {
  # The step must NOT use `set -e` such that an HTTP failure aborts.
  # Verify the curl is wrapped in `|| true` and exit code is captured.
  grep -qE "curl.*\|\| true|http_code=\\\$\\(curl" "$ACTION_YML"
}

# ---------------------------------------------------------------------------
# Round 2 (Codex) — graceful degradation (AC-4)
# ---------------------------------------------------------------------------

@test "AC-4: Codex step skips cleanly when codex CLI is missing" {
  # The step must check command -v codex and skip if absent.
  grep -qE "command -v codex" "$ACTION_YML"
  # Skip should log a warning, not fail the workflow.
  grep -qE "::warning::.*[Cc]odex" "$ACTION_YML"
}

@test "AC-4: Codex step uses the minimal-bypass CODEX_HOME pattern" {
  # Per AGENTS.md "How to invoke Codex review", the minimal bypass writes
  # approval_policy = "never" + inherits auth.json. Verify both.
  grep -q 'approval_policy = "never"' "$ACTION_YML"
  grep -q "auth.json" "$ACTION_YML"
}

@test "AC-4: Codex step skips when no auth.json is mounted" {
  # The step must NOT fail when auth.json is absent — that's the
  # natural state for forks that haven't set up CODEX_AUTH_JSON.
  grep -qE "\\! -f.*auth\\.json|auth.json.*missing" "$ACTION_YML"
}

# ---------------------------------------------------------------------------
# Workflow wiring (AC-5)
# ---------------------------------------------------------------------------

@test "AC-5: pr-review.yml workflow exists" {
  [[ -f "$WORKFLOW" ]]
}

@test "AC-5: workflow runs on pull_request to main" {
  grep -qE "pull_request:" "$WORKFLOW"
  grep -qE "branches:[[:space:]]*\\[main\\]" "$WORKFLOW"
}

@test "AC-5: workflow uses ./.github/actions/walter-review-loop" {
  grep -qE "uses:[[:space:]]+\\./\\.github/actions/walter-review-loop" "$WORKFLOW"
}

@test "AC-5: workflow has the minimum permissions (read+pr write)" {
  awk '/^permissions:/,/^jobs:/' "$WORKFLOW" | grep -q "contents: read"
  awk '/^permissions:/,/^jobs:/' "$WORKFLOW" | grep -q "pull-requests: write"
}

# ---------------------------------------------------------------------------
# Action README (AC-7)
# ---------------------------------------------------------------------------

@test "AC-7: action README exists" {
  [[ -f "$ACTION_README" ]]
}

@test "AC-7: action README is standalone (no required Walter-OS knowledge)" {
  # README must explicitly say it's usable without adopting Walter-OS.
  grep -qiE "standalone|do NOT need to adopt|without adopting|usable from your" "$ACTION_README"
}

@test "AC-7: action README documents all 7 inputs + 3 outputs" {
  # Lightweight check: the README has tables that name each input/output.
  grep -q "pr-number" "$ACTION_README"
  grep -q "base-branch" "$ACTION_README"
  grep -q "severity-gate-config" "$ACTION_README"
  grep -q "run-codex" "$ACTION_README"
  grep -q "run-copilot" "$ACTION_README"
  grep -q "findings-json" "$ACTION_README"
  grep -q "rounds-completed" "$ACTION_README"
  grep -q "status" "$ACTION_README"
}

@test "AC-7: action README documents the Codex auth setup" {
  grep -qE "CODEX_AUTH_JSON|auth\\.json" "$ACTION_README"
}

# ---------------------------------------------------------------------------
# Regression: issue #186 — pin the documented `rounds-completed` JSON
# contract regardless of implementation details. Codex's sweep originally
# claimed `IFS=',' rounds_json="..."` produced space-separated output, but
# verification showed bash treats both as regular assignments when no
# command follows the prefix (so IFS *is* set and `${rounds[*]}` *is*
# comma-joined — output was always valid JSON). Refactor to the subshell
# form was for clarity + to avoid leaking IFS, NOT to fix a runtime bug.
# These tests assert the JSON-array contract so any future change is
# safely covered.
# ---------------------------------------------------------------------------

# Helper that simulates the action's rounds-completed assembly block in a
# subshell with controlled env, then validates the JSON output. The script
# under test is the literal bash block from action.yml's "Collect findings
# + emit status" step — extracted in a way the assertions can exercise
# without spinning up a GitHub Actions runner.
_simulate_rounds_completed() {
  local copilot="$1"
  local codex="$2"
  local out
  out=$(
    export COPILOT_REQUESTED="$copilot"
    export CODEX_RAN="$codex"
    rounds=()
    [[ "$COPILOT_REQUESTED" == "true" ]] && rounds+=('"copilot-round-1"')
    [[ "$CODEX_RAN" == "true" ]] && rounds+=('"codex-round-2"')
    # Pull the JSON-assembly line(s) from action.yml so this test stays
    # honest as the action evolves. NB: filter the eval'd block with
    # `[[:space:]]` — `\s` is a literal `s` in ERE, so `\s` would let the
    # `echo "rounds-completed=..." >> "$GITHUB_OUTPUT"` line through and
    # it would explode at eval time because GITHUB_OUTPUT is unset.
    #
    # Wrap the extracted block in a temp function so it tolerates `local`,
    # `return`, `declare`, etc. inside the block — the prior bare-eval
    # form would error with "local: can only be used in a function" if a
    # future action.yml refactor used any of those. The function body is
    # invoked immediately; `rounds_json` is exported back via the outer
    # subshell.
    local _block
    _block=$(awk '/# rounds-completed JSON array/,/echo "rounds-completed=\$rounds_json"/' "$ACTION_YML" \
      | grep -vE '^[[:space:]]*echo')
    eval "_rounds_completed_block() { ${_block} }"
    _rounds_completed_block
    printf '%s' "$rounds_json"
  )
  printf '%s' "$out"
}

@test "AC-8: rounds-completed is valid JSON when both rounds ran (regression #186)" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local out
  out=$(_simulate_rounds_completed true true)
  echo "Generated: $out" >&3
  jq -e . <<< "$out" >/dev/null
  # Specifically: must be a 2-element array
  local n
  n=$(jq -r 'length' <<< "$out")
  [[ "$n" == "2" ]]
  # And the values must match
  [[ "$(jq -r '.[0]' <<< "$out")" == "copilot-round-1" ]]
  [[ "$(jq -r '.[1]' <<< "$out")" == "codex-round-2" ]]
}

@test "AC-8: rounds-completed is valid JSON when only Copilot ran" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local out
  out=$(_simulate_rounds_completed true false)
  jq -e . <<< "$out" >/dev/null
  [[ "$(jq -r 'length' <<< "$out")" == "1" ]]
  [[ "$(jq -r '.[0]' <<< "$out")" == "copilot-round-1" ]]
}

@test "AC-8: rounds-completed is valid JSON when only Codex ran" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local out
  out=$(_simulate_rounds_completed false true)
  jq -e . <<< "$out" >/dev/null
  [[ "$(jq -r 'length' <<< "$out")" == "1" ]]
  [[ "$(jq -r '.[0]' <<< "$out")" == "codex-round-2" ]]
}

@test "AC-8: rounds-completed is [] when no rounds ran" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  local out
  out=$(_simulate_rounds_completed false false)
  jq -e . <<< "$out" >/dev/null
  [[ "$(jq -r 'length' <<< "$out")" == "0" ]]
}
