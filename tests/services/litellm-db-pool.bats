#!/usr/bin/env bats
# Static assertions for the LiteLLM database pool guardrail.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
}

@test "litellm DATABASE_URL bounds client pool fanout" {
  database_url_line="$(grep -E '^[[:space:]]+DATABASE_URL:' "$COMPOSE_FILE")"

  [[ "$database_url_line" == *"postgresql://litellm:"* ]]
  [[ "$database_url_line" == *"?connection_limit=10"* ]]
  [[ "$database_url_line" == *"&pool_timeout=10"* ]]
  [[ "$database_url_line" == *"&connect_timeout=10"* ]]
}
