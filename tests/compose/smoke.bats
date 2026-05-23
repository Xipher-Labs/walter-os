#!/usr/bin/env bats
# Smoke tests for the all-in-one compose.yml
# @slow — requires Docker daemon. Tagged for CI opt-in.
#
# Usage:
#   bats tests/compose/smoke.bats                      # skips Docker tests
#   WALTER_COMPOSE_TEST=1 bats tests/compose/smoke.bats # runs full smoke test
#
# In CI (GitHub Actions), set WALTER_COMPOSE_TEST=1 and ensure Docker is available.
# The test spins up a subset of services, curls health endpoints, and tears down.
#
# Covers: AC-7

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/compose.yml"

  # Minimal env for testing (no real credentials needed for health checks)
  export WALTER_DOMAIN=localhost
  export WALTER_ADMIN_EMAIL=admin@localhost
  export WALTER_INITIAL_USER=admin
  export WALTER_INITIAL_PASSWORD=changeme123
  export WALTER_TIMEZONE=UTC
  export POSTGRES_PASSWORD=testpgpass
  export PLANE_POSTGRES_PASSWORD=planepgpass
  export PLANE_RABBITMQ_PASSWORD=mqpass
  export PLANE_RABBITMQ_USER=plane
  export PLANE_RABBITMQ_VHOST=plane
  export PLANE_SECRET_KEY="testsecretkey""123456789012345678"
  export PLANE_AWS_ACCESS_KEY_ID=minioadmin
  export PLANE_AWS_SECRET_ACCESS_KEY=minioadmin
  export FORGEJO_DB_PASS=forgejopass
  export INFISICAL_ENCRYPTION_KEY=00000000000000000000000000000001
  export INFISICAL_AUTH_SECRET=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabb
  export INFISICAL_DB_PASS=infisicalpass
  export INFISICAL_REDIS_PASS=redispass
  export LITELLM_MASTER_KEY=sk-testmaster
  export LITELLM_SALT_KEY=saltkeytest
  export LITELLM_DB_PASS=litellmpass
  export LITELLM_UI_PASS=uipasstest
  export GF_ADMIN_PASSWORD=grafanapasstest
  export N8N_PG_PASS=n8npass
  export N8N_ENCRYPTION_KEY=00000000000000000000000000000002
  export WG_PASSWORD_HASH='$2b$12$testhashtesthashhhhhhhhhhh'

  # Uptime Kuma compose service has no external deps — good minimal smoke target
  COMPOSE_PROJECT="walter_smoke_$$"
}

teardown() {
  if [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] && command -v docker >/dev/null 2>&1; then
    # Always clean up, even on test failure
    docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
      down --volumes --remove-orphans 2>/dev/null || true
  fi
}

# --- Structure tests (no Docker required) ---

@test "smoke.bats can locate compose.yml" {
  [ -f "$COMPOSE_FILE" ]
}

@test "compose.yml YAML is syntactically valid (python check)" {
  # Use python if available — no docker needed
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # skip if PyYAML not installed
with open('$COMPOSE_FILE') as f:
    yaml.safe_load(f)
print('YAML valid')
sys.exit(0)
"
  [ "$?" -eq 0 ]
}

# --- Docker-required tests (tagged @slow, opt-in via WALTER_COMPOSE_TEST=1) ---

@test "docker compose config exits 0 [requires Docker]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"
  run docker compose -f "$COMPOSE_FILE" config --quiet
  [ "$status" -eq 0 ]
}

@test "uptime-kuma starts and responds to HTTP [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  # Start just uptime-kuma (no deps, lightweight)
  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d uptime-kuma 2>&1

  # Wait up to 60s for uptime-kuma to respond
  local i=0
  while ! curl -sf http://localhost:3001/ >/dev/null 2>&1; do
    sleep 2
    i=$((i + 2))
    [ $i -lt 60 ] || break
  done

  run curl -sf -o /dev/null -w "%{http_code}" http://localhost:3001/
  # Uptime Kuma returns 200 on initial setup page
  [[ "$output" == "200" ]]
}

@test "postgres starts and passes healthcheck [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d postgres 2>&1

  # Wait for postgres healthcheck to pass (up to 60s)
  local i=0
  local status_out=""
  while true; do
    status_out=$(docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
      ps postgres --format json 2>/dev/null || echo "{}")
    if echo "$status_out" | grep -qi "healthy"; then
      break
    fi
    sleep 3
    i=$((i + 3))
    [ $i -lt 60 ] || break
  done

  # Verify pg_isready
  run docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    exec -T postgres pg_isready -U walter
  [ "$status" -eq 0 ]
}

