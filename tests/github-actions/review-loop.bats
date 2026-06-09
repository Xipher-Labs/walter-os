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

@test "AC-1: action declares optional input base-branch with safe default" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+base-branch:"
  awk '/^[[:space:]]+base-branch:/,/^[[:space:]]+severity-gate-config:/' "$ACTION_YML" \
    | grep -qE "^[[:space:]]+required:[[:space:]]+false[[:space:]]*$"
  awk '/^[[:space:]]+base-branch:/,/^[[:space:]]+severity-gate-config:/' "$ACTION_YML" \
    | grep -qE "^[[:space:]]+default:[[:space:]]+main[[:space:]]*$"
}

@test "AC-1: action declares optional input severity-gate-config" {
  awk '/^inputs:/,/^outputs:/' "$ACTION_YML" | grep -qE "^[[:space:]]+severity-gate-config:"
}

@test "AC-1: severity-gate-config is documented as v1 placeholder" {
  awk '/^[[:space:]]+severity-gate-config:/,/^[[:space:]]+run-copilot:/' "$ACTION_YML" \
    | grep -qiE "v1 placeholder|currently not read"
  grep -qiE "severity-gate-config.*v1 placeholder|v1 placeholder.*severity-gate-config" "$ACTION_README"
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
  if grep -q "gh pr edit --add-reviewer" "$ACTION_YML"; then
    echo "action.yml should not use the broken gh pr edit reviewer path" >&2
    return 1
  fi
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
  # approval_policy = "never", pins the supported model, and inherits auth.json.
  grep -q 'approval_policy = "never"' "$ACTION_YML"
  grep -q 'model = "gpt-5.5"' "$ACTION_YML"
  grep -q "auth.json" "$ACTION_YML"
  awk '/Codex Round 2/,/printf/' "$ACTION_YML" \
    | grep -qE 'umask[[:space:]]+077'
  grep -qE 'if ! mkdir -p "\$CODEX_HOME_INPUT" \|\| ! chmod[[:space:]]+700[[:space:]]+"\$CODEX_HOME_INPUT"' "$ACTION_YML"
  grep -qE 'chmod[[:space:]]+700[[:space:]]+"\$CODEX_HOME_INPUT"' "$ACTION_YML"
  grep -q "Could not prepare secure CODEX_HOME" "$ACTION_YML"
  grep -qE 'chmod[[:space:]]+600[[:space:]]+"\$CODEX_HOME_INPUT/config\.toml"' "$ACTION_YML"
  grep -q "Could not write secure Codex config" "$ACTION_YML"
  grep -qE 'chmod[[:space:]]+600[[:space:]]+"\$CODEX_HOME_INPUT/auth\.json"' "$ACTION_YML"
  grep -q "Could not restrict.*auth.json permissions" "$ACTION_YML"
}

@test "AC-4: Codex step skips when no auth.json is mounted" {
  # The step must NOT fail when auth.json is absent — that's the
  # natural state for forks that haven't set up CODEX_AUTH_JSON.
  grep -qE "\\! -f.*auth\\.json|auth.json.*missing" "$ACTION_YML"
}

@test "AC-4: Codex step uses documented codex review command" {
  grep -qE 'codex[[:space:]]+review[[:space:]]+--base[[:space:]]+"\$BASE_BRANCH"' "$ACTION_YML"
  if grep -qE 'codex[[:space:]]+exec[[:space:]]+review' "$ACTION_YML"; then
    echo "action.yml should use codex review, not codex exec review" >&2
    return 1
  fi
  grep -qE 'codex[[:space:]]+review' "$ACTION_README"
  if grep -qE 'codex[[:space:]]+exec[[:space:]]+review' "$ACTION_README"; then
    echo "README should document codex review, not codex exec review" >&2
    return 1
  fi
}

