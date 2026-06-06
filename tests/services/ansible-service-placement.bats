#!/usr/bin/env bats
# Static coverage for optional Ansible service-placement overlays.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLAYBOOK="$REPO_ROOT/ansible/walter-vm.yml"
  SERVICE_ROLE="$REPO_ROOT/ansible/roles/service/tasks/main.yml"
  README="$REPO_ROOT/ansible/README.md"
  EXAMPLE="$REPO_ROOT/ansible/examples/service-placement.example.yml"
}

@test "walter-vm playbook loads optional placement manifest from env" {
  [[ -f "$PLAYBOOK" ]]

  grep -Fq "WALTER_SERVICE_PLACEMENT_FILE" "$PLAYBOOK"
  grep -Fq "walter_service_placement_file" "$PLAYBOOK"
  grep -Fq "walter_service_placement_path" "$PLAYBOOK"
  grep -Fq "include_vars" "$PLAYBOOK"
  grep -Fq "walter_service_placement" "$PLAYBOOK"
}

@test "walter-vm playbook filters placement by current host groups" {
  [[ -f "$PLAYBOOK" ]]

  grep -Fq "walter_enabled_services" "$PLAYBOOK"
  grep -Fq "dict2items" "$PLAYBOOK"
  grep -Fq "intersect(group_names)" "$PLAYBOOK"
}

@test "service role preserves single-host fallback and skips unassigned services" {
  [[ -f "$SERVICE_ROLE" ]]

  grep -Fq "walter_service_should_deploy" "$SERVICE_ROLE"
  grep -Fq "walter_enabled_services is not defined or service_name in walter_enabled_services" "$SERVICE_ROLE"
  grep -Fq "when: walter_service_should_deploy | bool" "$SERVICE_ROLE"
  grep -Fq "svc_env.stat.exists | default(false)" "$SERVICE_ROLE"
  grep -Fq "svc_env_template.stat.exists | default(false)" "$SERVICE_ROLE"
  grep -Fq "svc_env is defined" "$SERVICE_ROLE"
  grep -Fq "svc_env_template is defined" "$SERVICE_ROLE"
  ! grep -Fq "svc_files" "$SERVICE_ROLE"
}

@test "placement-only set_fact tasks do not mark runs changed" {
  [[ -f "$PLAYBOOK" ]]
  [[ -f "$SERVICE_ROLE" ]]

  [[ "$(grep -c "changed_when: false" "$PLAYBOOK")" -ge 2 ]]
  [[ "$(grep -c "changed_when: false" "$SERVICE_ROLE")" -ge 1 ]]
}

@test "service placement example documents generic overlay shape" {
  [[ -f "$EXAMPLE" ]]
  [[ -f "$README" ]]

  grep -Fq "services:" "$EXAMPLE"
  grep -Fq "vms:" "$EXAMPLE"
  grep -Fq "WALTER_SERVICE_PLACEMENT_FILE" "$README"
  grep -Fq "ansible/examples/service-placement.example.yml" "$README"
}
