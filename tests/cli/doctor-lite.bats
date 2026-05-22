#!/usr/bin/env bats
# tests/cli/doctor-lite.bats
#
# Verifies `walter-os doctor --lite`.
# Spec: docs/specs/walter-os-lite-entry-tier.md (AC-6)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WO_BIN="$REPO_ROOT/bin/walter-os"
  FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
  mkdir -p "$FAKE_REPO"
}

_run_doctor() {
  (cd "$FAKE_REPO" && bash "$WO_BIN" doctor --lite)
}

@test "AC-6: doctor --lite returns NONE when no Lite contract is installed" {
  run _run_doctor
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "NONE" ]]
}

@test "AC-6: doctor --lite returns PASS when .walter-os-lite/AGENTS.md exists" {
  mkdir -p "$FAKE_REPO/.walter-os-lite"
  cat > "$FAKE_REPO/.walter-os-lite/AGENTS.md" <<'EOF'
# Walter-OS Lite (persisted contract)

## 1. Rigor

content

## 2. TDD

content
EOF
  run _run_doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "PASS" ]]
}

@test "AC-6: doctor --lite PASS output lists the discipline headings" {
  mkdir -p "$FAKE_REPO/.walter-os-lite"
  cat > "$FAKE_REPO/.walter-os-lite/AGENTS.md" <<'EOF'
# Walter-OS Lite

## 1. Rigor
## 2. TDD
## 3. Conventional commits
## 4. Branch flow
## 5. Self-review
## 6. Hard nevers
EOF
  run _run_doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Rigor" ]]
  [[ "$output" =~ "TDD" ]]
  [[ "$output" =~ "Hard nevers" ]]
}

@test "AC-6: doctor --lite flag is wired in cmd_doctor" {
  grep -q -- "--lite" "$WO_BIN"
  grep -q "_doctor_lite_probe" "$WO_BIN"
}

@test "AC-6: doctor --lite probe function is defined" {
  grep -q "^_doctor_lite_probe()" "$WO_BIN"
}
