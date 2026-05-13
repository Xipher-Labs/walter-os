#!/usr/bin/env bats
# tests/services/openclaw.bats
# Static-analysis assertions for the OpenClaw service definition.
# No live Docker required — validates config files and spec documents.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  OPENCLAW_COMPOSE="$REPO_ROOT/setup/walter-host/services/openclaw/compose.yml"
  OPENCLAW_SPEC="$REPO_ROOT/docs/specs/openclaw.md"
  OPENCLAW_PHASE2_SPEC="$REPO_ROOT/docs/specs/openclaw-phase2-matrix-bridges.md"
  ROOT_COMPOSE="$REPO_ROOT/compose.yml"
}

# --- Spec doc existence ---
@test "docs/specs/openclaw.md exists" {
  [[ -f "$OPENCLAW_SPEC" ]]
}
@test "docs/specs/openclaw-phase2-matrix-bridges.md exists" {
  [[ -f "$OPENCLAW_PHASE2_SPEC" ]]
}

# --- Spec content: openclaw.md ---
@test "openclaw.md has trust model section" {
  grep -qi "trust model\|trust tier\|trust level" "$OPENCLAW_SPEC"
}
@test "openclaw.md has capability matrix section" {
  grep -qi "capability\|capabilities" "$OPENCLAW_SPEC"
}
@test "openclaw.md has threat model section" {
  grep -qi "threat model\|threats" "$OPENCLAW_SPEC"
}
@test "openclaw.md has no hardcoded operator usernames" {
  run grep -E "\bnico\b" "$OPENCLAW_SPEC"
  [ "$status" -ne 0 ]
}
@test "openclaw.md references LiteLLM as the model gateway" {
  grep -q -i "litellm" "$OPENCLAW_SPEC"
}

# --- Spec content: openclaw-phase2-matrix-bridges.md ---
@test "openclaw-phase2 spec mentions Matrix bridges" {
  grep -qi "matrix\|bridge\|synapse" "$OPENCLAW_PHASE2_SPEC"
}
@test "openclaw-phase2 spec has no hardcoded operator usernames" {
  run grep -E "\bnico\b" "$OPENCLAW_PHASE2_SPEC"
  [ "$status" -ne 0 ]
}

# --- Service compose config ---
@test "openclaw compose uses OPENCLAW_GATEWAY_TOKEN with :? fail-loud form" {
  # Match actual compose syntax: OPENCLAW_GATEWAY_TOKEN: "${OPENCLAW_GATEWAY_TOKEN:?required - ...}"
  # The :? appears inside the ${...} expression, not after the YAML key.
  grep -qE '\$\{OPENCLAW_GATEWAY_TOKEN:\?' "$OPENCLAW_COMPOSE"
}
@test "openclaw compose OPENAI_API_KEY sourced from LITELLM_OPENCLAW_KEY (no hardcode)" {
  grep -q "OPENAI_API_KEY.*LITELLM_OPENCLAW_KEY" "$OPENCLAW_COMPOSE"
}
@test "openclaw compose DM policy is pairing (not auto-reply to unknown senders)" {
  grep -q "OPENCLAW_DM_POLICY.*pairing" "$OPENCLAW_COMPOSE"
}
@test "openclaw compose healthcheck uses /healthz endpoint" {
  grep -q "healthz" "$OPENCLAW_COMPOSE"
}
@test "openclaw compose no @latest npm install (version pinned)" {
  run grep -q "@latest" "$OPENCLAW_COMPOSE"
  [ "$status" -ne 0 ]
}

# --- Root compose assertions ---
@test "root compose OPENCLAW_GATEWAY_TOKEN is parameterized (no hardcoded value)" {
  # Per Codex R2 P1.1 fix: root compose does NOT use :?required for
  # optional-profile vars (it would block 'docker compose --profile core up'
  # for operators who haven't configured the assistant profile). Per-service
  # compose (setup/walter-host/services/openclaw/compose.yml) keeps :?required.
  # Root just needs the env var reference (not a hardcoded value).
  grep -qE '\$\{OPENCLAW_GATEWAY_TOKEN' "$ROOT_COMPOSE"
  # And NO hardcoded "changeme" or "default" value
  ! grep -qE 'OPENCLAW_GATEWAY_TOKEN.*[:=]\s*"?(changeme|default|placeholder)' "$ROOT_COMPOSE"
}
@test "root compose openclaw service references openclaw_data volume" {
  grep -q "openclaw_data" "$ROOT_COMPOSE"
}

# --- secrets-runtime-architecture appendix ---
@test "secrets-runtime-architecture.md mentions per-service LiteLLM key" {
  grep -qi "LITELLM_OPENCLAW_KEY\|per-service.*key\|virtual key" \
    "$REPO_ROOT/docs/specs/secrets-runtime-architecture.md"
}
@test "secrets-runtime-architecture.md has gitleaks section or references gitleaks hook" {
  grep -qi "gitleaks" "$REPO_ROOT/docs/specs/secrets-runtime-architecture.md"
}
