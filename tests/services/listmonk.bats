#!/usr/bin/env bats
# Static assertions for the optional Listmonk devrel/newsletter profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LISTMONK_DIR="$REPO_ROOT/setup/walter-host/services/listmonk"
  LISTMONK_COMPOSE="$LISTMONK_DIR/compose.yml"
  LISTMONK_ENV="$LISTMONK_DIR/.env.template"
  LISTMONK_README="$LISTMONK_DIR/README.md"
}

@test "listmonk service files exist" {
  [[ -f "$LISTMONK_COMPOSE" ]]
  [[ -f "$LISTMONK_ENV" ]]
  [[ -f "$LISTMONK_README" ]]
}

@test "listmonk services are gated behind the listmonk profile" {
  grep -qE 'profiles:\s*\[listmonk\]' "$LISTMONK_COMPOSE"
  [ "$(grep -cE 'profiles:\s*\[listmonk\]' "$LISTMONK_COMPOSE")" -ge 2 ]
}

@test "listmonk image is pinned to v6.1.0 and never latest" {
  grep -q 'image: listmonk/listmonk:v6.1.0' "$LISTMONK_COMPOSE"
  run grep -RInE '(:latest|LISTMONK_.*latest|nightly)' "$LISTMONK_DIR"
  [ "$status" -ne 0 ]
}

@test "listmonk compose includes dedicated Postgres and named persistence volumes" {
  grep -q 'image: postgres:' "$LISTMONK_COMPOSE"
  grep -q 'listmonk_pg:' "$LISTMONK_COMPOSE"
  grep -q 'listmonk_uploads:' "$LISTMONK_COMPOSE"
  grep -q '/var/lib/postgresql/data' "$LISTMONK_COMPOSE"
  grep -q '/listmonk/uploads' "$LISTMONK_COMPOSE"
}

@test "listmonk secrets fail closed in compose" {
  grep -qE '\$\{LISTMONK_POSTGRES_PASSWORD:\?' "$LISTMONK_COMPOSE"
  grep -qE '\$\{LISTMONK_ADMIN_USER:\?' "$LISTMONK_COMPOSE"
  grep -qE '\$\{LISTMONK_ADMIN_PASSWORD:\?' "$LISTMONK_COMPOSE"
}

@test "listmonk env template contains no real secrets" {
  grep -q '^LISTMONK_POSTGRES_PASSWORD=$' "$LISTMONK_ENV"
  grep -q '^LISTMONK_ADMIN_USER=$' "$LISTMONK_ENV"
  grep -q '^LISTMONK_ADMIN_PASSWORD=$' "$LISTMONK_ENV"
  run grep -RInE '(changeme|password123|secret|token=.+|LISTMONK_.*=.+[A-Za-z0-9]{12,})' "$LISTMONK_ENV"
  [ "$status" -ne 0 ]
}

@test "listmonk avoids public host ports" {
  run grep -nE '^[[:space:]]+-[[:space:]]+"?([0-9]+|0\.0\.0\.0):' "$LISTMONK_COMPOSE"
  [ "$status" -ne 0 ]
  run grep -nE '9000:9000' "$LISTMONK_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "listmonk docs mention route, SMTP, unsubscribe, backups, and optionality" {
  grep -q 'https://listmonk.${WALTER_DOMAIN}' "$LISTMONK_README"
  grep -qi 'SMTP' "$LISTMONK_README"
  grep -qi 'unsubscribe' "$LISTMONK_README"
  grep -qi 'backup' "$LISTMONK_README"
  grep -qi 'optional' "$LISTMONK_README"
  grep -qi 'devrel\|newsletter' "$LISTMONK_README"
}
