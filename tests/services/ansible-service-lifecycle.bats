#!/usr/bin/env bats
# Static coverage for declarative lifecycle state in the Ansible service role.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SERVICE_ROLE="$REPO_ROOT/ansible/roles/service/tasks/main.yml"
  README="$REPO_ROOT/ansible/README.md"
}

@test "service role declares present stopped absent lifecycle states" {
  [[ -f "$SERVICE_ROLE" ]]

  grep -Fq "walter_service_state" "$SERVICE_ROLE"
  grep -Fq "service_state | default('present')" "$SERVICE_ROLE"
  grep -Fq "present" "$SERVICE_ROLE"
  grep -Fq "stopped" "$SERVICE_ROLE"
  grep -Fq "absent" "$SERVICE_ROLE"
}

@test "present state is the only state that pulls and starts containers" {
  [[ -f "$SERVICE_ROLE" ]]

  grep -Fq "docker compose pull" "$SERVICE_ROLE"
  grep -Fq "docker compose --env-file .env up -d" "$SERVICE_ROLE"
  grep -Fq "walter_service_state == 'present'" "$SERVICE_ROLE"
}

@test "stopped state stops containers without removing them" {
  [[ -f "$SERVICE_ROLE" ]]

  grep -Fq "docker compose stop" "$SERVICE_ROLE"
  grep -Fq "stop_result.stderr | default('')" "$SERVICE_ROLE"
  ! grep -Fq "docker compose stop -v" "$SERVICE_ROLE"
}

@test "absent state removes containers without deleting volumes" {
  [[ -f "$SERVICE_ROLE" ]]

  grep -Fq "docker compose down" "$SERVICE_ROLE"
  grep -Fq "down_result.stderr | default('')" "$SERVICE_ROLE"
  ! grep -Fq "docker compose down -v" "$SERVICE_ROLE"
}

@test "README documents service_state lifecycle contract" {
  [[ -f "$README" ]]

  grep -Fq "service_state" "$README"
  grep -Fq "present" "$README"
  grep -Fq "stopped" "$README"
  grep -Fq "absent" "$README"
  grep -Fq 'default `present` state' "$README"
  grep -Fq "never removes volumes" "$README"
}
