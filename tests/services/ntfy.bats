#!/usr/bin/env bats
# tests/services/ntfy.bats
# Static-analysis assertions for the optional ntfy notification profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  NTFY_DIR="$REPO_ROOT/setup/walter-host/services/ntfy"
  NTFY_COMPOSE="$NTFY_DIR/compose.yml"
  NTFY_ENV="$NTFY_DIR/.env.template"
  NTFY_README="$NTFY_DIR/README.md"
  NTFY_SERVER_TEMPLATE="$NTFY_DIR/server.yml.template"
}

@test "ntfy service files exist" {
  [[ -f "$NTFY_COMPOSE" ]]
  [[ -f "$NTFY_ENV" ]]
  [[ -f "$NTFY_README" ]]
  [[ -f "$NTFY_SERVER_TEMPLATE" ]]
}

@test "ntfy compose is gated behind optional ntfy profile" {
  python3 - "$NTFY_COMPOSE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    compose = yaml.safe_load(handle)

profiles = compose["services"]["ntfy"].get("profiles", [])
assert "ntfy" in profiles
assert "notifications" in profiles
PY
}

@test "ntfy compose keeps env file optional and network stable" {
  grep -q "required: false" "$NTFY_COMPOSE"
  grep -q "name: ntfy_net" "$NTFY_COMPOSE"
}

@test "ntfy compose pins exact v2.23.0 image and avoids latest" {
  grep -q "binwiederhier/ntfy:v2.23.0" "$NTFY_COMPOSE"
  run grep -RInE '(:latest|@latest)' "$NTFY_COMPOSE" "$NTFY_README" "$NTFY_SERVER_TEMPLATE"
  [ "$status" -ne 0 ]
}

@test "ntfy compose avoids public host ports" {
  run grep -qE '^[[:space:]]*ports:' "$NTFY_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "ntfy compose mounts config plus data and cache volumes" {
  grep -q "server.yml" "$NTFY_COMPOSE"
  grep -q "ntfy_data" "$NTFY_COMPOSE"
  grep -q "ntfy_cache" "$NTFY_COMPOSE"
}

@test "ntfy server template denies anonymous access by default" {
  grep -q "auth-default-access: deny-all" "$NTFY_SERVER_TEMPLATE"
}

@test "ntfy server template configures cache auth and attachment storage" {
  grep -q "cache-file:" "$NTFY_SERVER_TEMPLATE"
  grep -q "auth-file:" "$NTFY_SERVER_TEMPLATE"
  grep -q "attachment-cache-dir:" "$NTFY_SERVER_TEMPLATE"
}

@test "ntfy server template includes Walter domain base URL placeholder" {
  grep -q 'https://ntfy.${WALTER_DOMAIN}' "$NTFY_SERVER_TEMPLATE"
}

@test "ntfy README documents setup mobile iOS backups and optionality" {
  grep -q "server.yml.template" "$NTFY_README"
  grep -q "server.yml" "$NTFY_README"
  grep -qi "mobile" "$NTFY_README"
  grep -qi "iOS" "$NTFY_README"
  grep -qi "backup" "$NTFY_README"
  grep -qi "optional" "$NTFY_README"
}
