#!/usr/bin/env bats
# tests/cli/doctor-cursor.bats
#
# Verifies the `walter-os doctor --cursor` subcommand.
# Spec: docs/specs/cursor-adapter-completion.md (AC-3)
#
# Three states tested:
#   NOT_GENERATED — no .cursor/rules/walter-os.mdc in cwd
#   PASS          — file exists, recorded hash matches current AGENTS.md
#   STALE         — file exists, recorded hash differs

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WO_BIN="$REPO_ROOT/bin/walter-os"
  # bin/walter-os requires WALTER_OS_HOME so it can locate VERSION, the
  # subcommand scripts, etc. Tests in tests/cli/ all export this — match
  # the established pattern.
  export WALTER_OS_HOME="$REPO_ROOT"
  FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
  mkdir -p "$FAKE_REPO"
  cat > "$FAKE_REPO/AGENTS.md" <<'EOF'
# AGENTS.md — test fixture
Test content for the bats suite.
EOF
}

# Generate the adapter via the install.sh path, so the test exercises the
# real production path rather than a synthesized fixture file.
_generate_adapter() {
  (
    cd "$FAKE_REPO"
    DRY_RUN=0 CHECK_ONLY=0 UPGRADE=0 UNINSTALL=0 STEP_ONLY="" \
      bash "$REPO_ROOT/install.sh" --cursor-rules
  ) > /dev/null
}

_run_doctor() {
  (cd "$FAKE_REPO" && WALTER_OS_HOME="$REPO_ROOT" bash "$WO_BIN" doctor --cursor)
}

@test "AC-3: doctor --cursor reports NOT_GENERATED when adapter is absent" {
  run _run_doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "NOT_GENERATED" ]]
}

@test "AC-3: doctor --cursor reports PASS after install.sh --cursor-rules" {
  _generate_adapter
  run _run_doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "PASS" ]]
}

@test "AC-3: doctor --cursor reports STALE when AGENTS.md changes after generation" {
  _generate_adapter
  # Mutate AGENTS.md AFTER the adapter is generated.
  echo "## Some new section" >> "$FAKE_REPO/AGENTS.md"
  run _run_doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "STALE" ]]
}

@test "AC-3: doctor --cursor flag is wired in cmd_doctor" {
  grep -q -- "--cursor" "$WO_BIN"
  grep -q "_doctor_cursor_probe" "$WO_BIN"
}

@test "AC-3: doctor --cursor probe function is defined" {
  grep -q "^_doctor_cursor_probe()" "$WO_BIN"
}
