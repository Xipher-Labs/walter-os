#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  UPGRADE_SH="$REPO_ROOT/scripts/upgrade.sh"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_OS_SKIP_UPDATE_CHECK=1
  export WALTER_CONFIG="$BATS_TEST_TMPDIR/walter-config"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$WALTER_CONFIG" "$HOME"
}

@test "walter-os help lists upgrade" {
  grep -q "#   upgrade" "$WALTER_OS_BIN"
  grep -q "upgrade) *cmd_upgrade" "$WALTER_OS_BIN"
}

@test "upgrade dry-run defaults to local plan" {
  run bash "$UPGRADE_SH" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Walter-OS upgrade plan"
  echo "$output" | grep -q "mode: local"
  echo "$output" | grep -q "fetch --quiet"
  echo "$output" | grep -q "install.sh --upgrade"
  echo "$output" | grep -q "walter-os audit"
  echo "$output" | grep -q "walter-os doctor"
}

@test "upgrade dry-run can skip audit and doctor" {
  run bash "$UPGRADE_SH" --dry-run --skip-audit --skip-doctor
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "walter-os audit"
  ! echo "$output" | grep -q "walter-os doctor"
}

@test "upgrade all dry-run with snapshot and service shows VM plan" {
  run bash "$UPGRADE_SH" --all --dry-run --snapshot --service n8n
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mode: all"
  echo "$output" | grep -q "walter vm snapshot pre-upgrade-"
  echo "$output" | grep -q "ssh walter-vm"
  echo "$output" | grep -q "walter deploy n8n"
}

@test "upgrade rejects target with VM-only mode" {
  run bash "$UPGRADE_SH" --vm --target v0.6.0 --dry-run
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--target applies only to local upgrades"
}

@test "upgrade rejects snapshot without VM mode" {
  run bash "$UPGRADE_SH" --snapshot --dry-run
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--snapshot requires --vm or --all"
}

@test "upgrade VM snapshot requires confirmation outside dry-run" {
  run bash "$UPGRADE_SH" --vm --snapshot
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--snapshot requires --yes"
}