@test "n8n starts and responds to /healthz [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  # n8n requires postgres
  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d postgres n8n 2>&1

  # Wait up to 90s for n8n
  local i=0
  while ! curl -sf http://localhost:5678/healthz >/dev/null 2>&1; do
    sleep 3
    i=$((i + 3))
    [ $i -lt 90 ] || break
  done

  run curl -sf http://localhost:5678/healthz
  [[ "$output" == *"ok"* ]]
}

@test "grafana starts and reports healthy [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  # grafana requires prometheus + loki
  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d prometheus loki grafana 2>&1

  # Wait up to 120s for grafana
  local i=0
  while ! curl -sf http://localhost:3030/api/health >/dev/null 2>&1; do
    sleep 3
    i=$((i + 3))
    [ $i -lt 120 ] || break
  done

  run curl -sf http://localhost:3030/api/health
  [[ "$output" == *"ok"* ]]
}

@test "forgejo starts and serves web UI [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  # forgejo requires postgres
  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d postgres forgejo 2>&1

  # Wait up to 120s for forgejo
  local i=0
  while ! curl -sf http://localhost:3000/ >/dev/null 2>&1; do
    sleep 3
    i=$((i + 3))
    [ $i -lt 120 ] || break
  done

  run curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000/
  [[ "$output" == "200" ]]
}

@test "litellm starts and reports healthy [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  # litellm requires postgres
  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    up -d postgres litellm 2>&1

  # Wait up to 120s for litellm
  local i=0
  while ! curl -sf http://localhost:4000/health >/dev/null 2>&1; do
    sleep 3
    i=$((i + 3))
    [ $i -lt 120 ] || break
  done

  run curl -sf http://localhost:4000/health
  [ "$status" -eq 0 ]
}

@test "postiz pinned to v2.20.x (pre-Temporal, closes #172)" {
  # v2.21.x introduced a Temporal-backed visibility store that crashes
  # against Postgres with the search-attribute limit (#172). Until
  # upstream ships a fix that respects the Postgres limit, the compose
  # template MUST stay on v2.20.x. This regression guard catches a
  # well-intentioned but premature bump.
  #
  # Match both the root compose.yml + the standalone postiz compose.
  for compose in "$COMPOSE_FILE" "$REPO_ROOT/setup/walter-host/services/postiz/compose.yml"; do
    [[ -f "$compose" ]] || continue
    local image
    image=$(grep -E "^[[:space:]]+image:[[:space:]]+ghcr\.io/gitroomhq/postiz-app:" "$compose" \
      | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    [[ -n "$image" ]] || {
      echo "no postiz image found in $compose" >&2
      return 1
    }
    [[ "$image" =~ ^v2\.20\.[0-9]+$ ]] || {
      echo "postiz image in $compose is $image — must be v2.20.x until upstream Temporal fix (#172)" >&2
      return 1
    }
  done
}

@test "postiz smoke probe uses port 3000 (W2)" {
  # Postiz listens on 3000 inside the container; the historical bug was a
  # probe pointed at 5000. The meaningful contract is that compose.yml's
  # postiz healthcheck targets port 3000 — that's what we verify.
  #
  # Scan the WHOLE postiz block (until the next service definition). The
  # prior `grep -A5/-A30` windows could miss the healthcheck on Postiz
  # blocks with many env vars (the canonical block has 16+ env entries
  # before the healthcheck).
  #
  # Dropped the prior "no 5000 reference in this test file" assertion —
  # it was self-referential (the regex pattern + the test name both
  # contained the strings it was looking for), portable-grep-fragile
  # (worked silently on BSD grep, failed on GNU), and provided no real
  # value once the compose.yml port is verified directly.
  local postiz_block
  postiz_block=$(awk '/^  postiz:$/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:$/{flag=0} flag' \
    "$COMPOSE_FILE")
  echo "$postiz_block" | grep -q "healthcheck"
  echo "$postiz_block" | grep -q "127.0.0.1:3000"
  # Belt-and-braces: explicitly forbid port 5000 inside the postiz
  # block. Catches a regression where a future PR adds back a 5000
  # reference inside the healthcheck without going through this test.
  ! echo "$postiz_block" | grep -q "5000"
}

@test "devrel profile: postiz starts [requires Docker, slow]" {
  [ "${WALTER_COMPOSE_TEST:-0}" = "1" ] || skip "set WALTER_COMPOSE_TEST=1 to run"
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  cd "$REPO_ROOT"

  export POSTIZ_PG_PASS=postizpass
  export POSTIZ_JWT_SECRET=postizjwtsecret

  docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" \
    --profile devrel up -d postgres postiz postiz-redis 2>&1

  local i=0
  while ! curl -sf http://localhost:3000/ >/dev/null 2>&1; do
    sleep 3
    i=$((i + 3))
    [ $i -lt 120 ] || break
  done

  run curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000/
  # 200 or 302 (redirect to login) both acceptable
  [[ "$output" == "200" ]] || [[ "$output" == "302" ]]
}
