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
  python3 - "$COMPOSE_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

service = compose["services"]["litellm-pgbouncer"]
env = service["environment"]

assert service["profiles"] == ["pgbouncer"], "PgBouncer must be opt-in"
assert service["image"] == "edoburu/pgbouncer:v1.24.1-p1", "PgBouncer image must be pinned"
assert service["depends_on"]["litellm-db"]["condition"] == "service_healthy", "PgBouncer must wait for litellm-db"
assert env["POOL_MODE"] == "transaction", "PgBouncer must use transaction pooling"
assert env["DB_HOST"] == "litellm-db", "PgBouncer must target litellm-db"
assert env["DB_NAME"] == "litellm", "PgBouncer must expose litellm database"
PY
}

@test "pgbouncer caps real backend connections independently of workers" {
  python3 - "$COMPOSE_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

env = compose["services"]["litellm-pgbouncer"]["environment"]

assert "LITELLM_PGBOUNCER_POOL_SIZE:-20" in env["DEFAULT_POOL_SIZE"], "missing DEFAULT_POOL_SIZE"
assert "LITELLM_PGBOUNCER_RESERVE_POOL_SIZE:-5" in env["RESERVE_POOL_SIZE"], "missing RESERVE_POOL_SIZE"
assert "LITELLM_PGBOUNCER_MAX_DB_CONNECTIONS:-25" in env["MAX_DB_CONNECTIONS"], "missing MAX_DB_CONNECTIONS"
assert "LITELLM_PGBOUNCER_MAX_CLIENT_CONN:-200" in env["MAX_CLIENT_CONN"], "missing MAX_CLIENT_CONN"
PY
}

@test "Walter Bridge docs explain how to enable optional pgbouncer" {
  [[ -f "$BRIDGE_DOC" ]]

  grep -q "LITELLM_DATABASE_URL" "$BRIDGE_DOC"
  grep -q "litellm-pgbouncer" "$BRIDGE_DOC"
  grep -q "transaction" "$BRIDGE_DOC"
}
