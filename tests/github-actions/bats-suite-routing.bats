#!/usr/bin/env bats
# Regression coverage for split Bats CI routing.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
}

@test "Cloudflare Bats tests route through compose-and-services, not hooks" {
  [[ -f "$CI_WORKFLOW" ]]

  local hooks_filter compose_filter
  hooks_filter="$(grep -E "set_bool hooks " "$CI_WORKFLOW")"
  compose_filter="$(grep -E "set_bool compose_and_services " "$CI_WORKFLOW")"

  [[ "$hooks_filter" != *"tests/cloudflare/"* ]]
  [[ "$compose_filter" == *"tests/cloudflare/"* ]]

  local hooks_matrix compose_matrix
  hooks_matrix="$(sed -n '/name: hooks/,/name: agents-and-skills/p' "$CI_WORKFLOW")"
  compose_matrix="$(sed -n '/name: compose-and-services/,/name: install-contracts/p' "$CI_WORKFLOW")"

  [[ "$hooks_matrix" != *"tests/cloudflare/"* ]]
  [[ "$compose_matrix" == *"tests/cloudflare/"* ]]
}
