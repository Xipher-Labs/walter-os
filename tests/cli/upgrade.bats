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

make_upgrade_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts"
  cp "$UPGRADE_SH" "$repo/scripts/upgrade.sh"
  cat > "$repo/install.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > install-args.txt
touch install-ran
SH
  chmod +x "$repo/install.sh"
  printf '0.6.0\n' > "$repo/VERSION"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.invalid"
  git -C "$repo" config user.name "Walter Test"
  git -C "$repo" add .
  git -C "$repo" commit -qm "fixture"
}

@test "walter-os help lists upgrade" {
  grep -q "#   upgrade" "$WALTER_OS_BIN"
  grep -q "upgrade) *cmd_upgrade" "$WALTER_OS_BIN"
  grep -q 'exec bash.*scripts/upgrade.sh' "$WALTER_OS_BIN"
  grep -q 'exec bash.*scripts/sync.sh' "$WALTER_OS_BIN"
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

@test "upgrade dry-run prints an operator summary" {
  run bash "$UPGRADE_SH" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Upgrade summary"
  echo "$output" | grep -q "dry-run: no changes applied"
  echo "$output" | grep -q "Next step: run walter-os upgrade without --dry-run"
}

@test "upgrade local target prints summary after install" {
  local repo="$BATS_TEST_TMPDIR/upgrade-repo"
  make_upgrade_fixture_repo "$repo"

  run bash "$repo/scripts/upgrade.sh" --target HEAD --skip-audit --skip-doctor

  [ "$status" -eq 0 ]
  [ -f "$repo/install-ran" ]
  grep -q -- "--upgrade" "$repo/install-args.txt"
  echo "$output" | grep -q "Upgrade summary"
  echo "$output" | grep -q "mode: local"
  echo "$output" | grep -q "version: 0.6.0"
  echo "$output" | grep -q "audit: skipped"
  echo "$output" | grep -q "doctor: skipped"
  echo "$output" | grep -q "rollback: git -C"
}

@test "upgrade local refuses dirty tree before install" {
  local repo="$BATS_TEST_TMPDIR/dirty-upgrade-repo"
  make_upgrade_fixture_repo "$repo"
  printf 'dirty\n' >> "$repo/VERSION"

  run bash "$repo/scripts/upgrade.sh" --target HEAD --skip-audit --skip-doctor

  [ "$status" -eq 2 ]
  echo "$output" | grep -q "working tree dirty"
  [ ! -f "$repo/install-ran" ]
}

@test "upgrade dry-run can skip audit and doctor" {
  run bash "$UPGRADE_SH" --dry-run --skip-audit --skip-doctor
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "walter-os audit"
  ! echo "$output" | grep -q "walter-os doctor"
}

@test "upgrade target dry-run fetches tags from all remotes" {
  run bash "$UPGRADE_SH" --dry-run --target v0.6.0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "fetch --all --tags --quiet"
  echo "$output" | grep -q "checkout v0.6.0"
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

@test "upgrade validates VM snapshot confirmation before local mutations" {
  run bash "$UPGRADE_SH" --all --snapshot
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--snapshot requires --yes"
  ! echo "$output" | grep -q "==> Local Walter-OS checkout"
}

@test "upgrade rejects service rollout in local mode" {
  run bash "$UPGRADE_SH" --dry-run --service n8n
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--service requires --vm or --all"
}

@test "upgrade rejects unsafe service names" {
  run bash "$UPGRADE_SH" --all --dry-run --service 'n8n;touch /tmp/pwned'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "unsafe service name"
}

@test "upgrade VM command checks remote checkout is clean" {
  run bash "$UPGRADE_SH" --vm --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'test\\ -z'
  echo "$output" | grep -q 'git\\ status\\ --porcelain'
}

@test "upgrade does not expose partial VM host override" {
  WALTER_VM_HOST=other-vm run bash "$UPGRADE_SH" --vm --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "vm host: walter-vm"
  ! echo "$output" | grep -q "other-vm"
}

@test "sync alias remains local-only even when VM mode is passed" {
  run bash "$REPO_ROOT/scripts/sync.sh" --dry-run --vm
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mode: local"
  ! echo "$output" | grep -q "ssh walter-vm"
}
