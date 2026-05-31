#!/usr/bin/env bats
# PASETO v4.public-compatible capability token helper tests.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  CAP_LIB="$REPO_ROOT/scripts/walter/lib/capability-token.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_SESSION_REPO="$TMP_HOME/work/repo"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  mkdir -p "$WALTER_CONFIG" "$WALTER_SESSION_REPO"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_state_file() {
  bash -c "source '$SESSION_LIB'; walter_session_state_file '$WALTER_SESSION_REPO'"
}

@test "capability helper signs and verifies claims" {
  bash -c "source '$SESSION_LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(_state_file)"
  claims="$(jq -nc \
    --arg session_id "$(jq -r '.session_id' "$state_file")" \
    '{iss:"walter-os", sub:"operator", session_id:$session_id, tool:"Bash", scope:{paths:["src/*"], network:[], patterns:["^make test$"]}, iat:"2026-01-01T00:00:00Z", exp:"2026-01-01T00:30:00Z", nonce:"cap-test"}')"

  run bash -c "source '$CAP_LIB'; token=\"\$(walter_cap_sign_claims '$state_file' '$claims')\"; echo \"\$token\"; walter_cap_verify_token '$state_file' \"\$token\""

  [ "$status" -eq 0 ]
  [[ "$output" == v4.public.* ]]
  echo "$output" | tail -1 | jq -e '.tool == "Bash" and .nonce == "cap-test"'
}

@test "capability helper rejects tampered tokens" {
  bash -c "source '$SESSION_LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(_state_file)"
  claims="$(jq -nc \
    --arg session_id "$(jq -r '.session_id' "$state_file")" \
    '{iss:"walter-os", sub:"operator", session_id:$session_id, tool:"Write", scope:{paths:["README.md"], network:[], patterns:[]}, iat:"2026-01-01T00:00:00Z", exp:"2026-01-01T00:30:00Z", nonce:"cap-test"}')"
  token="$(bash -c "source '$CAP_LIB'; walter_cap_sign_claims '$state_file' '$claims'")"
  tampered="${token%?}A"

  run bash -c "source '$CAP_LIB'; walter_cap_verify_token '$state_file' '$tampered'"

  [ "$status" -ne 0 ]
}

@test "duration parser rejects bare integers" {
  run bash -c "source '$CAP_LIB'; walter_cap_duration_to_seconds 4"

  [ "$status" -ne 0 ]
  [[ "$output" == *"duration must include a unit"* ]]
}
