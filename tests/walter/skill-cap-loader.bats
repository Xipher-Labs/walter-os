#!/usr/bin/env bats
# tests/walter/skill-cap-loader.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOADER="$REPO_ROOT/scripts/walter/lib/skill-cap-loader.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  REPO_UNDER_TEST="$TMP_HOME/work/repo"
  mkdir -p "$WALTER_CONFIG/overlay" "$REPO_UNDER_TEST"
  command -v yq >/dev/null 2>&1 || skip "yq required"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_write_config() {
  cat > "$WALTER_CONFIG/overlay/skill-capabilities.yml"
}

@test "skill cap loader auto-mints enabled default capabilities" {
  _write_config <<'YAML'
skills:
  nuclei-cli:
    tool: Bash
    scope:
      patterns: ["nuclei[[:space:]].*"]
      network: ["*"]
    duration: 4h
  disabled-skill:
    enabled: false
    tool: Bash
    scope:
      patterns: [".*"]
    duration: 4h
YAML

  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  run bash -c "source '$LOADER'; walter_skill_caps_mint_defaults '$REPO_UNDER_TEST'"

  [ "$status" -eq 0 ]
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [ "$(find "$caps_dir" -type f -name 'cap-*.paseto' | wc -l | tr -d ' ')" = "1" ]
  token_file="$(find "$caps_dir" -type f -name 'cap-*.paseto' | head -1)"
  claims="$(bash -c "source '$REPO_ROOT/scripts/walter/lib/capability-token.sh'; walter_cap_verify_token '$state_file' \"$(cat "$token_file")\"")"

  echo "$claims" | jq -e '.skill_name == "nuclei-cli"'
  echo "$claims" | jq -e '.tool == "Bash"'
  echo "$claims" | jq -e '.scope.patterns == ["nuclei[[:space:]].*"]'
  echo "$claims" | jq -e '.scope.network == ["*"]'
}

@test "skill cap loader rejects malformed enabled entries" {
  _write_config <<'YAML'
skills:
  bad-skill:
    tool: Bash
    scope: {}
    duration: 4h
YAML

  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  run bash -c "source '$LOADER'; walter_skill_caps_mint_defaults '$REPO_UNDER_TEST'"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid capability entry"* ]]
}

@test "skill cap loader writes no partial tokens when later entry is invalid" {
  _write_config <<'YAML'
skills:
  aaa-good:
    tool: Bash
    scope:
      patterns: ["nuclei[[:space:]].*"]
    duration: 4h
  zzz-bad:
    tool: Bash
    scope: {}
    duration: 4h
YAML

  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_UNDER_TEST'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_UNDER_TEST'")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  run bash -c "source '$LOADER'; walter_skill_caps_mint_defaults '$REPO_UNDER_TEST'"

  [ "$status" -ne 0 ]
  [ "$(find "$caps_dir" -type f -name 'cap-*.paseto' | wc -l | tr -d ' ')" = "0" ]
}
