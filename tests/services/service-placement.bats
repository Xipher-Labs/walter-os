#!/usr/bin/env bats
# Static coverage for ADR-0028 service placement metadata.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLACEMENT="$REPO_ROOT/ansible/service-placement.yml"
  INVENTORY="$REPO_ROOT/ansible/inventory.yml"
  ADR="$REPO_ROOT/docs/decisions/0028-two-vm-segregation-llm-ha.md"
}

@test "service placement uses inventory group identifiers" {
  [[ -f "$PLACEMENT" ]]
  [[ -f "$INVENTORY" ]]

  grep -Fq "vm_core:" "$INVENTORY"
  grep -Fq "vm_aux:" "$INVENTORY"
  grep -Fq "vm_core:" "$PLACEMENT"
  grep -Fq "vm_aux:" "$PLACEMENT"
  ! grep -Fq "vm-core" "$PLACEMENT"
  ! grep -Fq "vm-aux" "$PLACEMENT"
}

@test "service placement states current Ansible consumption limits" {
  [[ -f "$PLACEMENT" ]]
  [[ -f "$ADR" ]]

  grep -Fq "does not consume this file yet" "$PLACEMENT"
  grep -Fq "yet consumed by" "$ADR"
  grep -Fq "hosts: walter_vm" "$ADR"
}

@test "non-directory placement entries declare their deploy unit" {
  [[ -f "$PLACEMENT" ]]

  grep -A4 -F "litellm-db:" "$PLACEMENT" | grep -Fq "deploy_unit: compose_service"
  grep -A4 -F "litellm-db:" "$PLACEMENT" | grep -Fq "service_dir: litellm"
  grep -A5 -F "observability-agents:" "$PLACEMENT" | grep -Fq "deploy_unit: host_agent_bundle"
  grep -A5 -F "observability-agents:" "$PLACEMENT" | grep -Fq "service_dir: observability"
}

@test "declared service directories exist" {
  [[ -f "$PLACEMENT" ]]

  while IFS= read -r service_dir; do
    [[ -d "$REPO_ROOT/setup/walter-host/services/$service_dir" ]]
  done < <(sed -nE 's/^[[:space:]]+service_dir: ([A-Za-z0-9._-]+)$/\1/p' "$PLACEMENT")
}
