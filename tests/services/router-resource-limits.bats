#!/usr/bin/env bats
# Static coverage for subscription-router per-container resource limits.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
}

assert_router_limits() {
  local router="$1"
  local compose="$ROUTER_ROOT/$router/docker-compose.yml"

  [[ -f "$compose" ]]

  python3 - "$compose" "$router" <<'PY'
import sys
import yaml

compose_path, router = sys.argv[1], sys.argv[2]
with open(compose_path, "r", encoding="utf-8") as fh:
    compose = yaml.safe_load(fh)

service = compose["services"][router]
for key in ("mem_limit", "mem_reservation", "cpus", "pids_limit"):
    assert key in service, f"{router} missing {key}"
    assert service[key] not in ("", None), f"{router} has empty {key}"
PY
}

@test "chatgpt-codex-router has resource limits" {
  assert_router_limits "chatgpt-codex-router"
  grep -q 'CHATGPT_CODEX_ROUTER_MEM_LIMIT:-512m' "$ROUTER_ROOT/chatgpt-codex-router/docker-compose.yml"
}

@test "claude-sub-router has resource limits" {
  assert_router_limits "claude-sub-router"
  grep -q 'CLAUDE_SUB_ROUTER_MEM_LIMIT:-512m' "$ROUTER_ROOT/claude-sub-router/docker-compose.yml"
}

@test "gemini-sub-router has resource limits" {
  assert_router_limits "gemini-sub-router"
  grep -q 'GEMINI_SUB_ROUTER_MEM_LIMIT:-512m' "$ROUTER_ROOT/gemini-sub-router/docker-compose.yml"
}
