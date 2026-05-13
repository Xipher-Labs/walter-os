#!/usr/bin/env bash
# scripts/agents/lib/alerts.sh — Unified alert emission for Walter Council.
# Sourced (not exec'd) by agent runner, watchdog, and any script that needs
# to emit alerts to the operator.
#
# Alert tiers:
#   info     — JSONL log only (silent)
#   warn     — log + Telegram [WARN]
#   critical — log + Telegram [CRITICAL] + TOWER_CRITICAL_FLAG
#   panic    — log + Telegram + email + pause flag + gate.lock (blocks ALL ops)
#
# alert_unlock <reason> — used by `walter-os agents unlock`. Removes gate.lock
#   and pause flag, logs the reason.
#
# All log entries written to WALTER_ALERT_LOG in JSONL format:
#   {"ts": "...", "tier": "...", "message": "...", "context": {...}}
#
# Spec: docs/specs/walter-council-v2.md — Improvement 8 (T-8)
# Refs: T-8

# shellcheck disable=SC2034
WALTER_ALERTS_LIB_VERSION=1

# Config — all override-able via env for tests.
WALTER_ALERT_LOG="${WALTER_ALERT_LOG:-/var/log/walter-council/events.log}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
PAUSE_FLAG="${PAUSE_FLAG:-${WALTER_CONFIG}/agents.paused}"
TOWER_CRITICAL_FLAG="${TOWER_CRITICAL_FLAG:-${WALTER_CONFIG}/tower-critical.flag}"
GATE_LOCK="${GATE_LOCK:-${WALTER_CONFIG}/gate.lock}"

# _alert_log <tier> <message> <context_json> — write JSONL entry to log.
_alert_log() {
  local tier="$1" message="$2" context_json="${3:-{}}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local log_dir; log_dir="$(dirname "$WALTER_ALERT_LOG")"
  [[ -d "$log_dir" ]] || mkdir -p "$log_dir"

  local entry
  entry="$(jq -nc \
    --arg ts "$ts" \
    --arg tier "$tier" \
    --arg message "$message" \
    --argjson context "$context_json" \
    '{ts: $ts, tier: $tier, message: $message, context: $context}' 2>/dev/null)" || true
  if [[ -z "$entry" ]]; then
    # jq unavailable or failed — build minimal JSONL with fully JSON-escaped message.
    # Use python3 json.dumps for complete spec compliance (covers \n, \r, \t, control chars).
    local escaped_msg
    if command -v python3 >/dev/null 2>&1; then
      escaped_msg="$(printf '%s' "$message" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")"
    else
      # Bash-only fallback: escape all JSON special chars per RFC 8259.
      local s="${message//\\/\\\\}"   # backslash first
      s="${s//\"/\\\"}"               # double-quote
      s="${s//$'\n'/\\n}"             # newline
      s="${s//$'\r'/\\r}"             # carriage return
      s="${s//$'\t'/\\t}"             # tab
      # Drop remaining control chars 0x00-0x1F (except the above, already handled)
      s=$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
      escaped_msg="\"${s}\""
    fi
    entry="$(printf '{"ts":"%s","tier":"%s","message":%s,"context":{}}' \
      "$ts" "$tier" "$escaped_msg")"
  fi
  printf '%s\n' "$entry" >> "$WALTER_ALERT_LOG"
}

# _alert_telegram <prefix> <message> — send Telegram notification.
# Uses WALTER_TELEGRAM_BOT_TOKEN and WALTER_TELEGRAM_CHAT_ID.
# Silently skips if credentials not set.
_alert_telegram() {
  local prefix="$1" message="$2"
  local token="${WALTER_TELEGRAM_BOT_TOKEN:-}"
  local chat="${WALTER_TELEGRAM_CHAT_ID:-}"
  [[ -z "$token" || -z "$chat" ]] && return 0

  local text="${prefix} ${message}"
  curl -fsS -m 15 \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" \
    --data-urlencode "text=${text}" \
    >/dev/null 2>&1 || true
}

# _alert_email <tier> <message> — send email via sendmail or msmtp.
# Silently skips if neither is available.
_alert_email() {
  local tier="$1" message="$2"
  local to="${WALTER_ALERT_EMAIL:-}"
  local subject="[Walter Council PANIC] ${message:0:80}"
  local body
  body="Tier: ${tier}\nMessage: ${message}\nTimestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if command -v msmtp >/dev/null 2>&1 && [[ -n "$to" ]]; then
    printf "To: %s\nSubject: %s\n\n%b\n" "$to" "$subject" "$body" \
      | msmtp "$to" >/dev/null 2>&1 || true
  elif command -v sendmail >/dev/null 2>&1 && [[ -n "$to" ]]; then
    printf "To: %s\nSubject: %s\n\n%b\n" "$to" "$subject" "$body" \
      | sendmail -t >/dev/null 2>&1 || true
  fi
}

# alert_emit <tier> <message> <context_json> — emit alert at the given tier.
# Tier must be one of: info, warn, critical, panic.
# Returns exit 1 for unknown tiers.
alert_emit() {
  local tier="$1" message="$2" context_json="${3:-{}}"

  case "$tier" in
    info)
      _alert_log "info" "$message" "$context_json"
      ;;

    warn)
      _alert_log "warn" "$message" "$context_json"
      _alert_telegram "[WARN]" "$message"
      ;;

    critical)
      _alert_log "critical" "$message" "$context_json"
      _alert_telegram "[CRITICAL]" "$message"
      # Signal the Control Tower that a critical event occurred.
      mkdir -p "$(dirname "$TOWER_CRITICAL_FLAG")"
      printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) $message" >> "$TOWER_CRITICAL_FLAG"
      ;;

    panic)
      _alert_log "panic" "$message" "$context_json"
      _alert_telegram "[PANIC]" "$message"
      _alert_email "panic" "$message"
      # Create pause flag — stops new agent run-once invocations.
      mkdir -p "$(dirname "$PAUSE_FLAG")"
      date -u +%Y-%m-%dT%H:%M:%SZ > "$PAUSE_FLAG"
      # Create gate.lock — blocks ALL approval-gate decisions.
      mkdir -p "$(dirname "$GATE_LOCK")"
      printf '%s\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" > "$GATE_LOCK"
      # Also create critical flag for Tower.
      mkdir -p "$(dirname "$TOWER_CRITICAL_FLAG")"
      printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) [PANIC] $message" >> "$TOWER_CRITICAL_FLAG"
      ;;

    *)
      echo "alerts.sh: unknown tier '$tier'. Must be one of: info, warn, critical, panic" >&2
      return 1
      ;;
  esac
}

# alert_unlock <reason> — remove gate.lock and pause flag.
# Called by `walter-os agents unlock --reason "..."`.
alert_unlock() {
  local reason="${1:-no reason given}"

  rm -f "$GATE_LOCK"
  rm -f "$PAUSE_FLAG"

  _alert_log "info" "alert_unlock: panic lock cleared by operator" \
    "$(jq -nc --arg reason "$reason" '{event:"alert_unlock", reason:$reason}')"

  echo "alerts.sh: gate.lock removed. Reason: $reason"
}
