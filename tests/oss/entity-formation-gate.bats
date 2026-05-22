#!/usr/bin/env bats
# tests/oss/entity-formation-gate.bats
# Regression guard for the Xipher Labs entity formation gate (ADR-0022).
#
# The "gate" is policy + an advisory hook, not a hard runtime enforcement
# (entity formation is an external operator action). These tests verify
# the runbook exists, the advisory hook exists and behaves correctly in
# the documented states, and the runbook table is structurally sound.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/external-pr-merge-gate.sh"
  RUNBOOK="$REPO_ROOT/docs/operational/xipher-labs-entity-formation.md"
  ADR="$REPO_ROOT/docs/decisions/0022-xipher-labs-legal-entity.md"
}

# ---------------------------------------------------------------------------
# Runbook
# ---------------------------------------------------------------------------

@test "runbook exists at the documented path" {
  [[ -f "$RUNBOOK" ]]
}

@test "runbook references ADR-0022" {
  grep -q "0022-xipher-labs-legal-entity" "$RUNBOOK"
}

@test "runbook covers all 5 phases (0 prerequisites through 4 PR-unlock)" {
  grep -q "Phase 0" "$RUNBOOK"
  grep -q "Phase 1" "$RUNBOOK"
  grep -q "Phase 2" "$RUNBOOK"
  grep -q "Phase 3" "$RUNBOOK"
  grep -q "Phase 4" "$RUNBOOK"
}

@test "runbook records the constituted Argentine entity (Xipher Labs S.R.L.)" {
  # Post-Phase-1: the runbook records the constituted entity. ADR-0022
  # originally recommended S.A.S. — the operator chose S.R.L. for their
  # specific legal/tax situation, which the runbook documents.
  grep -q "Xipher Labs S.R.L." "$RUNBOOK"
  grep -qi "Argentina" "$RUNBOOK"
}

@test "runbook references the CLA activation (WALTER_CLA_ACTIVE)" {
  grep -q "WALTER_CLA_ACTIVE" "$RUNBOOK"
}

@test "runbook has a status snapshot table" {
  grep -q "Status snapshot" "$RUNBOOK"
}

# ---------------------------------------------------------------------------
# Advisory hook
# ---------------------------------------------------------------------------

@test "hook exists and is executable" {
  [[ -x "$HOOK" ]]
}

@test "hook has SPDX-License-Identifier (Apache-2.0 per ADR-0018)" {
  grep -q "SPDX-License-Identifier: Apache-2.0" "$HOOK"
}

@test "hook returns 2 with usage when called without arguments" {
  run "$HOOK"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "missing argument" ]]
}

@test "hook returns 0 (gate clear) when entity marker exists" {
  local tmp_marker
  tmp_marker="$(mktemp -d)/entity-formed"
  : > "$tmp_marker"
  # Use a fake PR ref — when marker exists the hook does not call gh.
  WALTER_ENTITY_FORMED_MARKER="$tmp_marker" run "$HOOK" 999999
  [[ "$status" -eq 0 ]]
  rm -rf "$(dirname "$tmp_marker")"
}

@test "hook refuses without WALTER_OPERATOR_GH_LOGIN" {
  # When the marker is absent and the operator login is unset, the hook
  # cannot determine "external vs operator" and must refuse with exit 2.
  # Use a fake marker path that does not exist.
  local missing_marker
  missing_marker="$(mktemp -u)"
  # gh may not be installed in CI; if it is, the call would happen before
  # the operator-login check. Cover both cases by mocking gh.
  local tmp_path_dir
  tmp_path_dir="$(mktemp -d)"
  cat > "$tmp_path_dir/gh" <<'MOCK'
#!/usr/bin/env bash
# Return a deterministic author for any args
echo "some-external-contributor"
MOCK
  chmod +x "$tmp_path_dir/gh"
  WALTER_OPERATOR_GH_LOGIN="" \
  WALTER_ENTITY_FORMED_MARKER="$missing_marker" \
  PATH="$tmp_path_dir:$PATH" \
  run "$HOOK" 123
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "WALTER_OPERATOR_GH_LOGIN" ]]
  rm -rf "$tmp_path_dir"
}

@test "hook returns 0 (gate clear) when PR author is the operator" {
  local missing_marker
  missing_marker="$(mktemp -u)"
  local tmp_path_dir
  tmp_path_dir="$(mktemp -d)"
  cat > "$tmp_path_dir/gh" <<'MOCK'
#!/usr/bin/env bash
# Return the operator login as the author
echo "operator-login"
MOCK
  chmod +x "$tmp_path_dir/gh"
  WALTER_OPERATOR_GH_LOGIN="operator-login" \
  WALTER_ENTITY_FORMED_MARKER="$missing_marker" \
  PATH="$tmp_path_dir:$PATH" \
  run "$HOOK" 123
  [[ "$status" -eq 0 ]]
  rm -rf "$tmp_path_dir"
}

@test "hook returns 0 (gate clear) when PR author is dependabot" {
  local missing_marker
  missing_marker="$(mktemp -u)"
  local tmp_path_dir
  tmp_path_dir="$(mktemp -d)"
  cat > "$tmp_path_dir/gh" <<'MOCK'
#!/usr/bin/env bash
echo "dependabot[bot]"
MOCK
  chmod +x "$tmp_path_dir/gh"
  WALTER_OPERATOR_GH_LOGIN="operator-login" \
  WALTER_ENTITY_FORMED_MARKER="$missing_marker" \
  PATH="$tmp_path_dir:$PATH" \
  run "$HOOK" 123
  [[ "$status" -eq 0 ]]
  rm -rf "$tmp_path_dir"
}

@test "hook returns 1 (gate engaged) for external PR without entity marker" {
  local missing_marker
  missing_marker="$(mktemp -u)"
  local tmp_path_dir
  tmp_path_dir="$(mktemp -d)"
  cat > "$tmp_path_dir/gh" <<'MOCK'
#!/usr/bin/env bash
echo "external-contributor"
MOCK
  chmod +x "$tmp_path_dir/gh"
  WALTER_OPERATOR_GH_LOGIN="operator-login" \
  WALTER_ENTITY_FORMED_MARKER="$missing_marker" \
  PATH="$tmp_path_dir:$PATH" \
  run "$HOOK" 123
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "REFUSING MERGE OF EXTERNAL PR" ]]
  rm -rf "$tmp_path_dir"
}
