#!/usr/bin/env bats
# Caddy config template tests
# Covers: AC-1, AC-8 (Task 5)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEMPLATE="$REPO_ROOT/setup/caddy/Caddyfile.template"
  CADDYFILE="$REPO_ROOT/setup/caddy/Caddyfile"
}

@test "setup/caddy/Caddyfile.template exists" {
  [ -f "$TEMPLATE" ]
}

@test "setup/caddy/Caddyfile exists (placeholder)" {
  [ -f "$CADDYFILE" ]
}

@test "Caddyfile.template uses WALTER_DOMAIN for all service routes" {
  # AC-8: no literal TLD-qualified domain in URL position
  ! grep -qP "\.(xyz|com|io|dev|net)/" "$TEMPLATE"
  # And WALTER_DOMAIN variable appears in route definitions (at least 5 occurrences)
  grep -c '\${WALTER_DOMAIN}' "$TEMPLATE" | awk '{exit ($1 < 5)}'
}

@test "Caddyfile.template contains no xipherlabs domain" {
  # AC-8
  ! grep -q "xipherlabs" "$TEMPLATE"
}

@test "scripts/ directory contains no hardcoded xipherlabs domains" {
  # AC-8 extended: scripts must use WALTER_DOMAIN, not operator-specific domain
  # Exclude __pycache__ (compiled .pyc may contain stale strings from old source)
  ! grep -rq --include="*.py" --include="*.sh" "xipherlabs" "$REPO_ROOT/scripts/"
}

@test "kuma-bulk-monitors.py uses WALTER_DOMAIN env var" {
  # B2: no hardcoded domain — must read from os.environ
  local kuma="$REPO_ROOT/scripts/kuma-bulk-monitors.py"
  [ -f "$kuma" ]
  grep -q "WALTER_DOMAIN" "$kuma"
}

@test "kuma-bulk-monitors.py exits non-zero when WALTER_DOMAIN not set" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  # Run without WALTER_DOMAIN — must fail fast with clear error
  run env -i PATH="$PATH" python3 "$REPO_ROOT/scripts/kuma-bulk-monitors.py"
  [ "$status" -ne 0 ]
}

@test "Caddyfile.template references WALTER_ADMIN_EMAIL for ACME" {
  grep -q "WALTER_ADMIN_EMAIL" "$TEMPLATE"
}

@test "Caddyfile.template has plane route" {
  grep -q "plane\." "$TEMPLATE"
}

@test "Caddyfile.template has forgejo/git route" {
  grep -q "git\." "$TEMPLATE"
}

@test "Caddyfile.template has grafana route" {
  grep -q "grafana\." "$TEMPLATE"
}

@test "Caddyfile.template has n8n route" {
  grep -q "n8n\." "$TEMPLATE"
}

@test "Caddyfile.template can be rendered with envsubst" {
  command -v envsubst >/dev/null 2>&1 || skip "envsubst not available"
  rendered=$(WALTER_DOMAIN=test.example.com WALTER_ADMIN_EMAIL=admin@test.example.com \
             envsubst < "$TEMPLATE")
  echo "$rendered" | grep -q "plane.test.example.com"
  ! echo "$rendered" | grep -q "\${WALTER_DOMAIN}"
}

@test "setup/litellm/config.yaml exists" {
  [ -f "$REPO_ROOT/setup/litellm/config.yaml" ]
}

@test "setup/prometheus/prometheus.yml exists" {
  [ -f "$REPO_ROOT/setup/prometheus/prometheus.yml" ]
}

@test "setup/loki/loki.yml exists" {
  [ -f "$REPO_ROOT/setup/loki/loki.yml" ]
}

@test "setup/promtail/promtail.yml exists" {
  [ -f "$REPO_ROOT/setup/promtail/promtail.yml" ]
}

@test "setup/grafana/provisioning/datasources/datasources.yaml exists" {
  [ -f "$REPO_ROOT/setup/grafana/provisioning/datasources/datasources.yaml" ]
}
