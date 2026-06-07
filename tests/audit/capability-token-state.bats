#!/usr/bin/env bats
# Daily-audit coverage for capability-token state hygiene.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"
  [[ -f "$AUDIT" ]] || skip "audit.sh missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export CLAUDE_HOME="$TMP_HOME/.claude"
  export CODEX_HOME="$TMP_HOME/.codex"
  mkdir -p "$WALTER_CONFIG/state" "$CLAUDE_HOME" "$CODEX_HOME"

  export AUDIT_FINDINGS="$TMP_HOME/findings.jsonl"
  AUDIT_RUNNER="$TMP_HOME/run_check_cap_state.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "source '$AUDIT'" \
    'finding() {' \
    '  local sev="$1" id="$2" desc="$3" action="${4:-investigate manually}"' \
    '  jq -nc --arg sev "$sev" --arg id "$id" --arg desc "$desc" --arg action "$action" '\''{severity: $sev, id: $id, desc: $desc, action: $action}'\'' >> "$AUDIT_FINDINGS"' \
    '}' \
    'check_cap_state' \
    > "$AUDIT_RUNNER"
  chmod +x "$AUDIT_RUNNER"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

@test "daily audit defines and invokes check_cap_state" {
  grep -q '^check_cap_state()' "$AUDIT"
  grep -q '^[[:space:]]*check_cap_state$' "$AUDIT"
}

@test "orphaned capability token dir reports cap-cleanup-stale" {
  mkdir -p "$WALTER_CONFIG/state/caps-stale-session"
  printf 'v4.public.fake-token\n' > "$WALTER_CONFIG/state/caps-stale-session/cap-stale.paseto"
  chmod 600 "$WALTER_CONFIG/state/caps-stale-session/cap-stale.paseto"

  run bash "$AUDIT_RUNNER"

  [ "$status" -eq 0 ]
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "info" and .id == "cap-cleanup-stale")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "malformed capability session state reports cap-state-malformed" {
  printf '{not-json\n' > "$WALTER_CONFIG/state/session-bad.json"

  run bash "$AUDIT_RUNNER"

  [ "$status" -eq 0 ]
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "cap-state-malformed")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "capability token files not mode 0600 report high finding" {
  mkdir -p "$WALTER_CONFIG/state/caps-active-session"
  printf 'v4.public.fake-token\n' > "$WALTER_CONFIG/state/caps-active-session/cap-wide.paseto"
  chmod 644 "$WALTER_CONFIG/state/caps-active-session/cap-wide.paseto"
  jq -n \
    --arg session_id "active-session" \
    --arg private_key "$WALTER_CONFIG/state/session-active-session.key" \
    --arg public_key "$WALTER_CONFIG/state/session-active-session.pub" \
    --arg caps_dir "$WALTER_CONFIG/state/caps-active-session" \
    '{
      session_id: $session_id,
      started_at: "2026-01-01T00:00:00Z",
      last_activity_at: "2026-01-01T00:00:00Z",
      capability_private_key_path: $private_key,
      capability_public_key_path: $public_key,
      capability_tokens_dir: $caps_dir,
      max_hours_at_start: 8,
      max_idle_min_at_start: 60
    }' > "$WALTER_CONFIG/state/session-active-session.json"
  printf 'PRIVATE\n' > "$WALTER_CONFIG/state/session-active-session.key"
  chmod 600 "$WALTER_CONFIG/state/session-active-session.key"

  run bash "$AUDIT_RUNNER"

  [ "$status" -eq 0 ]
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "cap-token-perms")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "capability files with mode 0600 do not report permission findings" {
  mkdir -p "$WALTER_CONFIG/state/caps-active-session"
  printf 'v4.public.fake-token\n' > "$WALTER_CONFIG/state/caps-active-session/cap-ok.paseto"
  chmod 600 "$WALTER_CONFIG/state/caps-active-session/cap-ok.paseto"
  jq -n \
    --arg session_id "active-session" \
    --arg private_key "$WALTER_CONFIG/state/session-active-session.key" \
    --arg public_key "$WALTER_CONFIG/state/session-active-session.pub" \
    --arg caps_dir "$WALTER_CONFIG/state/caps-active-session" \
    '{
      session_id: $session_id,
      started_at: "2026-01-01T00:00:00Z",
      last_activity_at: "2026-01-01T00:00:00Z",
      capability_private_key_path: $private_key,
      capability_public_key_path: $public_key,
      capability_tokens_dir: $caps_dir,
      max_hours_at_start: 8,
      max_idle_min_at_start: 60
    }' > "$WALTER_CONFIG/state/session-active-session.json"
  printf 'PRIVATE\n' > "$WALTER_CONFIG/state/session-active-session.key"
  chmod 600 "$WALTER_CONFIG/state/session-active-session.key"

  run bash "$AUDIT_RUNNER"

  [ "$status" -eq 0 ]
  if [[ -s "$AUDIT_FINDINGS" ]]; then
    run jq -s 'map(select(.id == "cap-token-perms" or .id == "cap-key-perms")) | length' "$AUDIT_FINDINGS"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]
  fi
}

@test "capability private key not mode 0600 reports critical finding" {
  mkdir -p "$WALTER_CONFIG/state/caps-active-session"
  jq -n \
    --arg session_id "active-session" \
    --arg private_key "$WALTER_CONFIG/state/session-active-session.key" \
    --arg public_key "$WALTER_CONFIG/state/session-active-session.pub" \
    --arg caps_dir "$WALTER_CONFIG/state/caps-active-session" \
    '{
      session_id: $session_id,
      started_at: "2026-01-01T00:00:00Z",
      last_activity_at: "2026-01-01T00:00:00Z",
      capability_private_key_path: $private_key,
      capability_public_key_path: $public_key,
      capability_tokens_dir: $caps_dir,
      max_hours_at_start: 8,
      max_idle_min_at_start: 60
    }' > "$WALTER_CONFIG/state/session-active-session.json"
  printf 'PRIVATE\n' > "$WALTER_CONFIG/state/session-active-session.key"
  chmod 644 "$WALTER_CONFIG/state/session-active-session.key"

  run bash "$AUDIT_RUNNER"

  [ "$status" -eq 0 ]
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "cap-key-perms")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
