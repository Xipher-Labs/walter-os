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

@test "ci workflow cancels stale runs for the same branch or PR" {
  [[ -f "$CI_WORKFLOW" ]]

  grep -Eq '^concurrency:[[:space:]]*$' "$CI_WORKFLOW"
  grep -Eq '^[[:space:]]+group:[[:space:]]+.*github\.workflow.*github\.event_name.*github\.event\.pull_request\.number.*\|\|.*github\.ref' "$CI_WORKFLOW"
  grep -Eq '^[[:space:]]+cancel-in-progress:[[:space:]]+true[[:space:]]*$' "$CI_WORKFLOW"
  grep -Fq 'the check rollup focused on the latest commit' "$CI_WORKFLOW"
}

@test "workflows cancel stale runs within each trigger and branch or PR" {
  local workflow
  for workflow in \
    ci \
    codeql \
    control-tower \
    gitleaks \
    osv-scanner \
    pr-review \
    pr-title-lint \
    readme-lint \
    semgrep
  do
    local path="$REPO_ROOT/.github/workflows/${workflow}.yml"
    [[ -f "$path" ]] || {
      echo "missing workflow: $path"
      return 1
    }

    grep -Eq '^concurrency:[[:space:]]*$' "$path" || {
      echo "missing concurrency block: $path"
      return 1
    }
    grep -Eq '^[[:space:]]+group:[[:space:]]+.*github\.workflow.*github\.event_name.*github\.event\.pull_request\.number.*\|\|.*github\.ref' "$path" || {
      echo "missing event-aware branch/PR concurrency group: $path"
      return 1
    }
    grep -Eq '^[[:space:]]+cancel-in-progress:[[:space:]]+true[[:space:]]*$' "$path" || {
      echo "missing cancel-in-progress: $path"
      return 1
    }
  done
}
