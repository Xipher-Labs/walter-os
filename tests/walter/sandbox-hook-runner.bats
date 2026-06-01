#!/usr/bin/env bats
# Runtime tests for the Walter-OS sandbox hook runner.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER="$REPO_ROOT/scripts/walter/sandbox-hook-runner.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_RUNTIME_DIR="$TMP_HOME/runtime"
  export HOOK_PAYLOAD_OUT="$TMP_HOME/hook-payload.json"
  export WALTER_PROVIDER_LOG="$TMP_HOME/provider.log"
  FAKE_BIN="$TMP_HOME/bin"
  HOOK="$TMP_HOME/test-hook.sh"
  mkdir -p "$HOME" "$WALTER_CONFIG" "$WALTER_RUNTIME_DIR" "$FAKE_BIN"
  cat > "$HOOK" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
cat > "$HOOK_PAYLOAD_OUT"
printf '%s\n' '{"decision":"allow","runner":"test-hook"}'
HOOK
  chmod +x "$HOOK"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_host_provider() {
  case "$(uname -s)" in
    Darwin) printf '%s\n' "sandbox-exec" ;;
    Linux) printf '%s\n' "nsjail" ;;
    *) printf '%s\n' "sandbox-exec" ;;
  esac
}

_write_fake_provider() {
  local provider="$1"
  cat > "$FAKE_BIN/$provider" <<'PROVIDER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$0 $*" >> "$WALTER_PROVIDER_LOG"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      exec "$@"
      ;;
    -f|--config)
      shift 2
      ;;
    --profile=*)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "fake provider: missing wrapped command" >&2
exit 99
PROVIDER
  chmod +x "$FAKE_BIN/$provider"
}

@test "#260 AC-4: sandbox hook runner executes hooks through walter_sandbox_run" {
  provider="$(_host_provider)"
  _write_fake_provider "$provider"

  run env PATH="$FAKE_BIN:$PATH" "$BASH" "$RUNNER" "$HOOK" <<< '{"tool_name":"Bash"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *'"runner":"test-hook"'* ]]
  [ "$(cat "$HOOK_PAYLOAD_OUT")" = '{"tool_name":"Bash"}' ]
  grep -q -- "$provider" "$WALTER_PROVIDER_LOG"
  grep -q -- "$HOOK" "$WALTER_PROVIDER_LOG"
}

@test "#260 AC-4: sandbox hook runner fails closed when sandbox is unavailable" {
  run env PATH="$FAKE_BIN" "$BASH" "$RUNNER" "$HOOK" <<< '{"tool_name":"Bash"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"sandbox unavailable"* ]]
  [ ! -f "$HOOK_PAYLOAD_OUT" ]
}

@test "#260 AC-4: sandbox bypass requires env var and --no-sandbox flag" {
  run env WALTER_SANDBOX_BYPASS=1 PATH="$FAKE_BIN" "$BASH" "$RUNNER" "$HOOK" <<< '{"tool_name":"Bash"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"requires WALTER_SANDBOX_BYPASS=1 and --no-sandbox"* ]]
  [ ! -f "$HOOK_PAYLOAD_OUT" ]
}

@test "#260 AC-4: two-factor sandbox bypass runs unsandboxed and records audit row" {
  run env WALTER_SANDBOX_BYPASS=1 PATH="$FAKE_BIN:$PATH" "$BASH" "$RUNNER" --no-sandbox "$HOOK" <<< '{"tool_name":"Bash"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *'"runner":"test-hook"'* ]]
  [ "$(cat "$HOOK_PAYLOAD_OUT")" = '{"tool_name":"Bash"}' ]
  [ ! -f "$WALTER_PROVIDER_LOG" ]
  [ -f "$WALTER_CONFIG/sandbox-bypass.jsonl" ]
  jq -e \
    'select(.decision_source == "operator-sandbox-bypass" and .profile == "walter-hook-default" and (.hook | endswith("test-hook.sh")))' \
    "$WALTER_CONFIG/sandbox-bypass.jsonl"
}
