#!/usr/bin/env bats
# Static-analysis assertions for Walter audit-chain telemetry in Loki/Grafana.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  OBS_DIR="$REPO_ROOT/setup/walter-host/services/observability"
  COMPOSE="$OBS_DIR/compose.yml"
  AUDIT_COMPOSE="$OBS_DIR/compose.audit.yml"
  PROMTAIL="$OBS_DIR/promtail/promtail.yml"
  AUDIT_PROMTAIL="$OBS_DIR/promtail/promtail.audit.yml"
  DASHBOARD="$OBS_DIR/grafana/provisioning/dashboards/walter-audit.json"
  ENV_TEMPLATE="$OBS_DIR/.env.template"
  OBS_DOC="$REPO_ROOT/docs/operational/observability.md"
}

@test "default observability compose does not require an audit directory" {
  run grep -q "target: /var/log/walter-audit" "$COMPOSE"
  [ "$status" -ne 0 ]
  run grep -q "job_name: walter-audit-chain" "$PROMTAIL"
  [ "$status" -ne 0 ]
  run grep -q -- "-config.expand-env=true" "$COMPOSE"
  [ "$status" -ne 0 ]
}

@test "audit override mounts the Walter audit directory read-only" {
  grep -q "source: \${WALTER_AUDIT_DIR:-/home/walter/.config/walter-os/audit}" "$AUDIT_COMPOSE"
  grep -q "target: /var/log/walter-audit" "$AUDIT_COMPOSE"
  grep -q "read_only: true" "$AUDIT_COMPOSE"
  grep -q "create_host_path: false" "$AUDIT_COMPOSE"
  grep -q "promtail.audit.yml" "$AUDIT_COMPOSE"
  grep -q "WALTER_AUDIT_HOST: \${WALTER_AUDIT_HOST:-walter-os}" "$AUDIT_COMPOSE"
  grep -q -- "-config.expand-env=true" "$AUDIT_COMPOSE"
}

@test "promtail scrapes audit-chain jsonl files from the mounted path" {
  grep -q "job_name: walter-audit-chain" "$AUDIT_PROMTAIL"
  grep -q "audit_ts: ts" "$AUDIT_PROMTAIL"
  grep -q "source: audit_ts" "$AUDIT_PROMTAIL"
  grep -q "format: RFC3339Nano" "$AUDIT_PROMTAIL"
  grep -q "__path__: /var/log/walter-audit/chain-\\*.jsonl" "$AUDIT_PROMTAIL"
}

@test "promtail uses only low-cardinality audit-chain labels" {
  audit_job="$(sed -n '/job_name: walter-audit-chain/,/job_name: restic/p' "$AUDIT_PROMTAIL")"
  grep -q "job: walter-audit-chain" <<<"$audit_job"
  grep -q "app: walter-os" <<<"$audit_job"
  grep -q "kind: audit-chain" <<<"$audit_job"
  grep -q "host: \${WALTER_AUDIT_HOST:-walter-os}" <<<"$audit_job"
  run grep -E "chain_id:|event_id:|session_id:|agent:|model:" <<<"$audit_job"
  [ "$status" -ne 0 ]
}

@test "audit promtail config keeps shared jobs in parity with the base config" {
  command -v ruby >/dev/null 2>&1 || skip "ruby required"

  ruby -ryaml -e '
    base = YAML.load_file(ARGV[0]).fetch("scrape_configs")
    audit = YAML.load_file(ARGV[1]).fetch("scrape_configs")
    audit_shared = audit.reject { |job| job.fetch("job_name") == "walter-audit-chain" }
    abort "shared promtail jobs drift from base config" unless audit_shared == base
  ' "$PROMTAIL" "$AUDIT_PROMTAIL"
}

@test "audit promtail config limits env expansion to audit host label" {
  run bash -c 'grep -v "WALTER_AUDIT_HOST" "$1" | grep -v "^[[:space:]]*#" | grep -E '\''\$[{(]?[A-Za-z0-9_]'\''' _ "$AUDIT_PROMTAIL"

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

@test "Grafana audit dashboard queries Loki and limits JSON parsing" {
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

assert json_panels >= 5
PY
}

@test "Distinct Sessions Seen avoids query-time JSON extraction" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  python3 - "$DASHBOARD" <<'PY'
import json
import sys

dashboard = json.load(open(sys.argv[1], encoding="utf-8"))
panel = next(
    panel
    for panel in dashboard.get("panels", [])
    if panel.get("title") == "Distinct Sessions Seen"
)
expr = panel["targets"][0]["expr"]
assert '{app="walter-os", kind="audit-chain"}' in expr
assert '| json' not in expr
assert '|= "\\"session_id\\":"' in expr
assert '| pattern ' in expr
assert '<session_id>' in expr
assert 'session_id != ""' in expr
PY
}

@test "observability docs cover audit telemetry mount, labels, and dashboard" {
  grep -q "compose.audit.yml" "$OBS_DOC"
  grep -q "promtail.audit.yml" "$OBS_DOC"
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

@test "env template lists audit telemetry knobs" {
  grep -q "WALTER_AUDIT_DIR=/home/walter/.config/walter-os/audit" "$ENV_TEMPLATE"
  grep -q "WALTER_AUDIT_HOST=walter-os" "$ENV_TEMPLATE"
}
