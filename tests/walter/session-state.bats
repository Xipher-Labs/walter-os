#!/usr/bin/env bats
# Foundation tests for #122 time-bounded session state.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_SESSION_REPO="$TMP_HOME/work/repo"
  export WALTER_SESSION_MAX_HOURS=8
  export WALTER_SESSION_MAX_IDLE_MIN=60
  export WALTER_SESSION_TEST_CLOCK=1
  mkdir -p "$WALTER_CONFIG" "$WALTER_SESSION_REPO"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_mode() {
  stat -f "%Lp" "$1" 2>/dev/null || stat -c "%a" "$1"
}

@test "session touch creates state file with current timestamps" {
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"started"'* ]]

  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  [ -f "$state_file" ]
  jq -e '.session_id and .started_at == "2026-01-01T00:00:00Z" and .last_activity_at == "2026-01-01T00:00:00Z"' "$state_file"
}

@test "session touch creates capability signing key material" {
  command -v openssl >/dev/null 2>&1 || skip "openssl required"
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  public_key="$(jq -r '.capability_public_key_path' "$state_file")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"

  [ -f "$private_key" ]
  [ -f "$public_key" ]
  [ -d "$caps_dir" ]
  [ "$(_mode "$private_key")" = "600" ]
  [ "$(_mode "$caps_dir")" = "700" ]
  openssl pkey -in "$private_key" -pubout 2>/dev/null | cmp -s - "$public_key"
}

@test "concurrent session starts leave one key and caps directory" {
  command -v openssl >/dev/null 2>&1 || skip "openssl required"
  export WALTER_SESSION_NOW_EPOCH=1767225600

  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null &
  pid_one=$!
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null &
  pid_two=$!
  wait "$pid_one"
  wait "$pid_two"

  state_dir="$WALTER_CONFIG/state"
  key_count="$(find "$state_dir" -type f -name 'session-*.key' | wc -l | tr -d ' ')"
  caps_count="$(find "$state_dir" -type d -name 'caps-*' | wc -l | tr -d ' ')"
  [ "$key_count" = "1" ]
  [ "$caps_count" = "1" ]
}

@test "session start reclaims a stale lock with a dead pid" {
  command -v openssl >/dev/null 2>&1 || skip "openssl required"
  export WALTER_SESSION_NOW_EPOCH=1767225600
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  lock_dir="${state_file}.lock"
  mkdir -p "$lock_dir"
  printf '999999999\n' > "$lock_dir/pid"

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"started"'* ]]
  [ -f "$state_file" ]
  [ ! -d "$lock_dir" ]
}

@test "clock override is ignored outside explicit test mode" {
  unset WALTER_SESSION_TEST_CLOCK
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  jq -e '.started_at != "2026-01-01T00:00:00Z"' "$state_file"
}

@test "session touch within idle window updates last_activity_at" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767227400
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"active"'* ]]
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  jq -e '.started_at == "2026-01-01T00:00:00Z" and .last_activity_at == "2026-01-01T00:30:00Z"' "$state_file"
}

@test "session touch after idle window reports max-idle expiry" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  first_id="$(bash -c "source '$LIB'; walter_session_get '$WALTER_SESSION_REPO' | jq -r .session_id")"
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  public_key="$(jq -r '.capability_public_key_path' "$state_file")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"

  export WALTER_SESSION_NOW_EPOCH=1767231001
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 10 ]
  [[ "$output" == *'"status":"expired"'* ]]
  [[ "$output" == *'"trigger":"max-idle"'* ]]
  second_id="$(bash -c "source '$LIB'; walter_session_get '$WALTER_SESSION_REPO' | jq -r .session_id")"
  [ "$first_id" = "$second_id" ]
  [ ! -f "$private_key" ]
  [ ! -d "$caps_dir" ]
  [ -f "$public_key" ]
}

@test "session touch after max hours reports max-hours expiry" {
  export WALTER_SESSION_MAX_IDLE_MIN=600
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767254401
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 10 ]
  [[ "$output" == *'"status":"expired"'* ]]
  [[ "$output" == *'"trigger":"max-hours"'* ]]
}

@test "session touch after both idle and max-hours windows reports idle expiry" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  first_id="$(bash -c "source '$LIB'; walter_session_get '$WALTER_SESSION_REPO' | jq -r .session_id")"

  export WALTER_SESSION_NOW_EPOCH=1767315600
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 10 ]
  [[ "$output" == *'"status":"expired"'* ]]
  [[ "$output" == *'"trigger":"max-idle"'* ]]
  second_id="$(bash -c "source '$LIB'; walter_session_get '$WALTER_SESSION_REPO' | jq -r .session_id")"
  [ "$first_id" = "$second_id" ]
}

@test "PHI mode caps effective limits" {
  export WALTER_PHI_MODE=1
  export WALTER_SESSION_MAX_HOURS=12
  export WALTER_SESSION_MAX_IDLE_MIN=90
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  jq -e '.max_hours_at_start == 4 and .max_idle_min_at_start == 30' "$state_file"
}

