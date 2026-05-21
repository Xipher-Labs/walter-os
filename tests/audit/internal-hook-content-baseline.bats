#!/usr/bin/env bats
# tests/audit/internal-hook-content-baseline.bats
#
# Covers AC1, AC6 of docs/specs/audit-hook-content-hashing.md:
#   AC1: walter-os baseline-hooks writes v2 hook-checksums.json with
#        content SHA256 for each hook registered in settings.json.
#   AC6: two consecutive baseline-hooks runs against unchanged input
#        produce byte-identical output (deterministic).

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  command -v sha256sum >/dev/null 2>&1 \
    || command -v shasum >/dev/null 2>&1 \
    || skip "sha256sum/shasum required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  [[ -x "$WALTER_OS_BIN" ]] || skip "bin/walter-os missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export CLAUDE_HOME="$TMP_HOME/.claude"
  export CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
  mkdir -p "$WALTER_CONFIG" "$CLAUDE_HOME"

  # Sandbox hook script.
  mkdir -p "$TMP_HOME/hooks"
  HOOK_PATH="$TMP_HOME/hooks/sample-hook.sh"
  cat > "$HOOK_PATH" <<'SH'
#!/usr/bin/env bash
echo '{"decision":"allow"}'
SH
  chmod +x "$HOOK_PATH"

  # settings.json with one hook
  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "command": "$HOOK_PATH" }
    ]
  }
}
EOF
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# -----------------------------------------------------------------------
# AC1: baseline-hooks writes v2 schema with content sha256
# -----------------------------------------------------------------------
@test "AC1: baseline-hooks writes v2 schema" {
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  [ -f "$WALTER_CONFIG/hook-checksums.json" ]
  run jq -r '.version' "$WALTER_CONFIG/hook-checksums.json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "AC1: baseline-hooks records command, path, and sha256 per hook" {
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  run jq -r '.hooks[0] | "\(.command)|\(.path)|\(.sha256 | length)"' "$WALTER_CONFIG/hook-checksums.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "${HOOK_PATH}|${HOOK_PATH}|64" ]]
}

@test "AC1: sha256 in baseline matches actual file hash" {
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  stored=$(jq -r '.hooks[0].sha256' "$WALTER_CONFIG/hook-checksums.json")
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$HOOK_PATH" | awk '{print $1}')
  else
    actual=$(shasum -a 256 "$HOOK_PATH" | awk '{print $1}')
  fi
  [ "$stored" = "$actual" ]
}

# -----------------------------------------------------------------------
# AC6: idempotency — two consecutive runs produce identical output
# -----------------------------------------------------------------------
@test "AC6: baseline-hooks is byte-identically idempotent" {
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  cp "$WALTER_CONFIG/hook-checksums.json" "$WALTER_CONFIG/hook-checksums.first.json"
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  diff -q "$WALTER_CONFIG/hook-checksums.json" "$WALTER_CONFIG/hook-checksums.first.json"
}
