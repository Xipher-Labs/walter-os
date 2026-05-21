#!/usr/bin/env bats
# tests/oss/services-n8n-auth.bats
#
# Audit P1-03 regression coverage: n8n must run with its built-in basic
# auth ENABLED as a defense-in-depth layer behind Cloudflare Access.
# Single-layer-auth setups (CF Access only) are one misconfig away from
# full exposure of n8n's Execute Command nodes and credential vault.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
COMPOSE="$REPO_ROOT/setup/walter-host/services/n8n/compose.yml"
ROOT_COMPOSE="$REPO_ROOT/compose.yml"
README="$REPO_ROOT/setup/walter-host/services/n8n/README.md"

@test "n8n compose has N8N_BASIC_AUTH_ACTIVE set to \"true\" (P1-03)" {
  [ -f "$COMPOSE" ]
  # Must literally be `"true"` (string). false / unset / true (no quotes)
  # all fail.
  grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"true"\s*$' "$COMPOSE"
}

@test "n8n compose does NOT set N8N_BASIC_AUTH_ACTIVE to \"false\" (P1-03)" {
  [ -f "$COMPOSE" ]
  ! grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"false"\s*$' "$COMPOSE"
}

@test "n8n compose wires N8N_BASIC_AUTH_USER + N8N_BASIC_AUTH_PASSWORD env vars (P1-03)" {
  [ -f "$COMPOSE" ]
  grep -qE 'N8N_BASIC_AUTH_USER:\s+\$\{N8N_BASIC_AUTH_USER' "$COMPOSE"
  grep -qE 'N8N_BASIC_AUTH_PASSWORD:\s+\$\{N8N_BASIC_AUTH_PASSWORD' "$COMPOSE"
}

@test "n8n compose fails loudly when basic-auth env vars are missing (\${VAR:?msg}) (P1-03)" {
  [ -f "$COMPOSE" ]
  # The :? substitution form makes docker compose fail at boot if either
  # var is absent. Without this, missing env silently falls back to
  # docker's default (empty string), which n8n would accept.
  grep -qE 'N8N_BASIC_AUTH_USER:\?' "$COMPOSE"
  grep -qE 'N8N_BASIC_AUTH_PASSWORD:\?' "$COMPOSE"
}

@test "n8n README documents the two-layer auth model (P1-03)" {
  [ -f "$README" ]
  grep -qi 'defense in depth\|defense-in-depth\|two-layer' "$README"
  grep -q 'Cloudflare Access' "$README"
  grep -q 'N8N_BASIC_AUTH_PASSWORD' "$README"
}

# --- Copilot R1 of #67: ALSO cover the repo-root compose.yml ---
# `install.sh` deploys the root compose.yml as the default-deploy path,
# not the walter-host services/n8n/compose.yml. Both files must hold the
# same basic-auth posture or the audit closure is only partial.

@test "root compose.yml: n8n service has N8N_BASIC_AUTH_ACTIVE \"true\" (P1-03)" {
  [ -f "$ROOT_COMPOSE" ]
  grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"true"\s*$' "$ROOT_COMPOSE"
}

@test "root compose.yml: n8n service does NOT set N8N_BASIC_AUTH_ACTIVE \"false\" (P1-03)" {
  [ -f "$ROOT_COMPOSE" ]
  ! grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"false"\s*$' "$ROOT_COMPOSE"
}

@test "root compose.yml: n8n service wires both basic-auth env vars with :? guard (P1-03)" {
  [ -f "$ROOT_COMPOSE" ]
  grep -qE 'N8N_BASIC_AUTH_USER:\s+\$\{N8N_BASIC_AUTH_USER:\?' "$ROOT_COMPOSE"
  grep -qE 'N8N_BASIC_AUTH_PASSWORD:\s+\$\{N8N_BASIC_AUTH_PASSWORD:\?' "$ROOT_COMPOSE"
}
