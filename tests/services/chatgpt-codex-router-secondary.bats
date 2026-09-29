#!/usr/bin/env bats
# Static coverage for the secondary ChatGPT account router
# (chatgpt-codex-router-solx) and the LiteLLM deployments that load-balance
# across both Codex routers.
# Refs: docs/specs/codex-router-secondary-account.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_DIR="$REPO_ROOT/setup/walter-host/services/chatgpt-codex-router"
  BASE_COMPOSE="$ROUTER_DIR/docker-compose.yml"
  SOLX_COMPOSE="$ROUTER_DIR/docker-compose.solx.yml"
  LITELLM_CONFIG="$REPO_ROOT/setup/walter-host/services/litellm/config.yaml"
  LITELLM_COMPOSE="$REPO_ROOT/setup/walter-host/services/litellm/compose.yml"
  PORT_MAP="$REPO_ROOT/setup/walter-host/ports.tsv"
  WATCHDOG="$REPO_ROOT/setup/walter-host/services/alerting/ai-stack-watchdog.sh"
  RUNBOOK="$ROUTER_DIR/RUNBOOK.md"
  ENV_TEMPLATE="$ROUTER_DIR/.env.template"
}

solx_block() {
  awk '
    /^  chatgpt-codex-router-solx:/ { flag=1; next }
    flag && /^  [a-zA-Z0-9_-]+:/ { flag=0 }
    flag && /^[a-z]/ { flag=0 }
    flag { print }
  ' "$SOLX_COMPOSE"
}

@test "AC-1: secondary router compose override defines chatgpt-codex-router-solx" {
  [[ -f "$SOLX_COMPOSE" ]]
  solx_block | grep -Fxq "    container_name: chatgpt-codex-router-solx"
  solx_block | grep -Fxq "    build: ."
}

@test "AC-1: secondary router reads its own key, fail-loud" {
  solx_block | grep -Fq 'CCR_APIKEY: "${CCR_SOLX_APIKEY:?'
  run grep -E 'CCR_SOLX_APIKEY:-' "$SOLX_COMPOSE"
  [ "$status" -ne 0 ]
}

@test "AC-1: secondary router mounts the second Codex home, not ~/.codex" {
  solx_block | grep -Fq -- '- ${CODEX_SOLX_HOME:-${HOME}/.codex-solx}:/home/appuser/.codex:rw'
  local block
  block="$(solx_block)"
  [[ "$block" != *'${HOME}/.codex:'* ]]
}

@test "AC-1: secondary router publishes 127.0.0.1:1459 on the LiteLLM network" {
  solx_block | grep -Fq -- '- "127.0.0.1:1459:1456"'
  solx_block | grep -Fq -- '- litellm_net'
  grep -Fq 'name: litellm_default' "$SOLX_COMPOSE"
}

@test "AC-1: secondary router keeps the router resource limits and probes" {
  solx_block | grep -Fxq '    mem_limit: "${CHATGPT_CODEX_ROUTER_SOLX_MEM_LIMIT:-512m}"'
  solx_block | grep -Fxq '    mem_reservation: "${CHATGPT_CODEX_ROUTER_SOLX_MEM_RESERVATION:-256m}"'
  solx_block | grep -Fxq '    cpus: "${CHATGPT_CODEX_ROUTER_SOLX_CPUS:-1.0}"'
  solx_block | grep -Fxq '    pids_limit: "${CHATGPT_CODEX_ROUTER_SOLX_PIDS_LIMIT:-256}"'
  solx_block | grep -Fq 'ROUTER_STARTUP_MODEL_PROBE: "${ROUTER_STARTUP_MODEL_PROBE:-1}"'
  solx_block | grep -Fq 'test: ["CMD", "curl", "-fsS", "http://localhost:1456/health"]'
}

@test "AC-1: base plus override renders without a 1456 host-port collision" {
  if [ "${WALTER_COMPOSE_TEST:-0}" != "1" ]; then
    skip "set WALTER_COMPOSE_TEST=1 to run docker compose render checks"
  fi
  command -v docker >/dev/null 2>&1 || skip "docker is not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose is not available"

  run env CCR_APIKEY=test CCR_SOLX_APIKEY=test2 docker compose \
    --project-directory "$ROUTER_DIR" -f "$BASE_COMPOSE" -f "$SOLX_COMPOSE" config --format json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
svc = cfg["services"]
assert "chatgpt-codex-router" in svc and "chatgpt-codex-router-solx" in svc
pub = [p.get("published") for p in svc["chatgpt-codex-router-solx"]["ports"]]
assert pub == ["1459"], pub
assert svc["chatgpt-codex-router-solx"]["environment"]["CCR_APIKEY"] == "test2"
'
}

