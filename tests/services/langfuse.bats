#!/usr/bin/env bats
# tests/services/langfuse.bats
# Static-analysis assertions for the optional Langfuse profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LANGFUSE_DIR="$REPO_ROOT/setup/walter-host/services/langfuse"
  LANGFUSE_COMPOSE="$LANGFUSE_DIR/compose.yml"
  LANGFUSE_ENV_TEMPLATE="$LANGFUSE_DIR/.env.template"
  LANGFUSE_README="$LANGFUSE_DIR/README.md"
  LANGFUSE_DOC="$REPO_ROOT/docs/operational/langfuse.md"
}

service_stanza() {
  local service="$1"
  awk -v service="$service" '
    $0 ~ "^  " service ":" { in_service=1; print; next }
    in_service && /^[^[:space:]]/ { exit }
    in_service && /^  [A-Za-z0-9_-]+:/ { exit }
    in_service { print }
  ' "$LANGFUSE_COMPOSE"
}

@test "langfuse service files exist" {
  [[ -f "$LANGFUSE_COMPOSE" ]]
  [[ -f "$LANGFUSE_ENV_TEMPLATE" ]]
  [[ -f "$LANGFUSE_README" ]]
}

@test "every langfuse service is gated by langfuse profile" {
  for service in langfuse-web langfuse-worker langfuse-postgres langfuse-clickhouse langfuse-redis langfuse-minio; do
    grep -qE "^  ${service}:" "$LANGFUSE_COMPOSE"
    service_stanza "$service" | grep -q "profiles: \\[langfuse\\]"
  done
}

@test "langfuse app images are pinned exactly" {
  grep -q "docker.io/langfuse/langfuse:3.176.0" "$LANGFUSE_COMPOSE"
  grep -q "docker.io/langfuse/langfuse-worker:3.176.0" "$LANGFUSE_COMPOSE"
}

@test "langfuse app images do not use latest or floating major tags" {
  run grep -E "docker.io/langfuse/langfuse(-worker)?:(latest|[0-9]+)([^0-9.]|$)" "$LANGFUSE_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "required secrets fail closed in compose" {
  for var in NEXTAUTH_SECRET SALT ENCRYPTION_KEY LANGFUSE_DB_PASSWORD CLICKHOUSE_PASSWORD REDIS_AUTH MINIO_ROOT_USER MINIO_ROOT_PASSWORD; do
    grep -qE "\\$\\{${var}:\\?required" "$LANGFUSE_COMPOSE"
  done
}

@test "env template documents required variables without real secrets" {
  for var in NEXTAUTH_SECRET SALT ENCRYPTION_KEY LANGFUSE_DB_PASSWORD CLICKHOUSE_PASSWORD REDIS_AUTH MINIO_ROOT_USER MINIO_ROOT_PASSWORD; do
    grep -q "^${var}=$" "$LANGFUSE_ENV_TEMPLATE"
  done

  run grep -Ei "=(changeme|password123|mysecret|mysalt|miniosecret|clickhouse|postgres://)" "$LANGFUSE_ENV_TEMPLATE"
  [ "$status" -ne 0 ]
}

@test "compose publishes only Langfuse UI on loopback" {
  grep -Fq '127.0.0.1:${LANGFUSE_HOST_PORT:-3011}:3000' "$LANGFUSE_COMPOSE"
  port_lines="$(grep -E '^[[:space:]]+-[[:space:]]*"?[^"]*:[0-9]+(:[0-9]+)?' "$LANGFUSE_COMPOSE" || true)"
  [ "$(printf '%s\n' "$port_lines" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ]
  printf '%s\n' "$port_lines" | grep -Fq '127.0.0.1:${LANGFUSE_HOST_PORT:-3011}:3000'
}

@test "compose defines named volumes for service-local dependencies" {
  for volume in langfuse_postgres_data langfuse_clickhouse_data langfuse_clickhouse_logs langfuse_redis_data langfuse_minio_data; do
    grep -qE "^  ${volume}:" "$LANGFUSE_COMPOSE"
  done
}

@test "docs mention caddy route and operational burden" {
  grep -q 'https://langfuse.${WALTER_DOMAIN}' "$LANGFUSE_README"
  grep -qi "trace" "$LANGFUSE_README"
  grep -qi "eval" "$LANGFUSE_README"
  grep -qi "backup" "$LANGFUSE_README"
  grep -qi "optional" "$LANGFUSE_README"
}

@test "operational doc covers traces, evals, backups, and optionality" {
  [[ -f "$LANGFUSE_DOC" ]]
  grep -qi "trace" "$LANGFUSE_DOC"
  grep -qi "eval" "$LANGFUSE_DOC"
  grep -qi "backup" "$LANGFUSE_DOC"
  grep -qi "optional" "$LANGFUSE_DOC"
}
