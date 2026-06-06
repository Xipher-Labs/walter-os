#!/usr/bin/env bats
# Regression coverage for Walter-VM out-of-band recovery assets.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/setup/walter-host/recovery/hetzner-break-glass-ssh.sh"
  TEMPLATE="$REPO_ROOT/setup/walter-host/recovery/hetzner-break-glass-ssh.rules.json.template"
  RUNBOOK="$REPO_ROOT/docs/runbooks/break-glass-recovery.md"
  HOST_README="$REPO_ROOT/setup/walter-host/README.md"
}

@test "Hetzner break-glass SSH helper exists and defaults to dry-run" {
  [[ -x "$SCRIPT" ]]

  run env WALTER_BREAK_GLASS_DESCRIPTION=breakglass "$SCRIPT" --server walter-vm --cidr 203.0.113.10/32
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" == *"hcloud firewall create"* ]]
  [[ "$output" == *"hcloud firewall add-rule"* ]]
  [[ "$output" == *"hcloud firewall add-rule walter-vm-break-glass-ssh --direction in --protocol tcp --port 22 --source-ips 203.0.113.10/32 --description breakglass"* ]]
  [[ "$output" == *"hcloud firewall apply-to-resource"* ]]
  [[ "$output" == *"hcloud firewall apply-to-resource walter-vm-break-glass-ssh --type server --server walter-vm"* ]]
}

@test "Hetzner break-glass SSH helper fails closed without server or CIDR" {
  run "$SCRIPT" --cidr 203.0.113.10/32
  [ "$status" -ne 0 ]
  [[ "$output" == *"--server"* ]]

  run "$SCRIPT" --server walter-vm
  [ "$status" -ne 0 ]
  [[ "$output" == *"--cidr"* ]]
}

@test "Hetzner break-glass SSH helper can plan teardown without CIDR" {
  run "$SCRIPT" --server walter-vm --remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" == *"hcloud firewall remove-from-resource"* ]]
  [[ "$output" == *"hcloud firewall remove-from-resource walter-vm-break-glass-ssh --type server --server walter-vm"* ]]
}

@test "Hetzner break-glass SSH helper rejects apply plus remove" {
  run "$SCRIPT" --server walter-vm --cidr 203.0.113.10/32 --apply --remove
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutually exclusive"* ]]

  run "$SCRIPT" --server walter-vm --cidr 203.0.113.10/32 --remove --apply
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "Hetzner firewall rule template is SSH-only and operator-scoped" {
  [[ -f "$TEMPLATE" ]]

  grep -q '"direction": "in"' "$TEMPLATE"
  grep -q '"protocol": "tcp"' "$TEMPLATE"
  grep -q '"port": "22"' "$TEMPLATE"
  grep -q '"source_ips"' "$TEMPLATE"
  grep -q '<OPERATOR_PUBLIC_IP_OR_CIDR>' "$TEMPLATE"
  ! grep -q '0.0.0.0/0' "$TEMPLATE"
}

@test "break-glass runbook documents non-tunnel recovery and teardown" {
  [[ -f "$RUNBOOK" ]]

  grep -q "Cloudflare Tunnel" "$RUNBOOK"
  grep -q "not depend on cloudflared" "$RUNBOOK"
  grep -q "WALTER_BREAK_GLASS_SSH_CIDR" "$RUNBOOK"
  grep -q "hetzner-break-glass-ssh.sh" "$RUNBOOK"
  grep -q -- "--apply" "$RUNBOOK"
  grep -q "remove-from-resource" "$RUNBOOK"
  grep -q "Headscale" "$RUNBOOK"
  grep -q "operator-specific" "$RUNBOOK"
}

@test "walter-host setup README points operators to break-glass before SSH lockdown" {
  [[ -f "$HOST_README" ]]

  grep -q "break-glass" "$HOST_README"
  grep -q "docs/runbooks/break-glass-recovery.md" "$HOST_README"
  grep -q "lock-ssh.sh" "$HOST_README"
}
