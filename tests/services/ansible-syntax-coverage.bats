#!/usr/bin/env bats
# Static coverage for Walter-VM Ansible syntax-check wiring.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLAYBOOK="$REPO_ROOT/ansible/walter-vm.yml"
  WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
}

@test "walter-vm playbook referenced roles exist" {
  [[ -f "$PLAYBOOK" ]]

  [[ -f "$REPO_ROOT/ansible/roles/base/tasks/main.yml" ]]
  [[ -f "$REPO_ROOT/ansible/roles/cloudflared/tasks/main.yml" ]]
  [[ -f "$REPO_ROOT/ansible/roles/service/tasks/main.yml" ]]
  [[ -f "$REPO_ROOT/ansible/roles/alerting/tasks/main.yml" ]]
}

@test "ci runs Ansible syntax-check for walter-vm playbook" {
  [[ -f "$WORKFLOW" ]]

  grep -Fq "name: ansible syntax-check" "$WORKFLOW"
  grep -Fq "ansible-playbook --syntax-check ansible/walter-vm.yml -i ansible/inventory.yml" "$WORKFLOW"
}