@test "AC-2: ports.tsv registers the secondary router on 1459" {
  grep -q $'^chatgpt-codex-router-solx\tapi\t1459\t1456\ttcp\tlocalhost\tstandalone/chatgpt-codex-router\t' "$PORT_MAP"
}

@test "AC-3: every primary Codex deployment has a secondary-account twin" {
  run python3 - "$LITELLM_CONFIG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
primary = "http://chatgpt-codex-router:1456/v1"
secondary = "http://chatgpt-codex-router-solx:1456/v1"
deps = cfg["model_list"]
def key(d):
    p = d["litellm_params"]
    return (d["model_name"], p["model"])
prim = {key(d): d for d in deps if d["litellm_params"].get("api_base") == primary}
sec = {key(d): d for d in deps if d["litellm_params"].get("api_base") == secondary}
assert prim, "no primary codex deployments"
missing = sorted(set(prim) - set(sec))
extra = sorted(set(sec) - set(prim))
assert not missing, f"missing secondary twin: {missing}"
assert not extra, f"secondary without primary: {extra}"
for k, d in prim.items():
    assert d["litellm_params"]["api_key"] == "os.environ/CCR_APIKEY", k
for k, d in sec.items():
    assert d["litellm_params"]["api_key"] == "os.environ/CCR_SOLX_APIKEY", k
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "AC-3: walter-host LiteLLM config has no literal api_key values" {
  run python3 - "$LITELLM_CONFIG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
bad = [d["model_name"] for d in cfg["model_list"]
       if "api_key" in d["litellm_params"]
       and not str(d["litellm_params"]["api_key"]).startswith("os.environ/")]
assert not bad, bad
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "AC-4: router_settings cool down failing deployments but not prompt errors" {
  run python3 - "$LITELLM_CONFIG" <<'PY'
import sys, yaml
rs = yaml.safe_load(open(sys.argv[1]))["router_settings"]
assert rs["allowed_fails"] == 3, rs.get("allowed_fails")
assert rs["cooldown_time"] == 300, rs.get("cooldown_time")
pol = rs["allowed_fails_policy"]
assert pol["ContentPolicyViolationErrorAllowedFails"] == 1000
assert pol["BadRequestErrorAllowedFails"] == 1000
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "AC-3: LiteLLM compose passes the secondary router key through" {
  grep -Fq 'CCR_SOLX_APIKEY: ${CCR_SOLX_APIKEY:-}' "$LITELLM_COMPOSE"
}

@test "AC-5: watchdog probes each Codex account router directly" {
  grep -Fq '"chatgpt-codex-router"' "$WATCHDOG"
  grep -Fq '"chatgpt-codex-router-solx"' "$WATCHDOG"
  grep -q 'ACCOUNT_PROBE_ROUTERS=' "$WATCHDOG"
  grep -q 'CODEX_ACCOUNT_PROBE_MODEL' "$WATCHDOG"
}

@test "AC-5: account probes skip absent routers and never restart on exhaustion" {
  run awk '
    /^# ---------- 4\. Per-account Codex router probe/ { flag=1 }
    flag && /docker restart/ { bad=1 }
    flag && /docker inspect/ { inspect=1 }
    END { exit !(flag && inspect && !bad) }
  ' "$WATCHDOG"
  [ "$status" -eq 0 ]
}

@test "AC-5: account probe keeps the router key inside the container" {
  run awk '
    /^# ---------- 4\. Per-account Codex router probe/ { flag=1 }
    flag && /docker exec/ { exec_seen=1 }
    flag && exec_seen && /sh -c \047.*Bearer \$CCR_APIKEY/ { found=1 }
    END { exit !found }
  ' "$WATCHDOG"
  [ "$status" -eq 0 ]
}

@test "AC-6: RUNBOOK documents account-exhaustion diagnosis" {
  grep -Fq "codex exec --skip-git-repo-check -m gpt-6-luna" "$RUNBOOK"
  grep -Fq "codex_error" "$RUNBOOK"
  grep -Fq "id_token" "$RUNBOOK"
  grep -Fq "chatgpt-codex-router-solx" "$RUNBOOK"
}

@test "AC-6: env template documents the secondary router key" {
  grep -q '^CCR_SOLX_APIKEY=$' "$ENV_TEMPLATE"
  grep -q 'COMPOSE_FILE=docker-compose.yml:docker-compose.solx.yml' "$ENV_TEMPLATE"
}
