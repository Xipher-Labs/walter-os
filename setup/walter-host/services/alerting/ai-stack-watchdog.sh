#!/usr/bin/env bash
# ai-stack-watchdog.sh — self-repair + alerting for the Walter-VM AI stack
# (LiteLLM gateway + its Postgres + the sub-account routers).
#
# WHY THIS EXISTS: on 2026-06-02 LiteLLM's dedicated Postgres (`litellm-db`)
# exhausted its connection slots ("too many clients already"). LiteLLM
# crash-looped on startup but the container still showed `Up` (it had NO
# healthcheck), so Docker never restarted it. The whole AI pipeline was dead
# for 4 days, undetected. A plain healthcheck/autoheal would NOT have caught
# it either: `litellm-db` stayed "healthy" (pg_isready passed) while refusing
# real connections, and a wedged sub-router can be "healthy" while returning
# 502 for a specific model. So this watchdog probes ACTUAL FUNCTION and heals.
#
# Checks (each self-heals THEN alerts, debounced via state transitions):
#   1. LiteLLM liveliness   — GET /health/liveliness; heal = restart db+litellm
#   2. litellm-db saturation — pg_stat_activity vs max_connections; heal = restart
#   3. Per-model probe       — claude-sub-haiku / gemini-sub / codex-sub via the
#                              gateway; heal = restart the matching sub-router
#
# Runs every 5 min via cron (see cron.example). Reuses the Telegram config of
# walter-vm-watchdog.sh.
#
# Install:
#   sudo cp ai-stack-watchdog.sh /opt/walter-vm/services/alerting/
#   sudo chmod +x /opt/walter-vm/services/alerting/ai-stack-watchdog.sh
#   sudo crontab -e  # add the ai-stack line from cron.example
#
# Env required (/etc/walter-vm/alerting.env):
#   WALTER_TELEGRAM_BOT_TOKEN, WALTER_TELEGRAM_CHAT_ID

set -euo pipefail

ENV_FILE="${WALTER_ALERTING_ENV:-/etc/walter-vm/alerting.env}"
STATE_FILE="${WALTER_AI_WATCHDOG_STATE:-/var/run/walter-ai-watchdog.state}"
LITELLM_URL="${LITELLM_LOCAL_URL:-http://127.0.0.1:4000}"
DB_SAT_PCT="${LITELLM_DB_SAT_PCT:-85}"   # restart db when used connections exceed this % of max
# Models to probe → the sub-router container that serves them.
# Format: "model_alias:router_container"
PROBES=(
  "claude-sub-haiku:claude-sub-router"
  "gemini-sub:gemini-sub-router"
  "codex-sub:chatgpt-codex-router"
)
MODEL_TIMEOUT="${LITELLM_MODEL_PROBE_TIMEOUT:-50}"  # gemini-sub legitimately takes ~35s
LITELLM_RESTART_SETTLE_SECONDS="${LITELLM_RESTART_SETTLE_SECONDS:-20}"
TELEGRAM_CONNECT_TIMEOUT="${WALTER_TELEGRAM_CONNECT_TIMEOUT:-5}"
TELEGRAM_MAX_TIME="${WALTER_TELEGRAM_MAX_TIME:-15}"

