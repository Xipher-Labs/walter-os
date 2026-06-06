#!/usr/bin/env bats
# Static coverage for optional PgBouncer in front of LiteLLM Postgres.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
  BRIDGE_DOC="$REPO_ROOT/docs/operational/walter-bridge.md"
}

@test "litellm database url remains direct by default but can be overridden" {
  [[ -f "$COMPOSE_FILE" ]]

  grep -q 'LITELLM_DATABASE_URL:-postgresql://litellm' "$COMPOSE_FILE"
  grep -q '@litellm-db:5432/litellm' "$COMPOSE_FILE"
  grep -q 'connection_limit=10' "$COMPOSE_FILE"
  grep -q 'pool_timeout=10' "$COMPOSE_FILE"
  grep -q 'connect_timeout=10' "$COMPOSE_FILE"
}

@test "optional pgbouncer service runs in transaction mode" {
  COMPOSE_FILE="$COMPOSE_FILE" ruby <<'RUBY'
require "yaml"
compose = YAML.load_file(ENV.fetch("COMPOSE_FILE"))
service = compose.fetch("services").fetch("litellm-pgbouncer")
env = service.fetch("environment")

abort "PgBouncer must be opt-in" unless service.fetch("profiles") == ["pgbouncer"]
abort "PgBouncer image must be pinned" unless service.fetch("image") == "edoburu/pgbouncer:v1.24.1-p1"
abort "PgBouncer must wait for litellm-db" unless service.fetch("depends_on").fetch("litellm-db").fetch("condition") == "service_healthy"
abort "PgBouncer must use transaction pooling" unless env.fetch("POOL_MODE") == "transaction"
abort "PgBouncer must target litellm-db" unless env.fetch("DB_HOST") == "litellm-db"
abort "PgBouncer must expose litellm database" unless env.fetch("DB_NAME") == "litellm"
RUBY
}

@test "pgbouncer caps real backend connections independently of workers" {
  COMPOSE_FILE="$COMPOSE_FILE" ruby <<'RUBY'
require "yaml"
compose = YAML.load_file(ENV.fetch("COMPOSE_FILE"))
env = compose.fetch("services").fetch("litellm-pgbouncer").fetch("environment")

abort "missing DEFAULT_POOL_SIZE" unless env.fetch("DEFAULT_POOL_SIZE").include?("LITELLM_PGBOUNCER_POOL_SIZE:-20")
abort "missing RESERVE_POOL_SIZE" unless env.fetch("RESERVE_POOL_SIZE").include?("LITELLM_PGBOUNCER_RESERVE_POOL_SIZE:-5")
abort "missing MAX_DB_CONNECTIONS" unless env.fetch("MAX_DB_CONNECTIONS").include?("LITELLM_PGBOUNCER_MAX_DB_CONNECTIONS:-25")
abort "missing MAX_CLIENT_CONN" unless env.fetch("MAX_CLIENT_CONN").include?("LITELLM_PGBOUNCER_MAX_CLIENT_CONN:-200")
RUBY
}

@test "Walter Bridge docs explain how to enable optional pgbouncer" {
  [[ -f "$BRIDGE_DOC" ]]

  grep -q "LITELLM_DATABASE_URL" "$BRIDGE_DOC"
  grep -q "litellm-pgbouncer" "$BRIDGE_DOC"
  grep -q "transaction" "$BRIDGE_DOC"
}
