#!/usr/bin/env bats
# Tests for T-8: scripts/agents/lib/alerts.sh
# Covers: AC-1 through AC-5 of Improvement 8

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/alerts.sh"
  [[ -f "$LIB" ]] || skip "alerts.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  # Isolated environment
  WALTER_CONFIG="$(mktemp -d -t walter-alerts-config-XXXXXX)"
  export WALTER_CONFIG
  LOG_DIR="$(mktemp -d -t walter-alerts-log-XXXXXX)"
  export WALTER_ALERT_LOG="$LOG_DIR/events.log"
  export PAUSE_FLAG="$WALTER_CONFIG/agents.paused"
  # Prevent real Telegram/email calls
  export WALTER_TELEGRAM_BOT_TOKEN="mock-token"
  export WALTER_TELEGRAM_CHAT_ID="mock-chat"
  # Override curl so we can mock it
  _MOCK_CURL_DIR="$(mktemp -d)"
  export PATH="$_MOCK_CURL_DIR:$PATH"
  cat > "$_MOCK_CURL_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
# Mock curl — records call, returns empty JSON
echo '{"ok":true}' >&1
exit 0
CURL_MOCK
  chmod +x "$_MOCK_CURL_DIR/curl"

  # Mock sendmail/msmtp to avoid real email
  cat > "$_MOCK_CURL_DIR/sendmail" <<'MAIL_MOCK'
#!/usr/bin/env bash
exit 0
MAIL_MOCK
  chmod +x "$_MOCK_CURL_DIR/sendmail"
  cat > "$_MOCK_CURL_DIR/msmtp" <<'MSMTP_MOCK'
#!/usr/bin/env bash
exit 0
MSMTP_MOCK
  chmod +x "$_MOCK_CURL_DIR/msmtp"
}

teardown() {
  rm -rf "$WALTER_CONFIG" "$LOG_DIR" "$_MOCK_CURL_DIR"
}

# ---- info tier ----

@test "alert_emit info does NOT call Telegram (curl count = 0)" {
  local tracker="$WALTER_CONFIG/curl-calls-info.txt"
  cat > "$_MOCK_CURL_DIR/curl" <<CURL_TRACK
#!/usr/bin/env bash
echo "\$@" >> "$tracker"
echo '{"ok":true}'
exit 0
CURL_TRACK
  chmod +x "$_MOCK_CURL_DIR/curl"

  source "$LIB"
  alert_emit info "test info should not curl" '{}'
  # curl must NOT have been invoked at all for info tier
  [[ ! -f "$tracker" ]]
}

@test "alert_emit info logs JSONL entry" {
  source "$LIB"
  alert_emit info "test info message" '{}'
  [[ -f "$WALTER_ALERT_LOG" ]]
  grep -q '"tier":"info"' "$WALTER_ALERT_LOG"
}

@test "alert_emit info does NOT create pause flag" {
  source "$LIB"
  alert_emit info "test info message" '{}'
  [[ ! -f "$PAUSE_FLAG" ]]
}

@test "alert_emit info does NOT create gate.lock" {
  source "$LIB"
  alert_emit info "test info message" '{}'
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]
}

# ---- warn tier ----

@test "alert_emit warn logs JSONL entry" {
  source "$LIB"
  alert_emit warn "test warn message" '{}'
  grep -q '"tier":"warn"' "$WALTER_ALERT_LOG"
}

@test "alert_emit warn calls Telegram (mock curl invoked)" {
  # Track curl calls via a temp file
  local tracker="$WALTER_CONFIG/curl-calls.txt"
  cat > "$_MOCK_CURL_DIR/curl" <<CURL_TRACK
#!/usr/bin/env bash
echo "\$@" >> "$tracker"
echo '{"ok":true}'
exit 0
CURL_TRACK
  chmod +x "$_MOCK_CURL_DIR/curl"

  source "$LIB"
  alert_emit warn "test warn message" '{}'
  [[ -f "$tracker" ]]
  grep -q "api.telegram.org" "$tracker"
}

@test "alert_emit warn does NOT create pause flag" {
  source "$LIB"
  alert_emit warn "test warn message" '{}'
  [[ ! -f "$PAUSE_FLAG" ]]
}

@test "alert_emit warn does NOT create gate.lock" {
  source "$LIB"
  alert_emit warn "test warn message" '{}'
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]
}

# ---- critical tier ----

@test "alert_emit critical logs JSONL entry" {
  source "$LIB"
  alert_emit critical "test critical" '{}'
  grep -q '"tier":"critical"' "$WALTER_ALERT_LOG"
}

@test "alert_emit critical creates TOWER_CRITICAL_FLAG file" {
  source "$LIB"
  alert_emit critical "test critical" '{}'
  [[ -f "${WALTER_CONFIG}/tower-critical.flag" ]]
}

@test "alert_emit critical does NOT create gate.lock" {
  source "$LIB"
  alert_emit critical "test critical" '{}'
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]
}

# ---- panic tier ----