[[ -f "$ENV_FILE" ]] || { echo "missing env: $ENV_FILE"; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"
[[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]] || {
  echo "WALTER_TELEGRAM_{BOT_TOKEN,CHAT_ID} required"; exit 2; }

notify() {
  if ! curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
    --connect-timeout "$TELEGRAM_CONNECT_TIMEOUT" \
    --max-time "$TELEGRAM_MAX_TIME" \
    -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" -d "parse_mode=Markdown" >/dev/null; then
    echo "ai-stack-watchdog: Telegram notification failed" >&2
    return 1
  fi
}
state_get() { [[ -f "$STATE_FILE" ]] && (grep -E "^${1}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2) || echo "0"; }
state_set() {
  mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"
  if grep -qE "^${1}=" "$STATE_FILE"; then sed -i "s/^${1}=.*/${1}=${2}/" "$STATE_FILE"
  else echo "${1}=${2}" >> "$STATE_FILE"; fi
}
# 0→1 alerts a problem (after healing), 1→0 alerts recovery. Debounced.
transition() {
  local key="$1" cur="$2" alert="$3" recover="$4" prev
  prev=$(state_get "$key")
  if [[ "$cur" == "1" && "$prev" == "0" ]]; then notify "🚨 *Walter-VM AI*: $alert" && state_set "$key" 1
  elif [[ "$cur" == "0" && "$prev" == "1" ]]; then notify "✅ *Walter-VM AI*: $recover" && state_set "$key" 0; fi
}

# Run a command as root whether the watchdog runs as root (cron in /etc/cron.d)
# or as walter (needs NOPASSWD sudo for the specific systemctl commands).
as_root() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo -n "$@"; fi; }

# ---------- 0. cloudflared tunnel (MUST be first — if down, everything 530s) ----------
# The 2026-06-06 outage: cloudflared stayed `active` (process alive) but
# UNREGISTERED from the Argo Tunnel → origin 530 "origin has been unregistered
# from Argo Tunnel" for authenticated traffic, and SSH-over-Access bad-handshake.
# A plain `systemctl is-active` does NOT catch this (process is up). So probe
# the metrics /ready endpoint when exposed, else scan recent logs for an
# unrecovered disconnect. This check runs LOCALLY on the VM, so it can restart
# cloudflared even while the tunnel is down; Telegram alerts go direct (not via
# the tunnel), so they get out regardless.
cf_healthy() {
  # Preferred: cloudflared --metrics endpoint; /ready is 200 with
  # readyConnections>0 only when at least one tunnel connection is registered.
  if [[ -n "${CLOUDFLARED_METRICS:-}" ]] \
     && curl -s --max-time 5 "http://${CLOUDFLARED_METRICS}/ready" 2>/dev/null \
        | grep -q '"readyConnections":[1-9]'; then
    return 0
  fi
  # Fallback: must be active AND not show an unrecovered disconnect in the
  # last 3 min (errors are OK if a re-registration followed them).
  systemctl is-active --quiet cloudflared || return 1
  local bad good
  bad=$(journalctl -u cloudflared --since "3 min ago" --no-pager 2>/dev/null \
        | grep -ciE "unregistered tunnel|lost connection|failed to (dial|serve|connect)|register tunnel.*error" || true)
  good=$(journalctl -u cloudflared --since "3 min ago" --no-pager 2>/dev/null \
         | grep -ciE "registered tunnel connection|connection.*registered" || true)
  [[ "${bad:-0}" -eq 0 || "${good:-0}" -gt 0 ]]
}
if ! cf_healthy; then
  as_root systemctl restart cloudflared >/dev/null 2>&1 || true
  sleep 12
  if cf_healthy; then cfst=0; else cfst=1; fi
  transition "cloudflared_down" "1" \
    "cloudflared tunnel down/unregistered → auto-restarted ($([ $cfst -eq 0 ] && echo recovered || echo STILL DOWN — needs Hetzner console)). Symptom: 530 'origin unregistered' + SSH bad-handshake; takes down ALL tunnelled services + the AI pipeline." \
    "cloudflared tunnel healthy again"
  [[ $cfst -eq 0 ]] && state_set "cloudflared_down" 0
  # If still down, the gateway probes below will all fail — skip them this cycle.
  [[ $cfst -ne 0 ]] && { echo "ai-stack-watchdog: cloudflared still down ($(date -u +%FT%TZ))"; exit 0; }
else
  transition "cloudflared_down" "0" "" "cloudflared tunnel healthy again"
fi

# ---------- 1. LiteLLM liveliness ----------
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${LITELLM_URL}/health/liveliness" 2>/dev/null || echo 000)
if [[ "$code" != "200" ]]; then
  # Heal: the recurring root cause is litellm-db connection exhaustion, so
  # restart the DB first (clears stuck connections), then litellm.
  docker restart litellm-db >/dev/null 2>&1 || true
  sleep 8
  docker restart litellm >/dev/null 2>&1 || true
  sleep "$LITELLM_RESTART_SETTLE_SECONDS"
  code2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${LITELLM_URL}/health/liveliness" 2>/dev/null || echo 000)
  [[ "$code2" == "200" ]] && healed="recovered after auto-restart (db+litellm)" || healed="STILL DOWN after auto-restart — manual intervention needed"
  transition "litellm_down" "1" \
    "LiteLLM /health was \`$code\` → auto-restarted db+litellm; $healed" \
    "LiteLLM healthy again"
  # Keep litellm_down=1 after a heal so the next healthy run emits recovery.
  # Don't run model probes this cycle if the gateway is down.
  [[ "$code2" != "200" ]] && exit 0
else
  transition "litellm_down" "0" "" "LiteLLM healthy again"
fi

# ---------- 2. litellm-db connection saturation ----------
used=$(docker exec litellm-db psql -U litellm -d litellm -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' \n' || true)
max=$(docker exec litellm-db psql -U litellm -d litellm -tAc "SELECT setting FROM pg_settings WHERE name='max_connections';" 2>/dev/null | tr -d ' \n' || true)
if [[ "${used:-}" =~ ^[0-9]+$ && "${max:-}" =~ ^[0-9]+$ && "$max" -gt 0 ]]; then
  pct=$(( used * 100 / max ))
  if [[ "$pct" -ge "$DB_SAT_PCT" ]]; then
    docker restart litellm-db >/dev/null 2>&1 || true; sleep 8
    docker restart litellm   >/dev/null 2>&1 || true
    sleep "$LITELLM_RESTART_SETTLE_SECONDS"
    code_after_db_restart=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${LITELLM_URL}/health/liveliness" 2>/dev/null || echo 000)
    transition "db_saturated" "1" \
      "litellm-db at ${used}/${max} conns (${pct}% ≥ ${DB_SAT_PCT}%) → auto-restarted db+litellm (pre-empts the 2026-06-02 outage)" \
      "litellm-db connections back to normal"
    if [[ "$code_after_db_restart" != "200" ]]; then
      transition "litellm_down" "1" \
        "LiteLLM /health is \`$code_after_db_restart\` after db saturation restart; skipping model probes this cycle" \
        "LiteLLM healthy again"
      exit 0
    fi
  else
    transition "db_saturated" "0" "" "litellm-db connections back to normal (${used}/${max})"
  fi
fi

# ---------- 3. Per-model functional probe ----------
# Uses the gateway master key, read inside the litellm container so the secret
# never lands on the host. Probes each model; on failure restarts its router.
for entry in "${PROBES[@]}"; do
  model="${entry%%:*}"; router="${entry##*:}"
  key="model_${model//[^a-zA-Z0-9]/_}"
  probe_result=$(docker exec -e M="$model" -e T="$MODEL_TIMEOUT" litellm sh -c 'set -a; . /run/secrets/litellm.env 2>/dev/null; set +a; python3 - <<PY 2>/dev/null
import os,json,urllib.request as u
k=os.environ.get("LITELLM_MASTER_KEY","")
if not k:
    print("missing_key")
    raise SystemExit(0)
req=u.Request("http://127.0.0.1:4000/v1/chat/completions",method="POST",
  headers={"Authorization":"Bearer "+k,"Content-Type":"application/json"},
  data=json.dumps({"model":os.environ["M"],"messages":[{"role":"user","content":"ping"}],"max_tokens":5}).encode())
try:
    with u.urlopen(req,timeout=int(os.environ["T"])) as r:
        print("1" if r.status==200 else "0")
except Exception:
    print("0")
PY' 2>/dev/null | tr -d ' \n' || true)
  if [[ "$probe_result" == "missing_key" ]]; then
    transition "litellm_master_key_missing" "1" \
      "LiteLLM master key is empty inside \`litellm\`; model probes skipped; fix \`LITELLM_MASTER_KEY\` in the LiteLLM service environment before restarting routers" \
      "LiteLLM master key available again"
    continue
  fi
  transition "litellm_master_key_missing" "0" "" "LiteLLM master key available again"
  if [[ "$probe_result" != "1" ]]; then
    prev_model_state=$(state_get "$key")
    if [[ "$prev_model_state" == "0" ]]; then
      docker restart "$router" >/dev/null 2>&1 || true
    fi
    transition "$key" "1" \
      "model \`$model\` probe FAILED → auto-restarted \`$router\`. If it persists it is likely a config/auth issue (e.g. wrong upstream model slug), not a crash — check \`docker logs $router\`." \
      "model \`$model\` healthy again"
  else
    transition "$key" "0" "" "model \`$model\` healthy again"
  fi
done

echo "ai-stack-watchdog ok ($(date -u +%FT%TZ))"
