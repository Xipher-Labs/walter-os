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
#   crontab -e  # add the ai-stack line from cron.example
#
# Env required (/etc/walter-vm/alerting.env):
#   WALTER_TELEGRAM_BOT_TOKEN, WALTER_TELEGRAM_CHAT_ID

set -uo pipefail

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

[[ -f "$ENV_FILE" ]] || { echo "missing env: $ENV_FILE"; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"
[[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]] || {
  echo "WALTER_TELEGRAM_{BOT_TOKEN,CHAT_ID} required"; exit 2; }

notify() {
  curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" -d "parse_mode=Markdown" >/dev/null || true
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
  if [[ "$cur" == "1" && "$prev" == "0" ]]; then notify "🚨 *Walter-VM AI*: $alert"; state_set "$key" 1
  elif [[ "$cur" == "0" && "$prev" == "1" ]]; then notify "✅ *Walter-VM AI*: $recover"; state_set "$key" 0; fi
}

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
used=$(docker exec litellm-db psql -U litellm -d litellm -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' \n')
max=$(docker exec litellm-db psql -U litellm -d litellm -tAc "SELECT setting FROM pg_settings WHERE name='max_connections';" 2>/dev/null | tr -d ' \n')
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
PY' 2>/dev/null | tr -d ' \n')
  if [[ "$probe_result" == "missing_key" ]]; then
    transition "${key}_auth" "1" \
      "model \`$model\` probe skipped because LiteLLM master key is empty inside \`litellm\`; fix \`/run/secrets/litellm.env\` before restarting routers" \
      "model \`$model\` LiteLLM master key available again"
    continue
  fi
  transition "${key}_auth" "0" "" "model \`$model\` LiteLLM master key available again"
  if [[ "$probe_result" != "1" ]]; then
    docker restart "$router" >/dev/null 2>&1 || true
    transition "$key" "1" \
      "model \`$model\` probe FAILED → auto-restarted \`$router\`. If it persists it is likely a config/auth issue (e.g. wrong upstream model slug), not a crash — check \`docker logs $router\`." \
      "model \`$model\` healthy again"
  else
    transition "$key" "0" "" "model \`$model\` healthy again"
  fi
done

echo "ai-stack-watchdog ok ($(date -u +%FT%TZ))"
