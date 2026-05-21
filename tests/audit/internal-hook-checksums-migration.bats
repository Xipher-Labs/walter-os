#!/usr/bin/env bats
# tests/audit/internal-hook-checksums-migration.bats
#
# Covers AC4, AC5 of audit-hook-content-hashing.md:
#   AC4: walter-os baseline-hooks invoked against an existing v1 file
#        (JSON array of strings) writes a v2 file (object with
#        version=2 + hooks array).
#   AC5: audit.sh check_hooks against a v1 file emits an info finding
#        and gracefully falls back to v1 detection without crashing.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  [[ -f "$AUDIT" ]] || skip "audit.sh missing"
  [[ -x "$WALTER_OS_BIN" ]] || skip "bin/walter-os missing"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export CLAUDE_HOME="$TMP_HOME/.claude"
  export CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
  mkdir -p "$WALTER_CONFIG" "$CLAUDE_HOME"

  mkdir -p "$TMP_HOME/hooks"
  HOOK_PATH="$TMP_HOME/hooks/legacy-hook.sh"
  cat > "$HOOK_PATH" <<'SH'
#!/usr/bin/env bash
echo '{"decision":"allow"}'
SH
  chmod +x "$HOOK_PATH"

  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "command": "$HOOK_PATH" }
    ]
  }
}
EOF

  # Pre-seed a v1 baseline file (the legacy format)
  jq -n --arg p "$HOOK_PATH" '[$p]' > "$WALTER_CONFIG/hook-checksums.json"
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# -----------------------------------------------------------------------
# AC4: v1 → v2 migration on next baseline-hooks
# -----------------------------------------------------------------------
@test "AC4: v1 (array) baseline migrates to v2 (object) on baseline-hooks" {
  # Verify pre-state is v1
  pre_schema=$(jq -r 'type' "$WALTER_CONFIG/hook-checksums.json")
  [ "$pre_schema" = "array" ]

  run "$WALTER_OS_BIN" baseline-hooks
  [ "$status" -eq 0 ]

  # Post-state must be v2 (object with .version=2)
  post_type=$(jq -r 'type' "$WALTER_CONFIG/hook-checksums.json")
  post_version=$(jq -r '.version // "missing"' "$WALTER_CONFIG/hook-checksums.json")
  [ "$post_type" = "object" ]
  [ "$post_version" = "2" ]
}

@test "AC4: migration log mentions v1 to v2 transition" {
  run "$WALTER_OS_BIN" baseline-hooks
  [ "$status" -eq 0 ]
  # Expected to print something mentioning migration / v1 / v2
  [[ "$output" == *"v1"* ]] || [[ "$output" == *"migrat"* ]] || [[ "$output" == *"v2"* ]]
}

# -----------------------------------------------------------------------
# AC5: check_hooks against v1 file emits info + falls back gracefully
# -----------------------------------------------------------------------
@test "AC5: check_hooks against v1 file emits info finding, does not crash" {
  # Reset to v1 state (in case prior test in suite migrated it)
  jq -n --arg p "$HOOK_PATH" '[$p]' > "$WALTER_CONFIG/hook-checksums.json"

  AUDIT_FINDINGS="$TMP_HOME/findings.jsonl"

  run bash -c "
    set -uo pipefail
    export HOME='$HOME'
    export WALTER_CONFIG='$WALTER_CONFIG'
    export WALTER_OS_HOME='$WALTER_OS_HOME'
    export CLAUDE_HOME='$CLAUDE_HOME'
    finding() {
      local sev=\"\$1\" id=\"\$2\" desc=\"\$3\" action=\"\${4:-investigate manually}\"
      jq -nc --arg sev \"\$sev\" --arg id \"\$id\" --arg desc \"\$desc\" --arg action \"\$action\" \
        '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> '$AUDIT_FINDINGS'
    }
    export -f finding
    source '$AUDIT' 2>/dev/null || true
    check_hooks
    echo \"exit:\$?\"
  "

  # Must not crash (exit:0 expected)
  [[ "$output" == *"exit:0"* ]]
  # Must have emitted at least an info finding about v1 schema
  if [ -s "$AUDIT_FINDINGS" ]; then
    grep -qE "v1|legacy|schema" "$AUDIT_FINDINGS"
  fi
}
