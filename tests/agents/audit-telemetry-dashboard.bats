#!/usr/bin/env bats
# Static-analysis assertions for Walter audit-chain telemetry in Loki/Grafana.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  OBS_DIR="$REPO_ROOT/setup/walter-host/services/observability"
  COMPOSE="$OBS_DIR/compose.yml"
  PROMTAIL="$OBS_DIR/promtail/promtail.yml"
  DASHBOARD="$OBS_DIR/grafana/provisioning/dashboards/walter-audit.json"
  OBS_DOC="$REPO_ROOT/docs/operational/observability.md"
}

@test "promtail mounts the Walter audit directory read-only" {
  grep -q "source: \${WALTER_AUDIT_DIR:-/home/walter/.config/walter-os/audit}" "$COMPOSE"
  grep -q "target: /var/log/walter-audit" "$COMPOSE"
  grep -q "read_only: true" "$COMPOSE"
  grep -q "create_host_path: false" "$COMPOSE"
  grep -q "WALTER_AUDIT_HOST: \${WALTER_AUDIT_HOST:-walter-vm}" "$COMPOSE"
  grep -q -- "-config.expand-env=true" "$COMPOSE"
}

@test "promtail scrapes audit-chain jsonl files from the mounted path" {
  grep -q "job_name: walter-audit-chain" "$PROMTAIL"
  grep -q "audit_ts: ts" "$PROMTAIL"
  grep -q "source: audit_ts" "$PROMTAIL"
  grep -q "format: RFC3339" "$PROMTAIL"
  grep -q "__path__: /var/log/walter-audit/chain-\\*.jsonl" "$PROMTAIL"
}

@test "promtail uses only low-cardinality audit-chain labels" {
  grep -q "app: walter-os" "$PROMTAIL"
  grep -q "kind: audit-chain" "$PROMTAIL"
  grep -q 'host: ${WALTER_AUDIT_HOST}' "$PROMTAIL"
  run grep -E "chain_id:|event_id:|session_id:|agent:|model:" "$PROMTAIL"
  [ "$status" -ne 0 ]
}

@test "Grafana audit dashboard has stable UID and at least six panels" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  python3 - "$DASHBOARD" <<'PY'
import json
import sys

dashboard = json.load(open(sys.argv[1], encoding="utf-8"))
assert dashboard["uid"] == "walter-audit"
assert len(dashboard.get("panels", [])) >= 6
PY
}

@test "Grafana audit dashboard queries Loki and parses JSON at query time" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  python3 - "$DASHBOARD" <<'PY'
import json
import sys

dashboard = json.load(open(sys.argv[1], encoding="utf-8"))
panels = dashboard.get("panels", [])
json_panels = 0
for panel in panels:
    targets = panel.get("targets", [])
    if not targets:
        continue
    panel_uses_json = False
    for target in targets:
        datasource = target.get("datasource") or panel.get("datasource") or {}
        assert datasource.get("uid") == "loki"
        expr = target.get("expr", "")
        assert '{app="walter-os", kind="audit-chain"}' in expr
        if "| json" in expr:
            panel_uses_json = True
    if panel_uses_json:
        json_panels += 1

assert json_panels >= 6
PY
}

@test "observability docs cover audit telemetry mount, labels, and dashboard" {
  grep -q "/home/walter/.config/walter-os/audit" "$OBS_DOC"
  grep -q "WALTER_AUDIT_DIR" "$OBS_DOC"
  grep -q "create_host_path: false" "$OBS_DOC"
  grep -q "timestamp" "$OBS_DOC"
  grep -q "/var/log/walter-audit" "$OBS_DOC"
  grep -q "app=walter-os" "$OBS_DOC"
  grep -q "kind=audit-chain" "$OBS_DOC"
  grep -q "WALTER_AUDIT_HOST" "$OBS_DOC"
  grep -q "walter-audit" "$OBS_DOC"
}