@test "AC-4: Codex step writes review output to a restricted temp file" {
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE 'umask[[:space:]]+077'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE '\[\[ ! -d "\$codex_output_dir" \]\]'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE 'codex_output_dir="/tmp"'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE 'if ! codex_output=.\$\(mktemp "\$codex_output_dir/codex-review\.XXXXXX"\)'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -q "Could not create secure Codex output file"
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE 'chmod[[:space:]]+600[[:space:]]+"\$codex_output"'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -q "Could not restrict Codex output file permissions"
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE '> "\$codex_output"[[:space:]]+2>&1'
}

@test "AC-4: review loop does not use fixed /tmp/codex-review.txt" {
  if grep -R "/tmp/codex-review.txt" \
    "$ACTION_YML" \
    "$ACTION_README" \
    "$WORKFLOW"; then
    echo "review-loop surfaces should not use a fixed shared /tmp/codex-review.txt path" >&2
    return 1
  fi
}

@test "AC-4: Codex step only marks ran true after command success" {
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -qE 'if[[:space:]]+CODEX_HOME="\$CODEX_HOME_INPUT"[[:space:]]+codex[[:space:]]+review.*> "\$codex_output"'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -q 'codex-ran=true'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -q 'codex-ran=false'
  awk '/Codex Round 2/,/Collect findings/' "$ACTION_YML" \
    | grep -q 'Codex review failed'
}

@test "AC-4: Codex empty output still counts as a completed round" {
  awk '/if CODEX_HOME=.*codex review/,/else/' "$ACTION_YML" \
    | grep -q 'codex-ran=true'
  if awk '/Codex produced no output/,/fi/' "$ACTION_YML" | grep -q 'codex-ran=false'; then
    echo "empty successful Codex output should not mark codex-ran=false" >&2
    return 1
  fi
  awk '/if CODEX_HOME=.*codex review/,/Codex review failed/' "$ACTION_YML" \
    | grep -q 'Output path: $codex_output'
}

@test "AC-4: Codex failure warning includes output path" {
  awk '/else/,/echo "::endgroup::"/' "$ACTION_YML" \
    | grep -q 'Codex review failed with exit code'
  awk '/else/,/echo "::endgroup::"/' "$ACTION_YML" \
    | grep -q 'Output path: $codex_output'
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
  if awk '/^permissions:/,/^jobs:/' "$WORKFLOW" | grep -q "issues: write"; then
    echo "pr-review.yml should not request issues: write in v1" >&2
    return 1
  fi
}

