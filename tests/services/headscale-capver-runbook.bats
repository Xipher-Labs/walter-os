#!/usr/bin/env bats
# Static coverage for Headscale/Tailscale capability-version drift guidance.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNBOOK="$REPO_ROOT/setup/walter-host/services/headscale/RUNBOOK.md"
  COMPOSE="$REPO_ROOT/setup/walter-host/services/headscale/compose.yml"
  OPERATOR_SETUP="$REPO_ROOT/docs/operational/operator-setup-runbook.md"
  ONBOARDING_CHECKLIST="$REPO_ROOT/docs/operational/onboarding-checklist.md"
  TROUBLESHOOTING="$REPO_ROOT/docs/operational/troubleshooting.md"
}

@test "headscale runbook documents capver registration failure" {
  [[ -f "$RUNBOOK" ]]
  [[ -f "$COMPOSE" ]]
  local pinned_headscale
  pinned_headscale="$(sed -nE 's/^[[:space:]]*image: headscale\/headscale:([^[:space:]]+).*/\1/p' "$COMPOSE")"
  [[ -n "$pinned_headscale" ]]

  grep -Fq "capability version must be set" "$RUNBOOK"
  grep -Fq "Tailscale 1.96.4" "$RUNBOOK"
  grep -Fq "Headscale $pinned_headscale" "$RUNBOOK"
  grep -Fq "HTTP 500" "$RUNBOOK"
}

@test "headscale runbook keeps break-glass on non-headscale path" {
  [[ -f "$RUNBOOK" ]]

  grep -Fq "Do not rely on Headscale as the primary break-glass path" "$RUNBOOK"
  grep -Fq "Walter-VM" "$RUNBOOK"
  grep -Fq "Hetzner Cloud Firewall SSH allow-list" "$RUNBOOK"
  grep -Fq "allow TCP/22 from your current public" "$RUNBOOK"
  grep -Fq "remove that allow-list" "$RUNBOOK"
}

@test "headscale compose points operators to version-drift guidance" {
  [[ -f "$COMPOSE" ]]

  grep -Fq "capability-version drift" "$COMPOSE"
  grep -Fq "RUNBOOK.md" "$COMPOSE"
}

@test "operator onboarding warns before headscale registration" {
  [[ -f "$OPERATOR_SETUP" ]]
  [[ -f "$ONBOARDING_CHECKLIST" ]]

  grep -Fq "capability version must be set" "$OPERATOR_SETUP"
  grep -Fq "Hetzner Cloud Firewall SSH allow-list" "$OPERATOR_SETUP"
  grep -Fq "capability version must be set" "$ONBOARDING_CHECKLIST"
  grep -Fq "Hetzner Cloud Firewall SSH allow-list" "$ONBOARDING_CHECKLIST"
}

@test "troubleshooting maps headscale HTTP 500 to capver drift" {
  [[ -f "$TROUBLESHOOTING" ]]

  grep -Fq "Headscale node enrollment returns HTTP 500" "$TROUBLESHOOTING"
  grep -Fq "capability version must be set" "$TROUBLESHOOTING"
  grep -Fq "setup/walter-host/services/headscale/RUNBOOK.md" "$TROUBLESHOOTING"
}
