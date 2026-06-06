#!/usr/bin/env bats
# Static coverage for Walter-VM Ansible syntax-check wiring.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLAYBOOK="$REPO_ROOT/ansible/walter-vm.yml"
  WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
  ALERTING_ROLE="$REPO_ROOT/ansible/roles/alerting/tasks/main.yml"
  CLOUDFLARED_ROLE="$REPO_ROOT/ansible/roles/cloudflared/tasks/main.yml"
  README="$REPO_ROOT/ansible/README.md"
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
  grep -Fq "working-directory: ansible" "$WORKFLOW"
  grep -Fq "ansible-playbook --syntax-check walter-vm.yml -i inventory.yml" "$WORKFLOW"
}

@test "alerting role treats /etc/walter-vm as root-only secrets dir" {
  [[ -f "$ALERTING_ROLE" ]]
  [[ -f "$README" ]]

  grep -Fq "path: /etc/walter-vm" "$ALERTING_ROLE"
  grep -Fq 'mode: "0700"' "$ALERTING_ROLE"
  grep -Fq "sudo install -m 600" "$ALERTING_ROLE"
  ! grep -Fq "operator-owned credentials" "$README"
}

@test "cloudflared role pins package key and avoids unused packages" {
  [[ -f "$CLOUDFLARED_ROLE" ]]

  grep -Fq "checksum: sha256:1bd95f4082b320d541bee351560fc2765aa9f9cd8efa4c9e32135e63f252721d" "$CLOUDFLARED_ROLE"
  grep -Fq "CC94 B39C 77AE 7342 A68B 8962 8A68 2D30 8D4E 5E73" "$CLOUDFLARED_ROLE"
  grep -Fq "walter_cloudflared_config_copy" "$CLOUDFLARED_ROLE"
  grep -Fq "restarted" "$CLOUDFLARED_ROLE"
  ! grep -Fq "lsb-release" "$CLOUDFLARED_ROLE"
}