@test "AC-5: workflow writes Codex auth with restrictive permissions" {
  awk '/Mount Codex auth/,/Run Walter-OS review loop/' "$WORKFLOW" \
    | grep -qE "umask[[:space:]]+077"
  awk '/Mount Codex auth/,/Run Walter-OS review loop/' "$WORKFLOW" \
    | grep -qE "chmod[[:space:]]+600[[:space:]]+/tmp/codex-minimal/auth\\.json"
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

@test "AC-7: action README documents capability-aware Codex usage" {
  grep -q "walter ai status" "$ACTION_README"
  grep -q "CODEX_AUTH_JSON" "$ACTION_README"
  grep -q "run-codex: false" "$ACTION_README"
}

@test "AC-7: action README documents the Codex auth setup" {
  grep -qE "CODEX_AUTH_JSON|auth\\.json" "$ACTION_README"
  grep -qE "umask[[:space:]]+077" "$ACTION_README"
  grep -qE "chmod[[:space:]]+600[[:space:]]+/tmp/codex-minimal/auth\\.json" "$ACTION_README"
}

@test "AC-7: action README uses standalone GitHub links" {
  if grep -qE '\]\(\\.\\./\\.\\./\\.\\./' "$ACTION_README"; then
    echo "README should not use repo-relative links that break downstream" >&2
    return 1
  fi
  grep -qE 'https://github.com/Xipher-Labs/walter-os/' "$ACTION_README"
}

# ---------------------------------------------------------------------------
# Regression: issue #185 — pr-review.yml's Codex auth mount step used a
# step-level `if: ${{ env.CODEX_AUTH_JSON != '' }}` which is evaluated
# BEFORE the step-level env block, so the step was always skipped on
# this repo. The fix is to drop the `if:` and gate inside the shell.
# ---------------------------------------------------------------------------

@test "AC-9 (#185): pr-review.yml Codex mount step does NOT use step-level if-on-env" {
  # The buggy pattern was:
  #   - name: Mount Codex auth (Round 2 enable)
  #     env:
  #       CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
  #     if: ${{ env.CODEX_AUTH_JSON != '' }}
  # GitHub evaluates `if:` BEFORE the step's `env:` block, so the
  # env reference is always empty → step never runs.
  if grep -qE 'if: \$\{\{ env\.CODEX_AUTH_JSON' "$WORKFLOW"; then
    echo "pr-review.yml still uses the broken step-level if-on-env pattern (#185)" >&2
    return 1
  fi
}

@test "AC-9 (#185): pr-review.yml Codex mount step gates inside the shell" {
  # The fix is to remove the `if:` and check `[[ -z "$CODEX_AUTH_JSON" ]]`
  # in the shell. That ensures the step runs and the env var has been
  # mapped by the time we check.
  awk '/Mount Codex auth/,/Run Walter-OS review loop/' "$WORKFLOW" \
    | grep -qE '\[\[ -z "\$CODEX_AUTH_JSON" \]\]|\[ -z "\$CODEX_AUTH_JSON" \]'
}

# ---------------------------------------------------------------------------
# Regression: issue #184 — pr-review.yml example should pass github-token
# explicitly even though the action defaults it (defensive — composite
# action input default resolution timing has been fragile in past
# GitHub-Actions versions).
# ---------------------------------------------------------------------------

@test "AC-9 (#184): pr-review.yml passes github-token to the action explicitly" {
  awk '/uses:.*walter-review-loop/,/^      - name:/' "$WORKFLOW" \
    | grep -qE 'github-token:[[:space:]]+\$\{\{[[:space:]]*github\.token[[:space:]]*\}\}'
}

@test "AC-9 (#184): action README example passes github-token explicitly" {
  # The README's quickstart example should match what pr-review.yml does
  # so adopters copying the example don't hit the issue.
  awk '/uses: Xipher-Labs\/walter-os\/.github\/actions\/walter-review-loop/,/Post status/' \
    "$ACTION_README" \
    | grep -qE 'github-token:[[:space:]]+\$\{\{[[:space:]]*github\.token[[:space:]]*\}\}'
}

@test "AC-9 (#185): action README Codex-auth snippet does NOT use step-level if-on-env" {
  # The README "Setting up Codex Round 2" snippet had the same foot-gun
  # as pr-review.yml's workflow step (`if: ${{ env.CODEX_AUTH_JSON ... }}`
  # is evaluated before step `env:` is applied, so the snippet would
  # always skip when adopters copied it verbatim). Copilot R1 #193.
  # Awk-range gotcha: `/^## Setting up.../,/^## /` matches the start
  # line for BOTH bounds (since ^## also matches the start heading
  # itself), so it captures only one line. Use a flag-driven extraction
  # that flips on at the section header + flips off at the NEXT
  # heading.
  #
  # Anchor the grep on optional-whitespace-then-`if:` so a markdown
  # blockquote (`> **Note**: Do NOT use ...`) explaining the foot-gun
  # is correctly NOT flagged. The actual broken pattern would appear
  # at the start of a yaml step line (`  if: ...`), with only
  # whitespace as the prefix.
  awk '/^## Setting up Codex Round 2/{flag=1;next} flag && /^## /{flag=0} flag' \
    "$ACTION_README" \
    | { ! grep -qE '^[[:space:]]+if:[[:space:]]*\$\{\{[[:space:]]*env\.CODEX_AUTH_JSON'; }
}

@test "AC-9 (#185): action README Codex-auth snippet gates inside the shell" {
  awk '/^## Setting up Codex Round 2/{flag=1;next} flag && /^## /{flag=0} flag' \
    "$ACTION_README" \
    | grep -qE '\[\[ -z "\$CODEX_AUTH_JSON" \]\]|\[ -z "\$CODEX_AUTH_JSON" \]'
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