@test "invalid configured limits fall back to safe defaults" {
  export WALTER_SESSION_MAX_HOURS=banana
  export WALTER_SESSION_MAX_IDLE_MIN=0
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  jq -e '.max_hours_at_start == 8 and .max_idle_min_at_start == 60' "$state_file"
}

@test "session touch rejects clock rewind" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null

  export WALTER_SESSION_NOW_EPOCH=1767225599
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 11 ]
  [[ "$output" == *'"status":"invalid"'* ]]
  [[ "$output" == *'"trigger":"clock-rewind"'* ]]
}

@test "session touch fails closed on malformed state" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  mkdir -p "$(dirname "$state_file")"
  printf '{}\n' > "$state_file"

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 11 ]
  [[ "$output" == *'"status":"invalid"'* ]]
  [[ "$output" == *'"trigger":"malformed-state"'* ]]
}

@test "session touch fails closed on malformed timestamps" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  mkdir -p "$(dirname "$state_file")"
  jq -n \
    --arg started_at "not-a-date" \
    --arg last_activity_at "2026-01-01T00:00:00Z" \
    '{session_id:"bad", started_at:$started_at, last_activity_at:$last_activity_at}' > "$state_file"

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 11 ]
  [[ "$output" == *'"status":"invalid"'* ]]
  [[ "$output" == *'"trigger":"malformed-state"'* ]]
}

@test "session touch invalidates active legacy sessions without capability material" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  mkdir -p "$(dirname "$state_file")"
  jq -n \
    --arg started_at "2026-01-01T00:00:00Z" \
    --arg last_activity_at "2026-01-01T00:30:00Z" \
    '{session_id:"legacy-session", started_at:$started_at, last_activity_at:$last_activity_at}' > "$state_file"

  export WALTER_SESSION_NOW_EPOCH=1767227401
  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 11 ]
  [[ "$output" == *'"status":"invalid"'* ]]
  [[ "$output" == *'"trigger":"legacy-session"'* ]]
}

@test "session touch fails closed when state cannot be created" {
  rm -r "$WALTER_CONFIG"
  printf '%s\n' "not a directory" > "$WALTER_CONFIG"
  export WALTER_SESSION_NOW_EPOCH=1767225600

  run bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'"

  [ "$status" -eq 12 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"trigger":"state-write"'* ]]
}

@test "session end removes state file" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  public_key="$(jq -r '.capability_public_key_path' "$state_file")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [ -f "$state_file" ]
  [ -f "$private_key" ]
  [ -f "$public_key" ]
  [ -d "$caps_dir" ]

  run bash -c "source '$LIB'; walter_session_end '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [ ! -f "$state_file" ]
  [ ! -f "$private_key" ]
  [ ! -d "$caps_dir" ]
  [ -f "$public_key" ]
}

@test "session end tolerates an already-missing capabilities directory" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  private_key="$(jq -r '.capability_private_key_path' "$state_file")"
  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  rm -r "$caps_dir"

  run bash -c "source '$LIB'; walter_session_end '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [ ! -f "$state_file" ]
  [ ! -f "$private_key" ]
}

@test "session end ignores private key paths outside the state directory" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  victim="$TMP_HOME/victim.txt"
  printf 'keep me\n' > "$victim"
  tmp_state="${state_file}.tmp"
  jq --arg victim "$victim" '.capability_private_key_path = $victim' "$state_file" > "$tmp_state"
  mv "$tmp_state" "$state_file"

  run bash -c "source '$LIB'; walter_session_end '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [ -f "$victim" ]
  [ ! -f "$state_file" ]
}

@test "session end ignores stored caps dir traversal paths" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  real_caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  victim_dir="$TMP_HOME/victim-dir"
  mkdir -p "$victim_dir"
  tmp_state="${state_file}.tmp"
  jq --arg caps_dir "${real_caps_dir}/../../victim-dir" '.capability_tokens_dir = $caps_dir' "$state_file" > "$tmp_state"
  mv "$tmp_state" "$state_file"

  run bash -c "source '$LIB'; walter_session_end '$WALTER_SESSION_REPO'"

  [ "$status" -eq 0 ]
  [ -d "$victim_dir" ]
  [ ! -d "$real_caps_dir" ]
  [ ! -f "$state_file" ]
}

@test "session end reports delete failures" {
  export WALTER_SESSION_NOW_EPOCH=1767225600
  bash -c "source '$LIB'; walter_session_touch '$WALTER_SESSION_REPO'" >/dev/null
  state_file="$(bash -c "source '$LIB'; walter_session_state_file '$WALTER_SESSION_REPO'")"
  chmod u-w "$(dirname "$state_file")"

  run bash -c "source '$LIB'; walter_session_end '$WALTER_SESSION_REPO'"

  [ "$status" -eq 12 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"trigger":"state-delete"'* ]]
}