@test "alert_emit panic logs JSONL entry" {
  source "$LIB"
  alert_emit panic "test panic" '{}'
  grep -q '"tier":"panic"' "$WALTER_ALERT_LOG"
}

@test "alert_emit panic creates pause flag" {
  source "$LIB"
  alert_emit panic "test panic" '{}'
  [[ -f "$PAUSE_FLAG" ]]
}

@test "alert_emit panic creates gate.lock" {
  source "$LIB"
  alert_emit panic "test panic" '{}'
  [[ -f "$WALTER_CONFIG/gate.lock" ]]
}

# ---- alert_unlock ----

@test "alert_unlock removes gate.lock" {
  source "$LIB"
  alert_emit panic "create lock" '{}'
  [[ -f "$WALTER_CONFIG/gate.lock" ]]
  alert_unlock "test unlock reason"
  [[ ! -f "$WALTER_CONFIG/gate.lock" ]]
}

@test "alert_unlock removes pause flag" {
  source "$LIB"
  alert_emit panic "create pause" '{}'
  [[ -f "$PAUSE_FLAG" ]]
  alert_unlock "test unlock reason"
  [[ ! -f "$PAUSE_FLAG" ]]
}

@test "alert_unlock logs the unlock reason" {
  source "$LIB"
  alert_emit panic "create lock" '{}'
  alert_unlock "operator confirmed resolution"
  grep -q "alert_unlock\|unlock\|operator confirmed" "$WALTER_ALERT_LOG"
}

# ---- tier validation ----

@test "alert_emit with unknown tier returns exit code 1" {
  source "$LIB"
  run alert_emit "unknown-tier" "message" '{}'
  [[ "$status" -ne 0 ]]
}

# ---- JSONL format ----

@test "alert log entries are valid JSON" {
  source "$LIB"
  alert_emit info "json test" '{"key":"value"}'
  # Each line of the log must be valid JSON
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" | jq . >/dev/null 2>&1
  done < "$WALTER_ALERT_LOG"
}

@test "alert log entry contains ts, tier, message, context fields" {
  source "$LIB"
  alert_emit warn "field test" '{"source":"bats"}'
  local entry; entry="$(tail -1 "$WALTER_ALERT_LOG")"
  echo "$entry" | jq -e '.ts' >/dev/null
  echo "$entry" | jq -e '.tier' >/dev/null
  echo "$entry" | jq -e '.message' >/dev/null
  echo "$entry" | jq -e '.context' >/dev/null
}

@test "F12 alert log jq fallback: multiline+tab message produces valid JSONL" {
  # F12: fallback path must escape newlines, tabs, and CR per JSON spec.
  local mock_dir; mock_dir="$(mktemp -d)"
  cat > "$mock_dir/jq" <<'JQ_FAIL'
#!/usr/bin/env bash
for arg in "$@"; do
  [[ "$arg" == "-nc" ]] && exit 1
done
exec /usr/bin/env jq "$@"
JQ_FAIL
  chmod +x "$mock_dir/jq"

  local orig_path="$PATH"
  export PATH="$mock_dir:$PATH"
  source "$LIB"
  export PATH="$orig_path"

  # Message with newline, tab, and CR — the chars the old fallback missed
  local msg
  msg="$(printf 'line one\nline two\there\r')"
  PATH="$mock_dir:$orig_path" alert_emit info "$msg" '{}'

  # Every line in the log must be parseable JSON
  local ok=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! echo "$line" | /usr/bin/env jq . >/dev/null 2>&1; then
      echo "Invalid JSON line: $line" >&3
      ok=1
    fi
  done < "$WALTER_ALERT_LOG"
  rm -rf "$mock_dir"
  [[ "$ok" -eq 0 ]]
}

@test "alert log jq fallback: message with quotes and backslashes produces valid JSONL" {
  # F9: override jq with a broken mock to force the fallback path,
  # then verify the fallback still produces parseable JSONL when
  # the message contains special characters.
  local mock_dir; mock_dir="$(mktemp -d)"
  # Write a jq mock that always fails (simulates jq unavailable)
  cat > "$mock_dir/jq" <<'JQ_FAIL'
#!/usr/bin/env bash
# If called with -nc (build JSON), fail. Pass through other calls.
for arg in "$@"; do
  [[ "$arg" == "-nc" ]] && exit 1
done
exec /usr/bin/env jq "$@"
JQ_FAIL
  chmod +x "$mock_dir/jq"

  local orig_path="$PATH"
  export PATH="$mock_dir:$PATH"
  source "$LIB"
  export PATH="$orig_path"

  # Message with quotes, backslashes — the dangerous chars
  local msg='say "hello" \ world'
  PATH="$mock_dir:$orig_path" alert_emit info "$msg" '{}'

  # Every line in the log must be parseable JSON
  local ok=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! echo "$line" | jq . >/dev/null 2>&1; then
      echo "Invalid JSON line: $line" >&3
      ok=1
    fi
  done < "$WALTER_ALERT_LOG"
  rm -rf "$mock_dir"
  [[ "$ok" -eq 0 ]]
}
