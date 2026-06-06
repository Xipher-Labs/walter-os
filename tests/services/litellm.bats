#!/usr/bin/env bats
# Static assertions for the Walter-VM LiteLLM service compose contract.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
}

litellm_service_block() {
  awk '
    /^  litellm:/ { in_block=1; print; next }
    in_block && /^[^[:space:]][^:]*:/ { exit }
    in_block && /^  [^[:space:]][^:]*:/ { exit }
    in_block { print }
  ' "$COMPOSE_FILE"
}

@test "litellm compose exists" {
  [[ -f "$COMPOSE_FILE" ]]
}

@test "litellm has a functional liveliness healthcheck" {
  block="$(litellm_service_block)"

  grep -q "restart: unless-stopped" <<<"$block"
  grep -q "healthcheck:" <<<"$block"
  grep -q "CMD-SHELL" <<<"$block"
  grep -q "http://localhost:4000/health/liveliness" <<<"$block"
  grep -q "timeout=5" <<<"$block"
  grep -q ">/dev/null 2>&1" <<<"$block"
  grep -q "interval: 30s" <<<"$block"
  grep -q "timeout: 10s" <<<"$block"
  grep -q "retries: 5" <<<"$block"
  grep -q "start_period: 60s" <<<"$block"
}
