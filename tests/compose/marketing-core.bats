#!/usr/bin/env bats
# tests/compose/marketing-core.bats
# Bats test suite for marketing core services (PR #50)
# Prereqs: bats-core; docker + docker compose only needed when WALTER_COMPOSE_TEST=1
# Run (static checks only):  bats tests/compose/marketing-core.bats
# Run (full with compose):   WALTER_COMPOSE_TEST=1 bats tests/compose/marketing-core.bats

setup() {
  # Work from repo root
  cd "$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

# --- compose parse (docker-gated) ----------------------------------------

@test "compose.yml parses without errors" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --quiet
  [ "$status" -eq 0 ]
}

# --- PostHog services in default profile (docker-gated) ------------------

@test "posthog service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog$"
}

@test "posthog-worker service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog-worker$"
}

@test "posthog-plugin-server service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog-plugin-server$"
}

@test "posthog-asyncmigrationscheck service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog-asyncmigrationscheck$"
}

@test "posthog-clickhouse service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog-clickhouse$"
}

@test "posthog-redis service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^posthog-redis$"
}

# --- Postiz and Metabase now in default profile (docker-gated) -----------

@test "postiz service present in default profile (no --profile flag)" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^postiz$"
}

@test "postiz-redis service present in default profile (no --profile flag)" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^postiz-redis$"
}

@test "metabase service present in default profile (no --profile flag)" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^metabase$"
}

# --- Control Tower (docker-gated) ----------------------------------------

@test "control-tower service present in default profile" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config --services
  echo "$output" | grep -q "^control-tower$"
}

@test "control-tower build stanza present in compose.yml" {
  [[ "${WALTER_COMPOSE_TEST:-0}" == "1" ]] || skip "set WALTER_COMPOSE_TEST=1 to run compose tests"
  run docker compose config
  echo "$output" | grep -q "build"
}

# --- Image pin check (static) --------------------------------------------

@test "no :latest image tags in compose.yml (regression guard)" {
  # Grep only image: lines; exclude locally-built walter-control-tower which has no semver.
  # The npm command "migration:latest" in infisical's entrypoint is not an image tag.
  run grep -E '^[[:space:]]+image:.*:latest' compose.yml
  # Filter out the local control-tower image (no upstream registry, tag controlled by operator build)
  filtered=$(echo "$output" | grep -v 'walter-control-tower:latest' || true)
  [ -z "$filtered" ]
}

# --- SERVICES-INVENTORY.md hostnames (static) ----------------------------

@test "posthog hostname in SERVICES-INVENTORY.md" {
  grep -q 'posthog\.\${WALTER_DOMAIN}' setup/SERVICES-INVENTORY.md
}

@test "metabase hostname in SERVICES-INVENTORY.md" {
  grep -q 'metabase\.\${WALTER_DOMAIN}' setup/SERVICES-INVENTORY.md
}

@test "postiz hostname in SERVICES-INVENTORY.md" {
  grep -q 'postiz\.\${WALTER_DOMAIN}' setup/SERVICES-INVENTORY.md
}

@test "control-tower hostname in SERVICES-INVENTORY.md" {
  grep -q 'tower\.\${WALTER_DOMAIN}' setup/SERVICES-INVENTORY.md
}

# --- env.all.template variables (static) ---------------------------------

@test "POSTHOG_SECRET in env.all.template" {
  grep -q 'POSTHOG_SECRET' templates/env.all.template
}

@test "POSTHOG_DB_PASS in env.all.template" {
  grep -q 'POSTHOG_DB_PASS' templates/env.all.template
}

@test "CLICKHOUSE_PASSWORD in env.all.template" {
  grep -q 'CLICKHOUSE_PASSWORD' templates/env.all.template
}

@test "CONTROL_TOWER_ADMIN_TOKEN in env.all.template" {
  grep -q 'CONTROL_TOWER_ADMIN_TOKEN' templates/env.all.template
}

@test "LITELLM_API_KEY in env.all.template" {
  grep -q 'LITELLM_API_KEY' templates/env.all.template
}

@test "GRAFANA_SA_TOKEN in env.all.template" {
  grep -q 'GRAFANA_SA_TOKEN' templates/env.all.template
}

# --- Caddyfile.template entries (static) ---------------------------------

@test "posthog hostname in Caddyfile.template" {
  grep -q 'posthog\.\${WALTER_DOMAIN}' setup/caddy/Caddyfile.template
}

@test "tower hostname in Caddyfile.template" {
  grep -q 'tower\.\${WALTER_DOMAIN}' setup/caddy/Caddyfile.template
}

@test "Caddy control-tower vhost has XFF header stripping" {
  grep -q 'header_up -X-Forwarded-For' setup/caddy/Caddyfile.template
}

@test "Postiz secrets use :?required in compose.yml (no weak defaults)" {
  run grep -E 'POSTIZ_PG_PASS:-|POSTIZ_JWT_SECRET:-' compose.yml
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

# --- kuma-bulk-monitors.py entries (static) ------------------------------

@test "PostHog monitor in kuma-bulk-monitors.py" {
  grep -q 'PostHog' scripts/kuma-bulk-monitors.py
}

@test "Postiz monitor in kuma-bulk-monitors.py" {
  grep -q 'Postiz' scripts/kuma-bulk-monitors.py
}

@test "Control Tower monitor in kuma-bulk-monitors.py" {
  grep -q 'Control Tower' scripts/kuma-bulk-monitors.py
}
