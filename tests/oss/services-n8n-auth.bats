#!/usr/bin/env bats
# shellcheck disable=SC2016
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
DEPLOY="$REPO_ROOT/setup/walter-host/services/n8n/deploy.sh"
ENV_TEMPLATE="$REPO_ROOT/setup/walter-host/services/n8n/.env.template"
IMPORT_SCRIPT="$REPO_ROOT/setup/walter-host/services/n8n/import-workflows.sh"

setup() {
  TMP_SVC=""
}

teardown() {
  if [[ -n "${TMP_SVC:-}" ]]; then
    case "$TMP_SVC" in
      /tmp/*|/var/tmp/*|/var/folders/*) rm -rf "$TMP_SVC" ;;
    esac
  fi
}

file_mode() {
  stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1"
}

@test "n8n compose has N8N_BASIC_AUTH_ACTIVE set to \"true\" (P1-03)" {
  [ -f "$COMPOSE" ]
  # Must literally be `"true"` (string). false / unset / true (no quotes)
  # all fail.
  grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"true"\s*$' "$COMPOSE"
}

@test "n8n compose does NOT set N8N_BASIC_AUTH_ACTIVE to \"false\" (P1-03)" {
  [ -f "$COMPOSE" ]
  run grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"false"\s*$' "$COMPOSE"
  [ "$status" -ne 0 ]
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
  grep -q 'infisical run --env=prod -- bash deploy.sh' "$README"
  grep -q 'password manager instead' "$README"
  grep -q 'cd /opt/walter-vm/services/n8n' "$README"
  if grep -q 'infisical export .*>> .env' "$README"; then
    return 1
  fi
}

@test "n8n deploy.sh generates missing basic-auth credentials (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" bash "$DEPLOY"

  [ "$status" -eq 0 ]
  grep -q '^N8N_BASIC_AUTH_USER=walter-admin$' "$TMP_SVC/.env"
  grep -qE '^N8N_BASIC_AUTH_PASSWORD=[0-9a-f]{48}$' "$TMP_SVC/.env"
}

@test "n8n deploy.sh honors provided basic-auth credentials (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER=operator \
    N8N_BASIC_AUTH_PASSWORD=provided-secret \
    bash "$DEPLOY"

  [ "$status" -eq 0 ]
  grep -q '^N8N_BASIC_AUTH_USER=operator$' "$TMP_SVC/.env"
  grep -q '^N8N_BASIC_AUTH_PASSWORD=provided-secret$' "$TMP_SVC/.env"
}

@test "n8n deploy.sh treats whitespace-only env overrides as missing (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER='   ' \
    N8N_BASIC_AUTH_PASSWORD='   ' \
    bash "$DEPLOY"

  [ "$status" -eq 0 ]
  grep -q '^N8N_BASIC_AUTH_USER=walter-admin$' "$TMP_SVC/.env"
  grep -qE '^N8N_BASIC_AUTH_PASSWORD=[0-9a-f]{48}$' "$TMP_SVC/.env"
}

@test "n8n deploy.sh trims env override values before writing .env (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER=' operator ' \
    N8N_BASIC_AUTH_PASSWORD=' provided-secret ' \
    bash "$DEPLOY"

  [ "$status" -eq 0 ]
  grep -q '^N8N_BASIC_AUTH_USER=operator$' "$TMP_SVC/.env"
  grep -q '^N8N_BASIC_AUTH_PASSWORD=provided-secret$' "$TMP_SVC/.env"
}

@test "n8n deploy.sh rejects multiline basic-auth values before writing .env (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER=$'operator\nINJECTED_KEY=1' \
    N8N_BASIC_AUTH_PASSWORD=provided-secret \
    bash "$DEPLOY"

  [ "$status" -ne 0 ]
  [[ "$output" == *"N8N_BASIC_AUTH_USER must be a single-line value"* ]]
  run grep -q '^INJECTED_KEY=1$' "$TMP_SVC/.env"
  [ "$status" -ne 0 ]
}

@test "n8n deploy.sh does not require openssl when required keys already exist (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  cat > "$TMP_SVC/.env" <<'ENV'
N8N_PG_PASS=pg
N8N_ENCRYPTION_KEY=encryption
N8N_BASIC_AUTH_USER=operator
N8N_BASIC_AUTH_PASSWORD=provided-secret
ENV
  chmod 600 "$TMP_SVC/.env"
  mkdir "$TMP_SVC/bin"
  ln -s "$(command -v awk)" "$TMP_SVC/bin/awk"
  ln -s "$(command -v chmod)" "$TMP_SVC/bin/chmod"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" PATH="$TMP_SVC/bin" /bin/bash "$DEPLOY"

  [ "$status" -eq 0 ]
  [[ "$output" != *"openssl is required"* ]]
}

@test "n8n deploy.sh reapplies 0600 mode to existing .env (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  cat > "$TMP_SVC/.env" <<'ENV'
N8N_PG_PASS=pg
N8N_ENCRYPTION_KEY=encryption
N8N_BASIC_AUTH_USER=operator
N8N_BASIC_AUTH_PASSWORD=provided-secret
ENV
  chmod 0644 "$TMP_SVC/.env"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" bash "$DEPLOY"

  [ "$status" -eq 0 ]
  [ "$(file_mode "$TMP_SVC/.env")" = "600" ]
}

@test "n8n deploy.sh does not print secret values to stdout (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  cat > "$TMP_SVC/.env" <<'ENV'
N8N_PG_PASS=pg-secret
N8N_ENCRYPTION_KEY=encryption-secret
N8N_BASIC_AUTH_USER=operator-user
N8N_BASIC_AUTH_PASSWORD=provided-secret
ENV
  chmod 600 "$TMP_SVC/.env"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" bash "$DEPLOY"

  [ "$status" -eq 0 ]
  [[ "$output" != *"pg-secret"* ]]
  [[ "$output" != *"encryption-secret"* ]]
  [[ "$output" != *"operator-user"* ]]
  [[ "$output" != *"provided-secret"* ]]
}

@test "n8n deploy.sh requires WALTER_DOMAIN before full deploy work (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  cat > "$TMP_SVC/.env" <<'ENV'
N8N_PG_PASS=pg
N8N_ENCRYPTION_KEY=encryption
N8N_BASIC_AUTH_USER=operator
N8N_BASIC_AUTH_PASSWORD=provided-secret
ENV
  chmod 600 "$TMP_SVC/.env"

  run env -u WALTER_DOMAIN SVC_DIR="$TMP_SVC" bash "$DEPLOY"

  [ "$status" -eq 2 ]
  [[ "$output" == *"WALTER_DOMAIN is required"* ]]
  [[ "$output" != *"docker compose pull"* ]]
}

@test "n8n deploy.sh checks cloudflared route with fixed-string grep (P1-03)" {
  [ -f "$DEPLOY" ]
  grep -q 'grep -Fq "n8n.${WALTER_DOMAIN}"' "$DEPLOY"
}

@test "n8n deploy.sh treats blank quoted/whitespace auth values as missing (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  {
    printf '%s\n' 'N8N_PG_PASS=pg'
    printf '%s\n' 'N8N_ENCRYPTION_KEY=encryption'
    printf '%s\n' 'N8N_BASIC_AUTH_USER=""'
    printf 'N8N_BASIC_AUTH_PASSWORD=   \n'
  } > "$TMP_SVC/.env"
  chmod 600 "$TMP_SVC/.env"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER=operator \
    N8N_BASIC_AUTH_PASSWORD=provided-secret \
    bash "$DEPLOY"

  [ "$status" -eq 0 ]
  grep -q '^N8N_BASIC_AUTH_USER=operator$' "$TMP_SVC/.env"
  grep -q '^N8N_BASIC_AUTH_PASSWORD=provided-secret$' "$TMP_SVC/.env"
}

@test "n8n deploy.sh treats the last duplicate env assignment as authoritative (P1-03)" {
  TMP_SVC="$(mktemp -d)"
  cp "$ENV_TEMPLATE" "$TMP_SVC/.env.template"
  {
    printf '%s\n' 'N8N_PG_PASS=pg'
    printf '%s\n' 'N8N_ENCRYPTION_KEY=encryption'
    printf '%s\n' 'N8N_BASIC_AUTH_USER=operator'
    printf '%s\n' 'N8N_BASIC_AUTH_USER=""'
    printf '%s\n' 'N8N_BASIC_AUTH_PASSWORD=provided-secret'
    printf 'N8N_BASIC_AUTH_PASSWORD=   \n'
  } > "$TMP_SVC/.env"
  chmod 600 "$TMP_SVC/.env"

  run env N8N_DEPLOY_ENV_ONLY=1 SVC_DIR="$TMP_SVC" \
    N8N_BASIC_AUTH_USER=operator \
    N8N_BASIC_AUTH_PASSWORD=provided-secret \
    bash "$DEPLOY"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^N8N_BASIC_AUTH_USER=operator$' "$TMP_SVC/.env")" -eq 2 ]
  [ "$(grep -c '^N8N_BASIC_AUTH_PASSWORD=provided-secret$' "$TMP_SVC/.env")" -eq 2 ]
}

@test "n8n import-workflows supports optional basic-auth curl args (P1-03)" {
  [ -f "$IMPORT_SCRIPT" ]
  grep -q 'N8N_BASIC_AUTH_USER' "$IMPORT_SCRIPT"
  grep -q 'N8N_BASIC_AUTH_PASSWORD' "$IMPORT_SCRIPT"
  grep -q 'curl_auth_args=(-u "${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}")' "$IMPORT_SCRIPT"
  grep -q 'set both N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD' "$IMPORT_SCRIPT"
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
  run grep -qE '^\s*N8N_BASIC_AUTH_ACTIVE:\s*"false"\s*$' "$ROOT_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "root compose.yml: n8n service wires both basic-auth env vars with :? guard (P1-03)" {
  [ -f "$ROOT_COMPOSE" ]
  grep -qE 'N8N_BASIC_AUTH_USER:\s+\$\{N8N_BASIC_AUTH_USER:\?' "$ROOT_COMPOSE"
  grep -qE 'N8N_BASIC_AUTH_PASSWORD:\s+\$\{N8N_BASIC_AUTH_PASSWORD:\?' "$ROOT_COMPOSE"
}

@test "root .env.example documents n8n basic-auth inputs (P1-03)" {
  [ -f "$REPO_ROOT/.env.example" ]
  grep -q '^# N8N_BASIC_AUTH_USER=walter-admin$' "$REPO_ROOT/.env.example"
  grep -q '^# N8N_BASIC_AUTH_PASSWORD=$' "$REPO_ROOT/.env.example"
}
