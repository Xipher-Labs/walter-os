#!/usr/bin/env bats
# Static assertions for cloudflared HA + metrics + /ready restart guard.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALL_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/03-install-cloudflared.sh"
}

@test "cloudflared installer exposes HA metrics readiness" {
  grep -q 'CLOUDFLARED_METRICS_ADDR="${CLOUDFLARED_METRICS_ADDR:-127.0.0.1:49312}"' "$INSTALL_SCRIPT"
  grep -q -- '--metrics "${CLOUDFLARED_METRICS_ADDR}"' "$INSTALL_SCRIPT"
  grep -q -- '--ha-connections 4' "$INSTALL_SCRIPT"
  grep -q 'Restart=always' "$INSTALL_SCRIPT"
  grep -q 'RestartSec=10s' "$INSTALL_SCRIPT"
}

@test "cloudflared installer wires metrics into alerting env" {
  grep -q 'CLOUDFLARED_METRICS="${CLOUDFLARED_METRICS_ADDR}"' "$INSTALL_SCRIPT"
  grep -q '/etc/walter-vm/alerting.env' "$INSTALL_SCRIPT"
  grep -q 'chown root:root /etc/walter-vm/alerting.env' "$INSTALL_SCRIPT"
  grep -q 'chmod 0600 /etc/walter-vm/alerting.env' "$INSTALL_SCRIPT"
}

@test "cloudflared installer adds status-code based /ready guard" {
  grep -q '/usr/local/sbin/walter-cloudflared-ready-check' "$INSTALL_SCRIPT"
  grep -q 'systemctl is-active --quiet cloudflared' "$INSTALL_SCRIPT"
  grep -Fq 'if ready_code=\$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://\${CLOUDFLARED_METRICS_ADDR}/ready" 2>/dev/null); then' "$INSTALL_SCRIPT"
  grep -Fq 'ready_code=000' "$INSTALL_SCRIPT"
  run grep -F '|| echo 000' "$INSTALL_SCRIPT"
  [ "$status" -ne 0 ]
  grep -Fq '200) exit 0' "$INSTALL_SCRIPT"
  grep -Fq '000)' "$INSTALL_SCRIPT"
  grep -Fq 'systemctl restart cloudflared' "$INSTALL_SCRIPT"
  grep -q '/etc/systemd/system/walter-cloudflared-ready-check.service' "$INSTALL_SCRIPT"
  grep -q '/etc/systemd/system/walter-cloudflared-ready-check.timer' "$INSTALL_SCRIPT"
  grep -q 'OnUnitActiveSec=60s' "$INSTALL_SCRIPT"
  grep -q 'systemctl enable --now walter-cloudflared-ready-check.timer' "$INSTALL_SCRIPT"
  run grep -q 'readyConnections' "$INSTALL_SCRIPT"
  [ "$status" -ne 0 ]
  run grep -q 'ready_payload' "$INSTALL_SCRIPT"
  [ "$status" -ne 0 ]
}

@test "cloudflared installer reapplies rewritten systemd unit" {
  grep -q 'cloudflared_was_active=0' "$INSTALL_SCRIPT"
  grep -q 'cloudflared_was_active=1' "$INSTALL_SCRIPT"
  grep -q 'systemctl enable cloudflared' "$INSTALL_SCRIPT"
  grep -q 'systemctl restart cloudflared' "$INSTALL_SCRIPT"
  grep -q 'systemctl start cloudflared' "$INSTALL_SCRIPT"
}
