#!/usr/bin/env bats
# tests/walter/review-policy.bats
#
# Lightweight contract test for the operator-facing review-policy example.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  POLICY="$REPO_ROOT/contexts/_examples/review-policy.yml.example"
}

@test "review-policy example declares required multi-model review rounds" {
  [ -f "$POLICY" ]
  grep -q "github-copilot" "$POLICY"
  grep -q "model_domain: backend_review" "$POLICY"
  grep -q "model_domain: frontend" "$POLICY"
  grep -q "model_domain: phi" "$POLICY"
  grep -q "external_apis_allowed: false" "$POLICY"
}
