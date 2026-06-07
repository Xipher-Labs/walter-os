#!/usr/bin/env bats
# Coverage for walter-os svc compose lifecycle wrapper.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME/.config/walter-os" "$TEST_HOME/walter-os"
}

run_walter_os() {
  HOME="$TEST_HOME" WALTER_OS_HOME="$REPO_ROOT" "$WALTER_OS_BIN" "$@"
}

@test "svc dry-run up pulls and starts the named service" {
  run run_walter_os svc up litellm --services-dir /opt/walter-vm/services --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"cd /opt/walter-vm/services/litellm"* ]]
  [[ "$output" == *"docker compose pull && docker compose up -d"* ]]
}

@test "svc dry-run down never removes volumes" {
  run run_walter_os svc down posthog --services-dir /opt/walter-vm/services --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"docker compose down"* ]]
  [[ "$output" != *"down -v"* ]]
}

@test "svc dry-run supports remote host execution" {
  run run_walter_os svc stop plane --host walter-vm --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh walter-vm"* ]]
  [[ "$output" == *"/opt/walter-vm/services/plane"* ]]
  [[ "$output" == *"docker\\ compose\\ stop"* ]]
}

@test "svc rejects path traversal service names" {
  run run_walter_os svc ps ../litellm --dry-run

  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid service name"* ]]
}

@test "top-level help lists svc subcommand" {
  run run_walter_os help

  [ "$status" -eq 0 ]
  [[ "$output" == *"svc {up|stop|down|restart|ps|logs|apply}"* ]]
}

@test "svc help exits cleanly" {
  run run_walter_os svc --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: walter-os svc"* ]]
}
