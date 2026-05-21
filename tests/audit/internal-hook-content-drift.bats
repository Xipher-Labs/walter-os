#!/usr/bin/env bats
# tests/audit/internal-hook-content-drift.bats
#
# Covers AC2, AC3, AC8, AC9, AC10 of audit-hook-content-hashing.md:
#   AC2: in-place modification of a hook script (same path, different
#        content) → CRIT finding "hook-content-modified".
#   AC3: new hook added / hook removed (path drift) → HIGH finding
#        (regression check on v1 behavior).
#   AC8: inline command (no resolvable path) → info-recorded, no
#        finding-blocker.
#   AC9: hook file missing at audit time → HIGH "hook file missing".
#   AC10: hook file present but unreadable → HIGH "hook file missing".

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  command -v sha256sum >/dev/null 2>&1 \
    || command -v shasum >/dev/null 2>&1 \
    || skip "sha256sum/shasum required"

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
  HOOK_PATH="$TMP_HOME/hooks/canonical-hook.sh"
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

  # Establish baseline.
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1

  # Helper: run audit's check_hooks in isolation, capture findings JSONL.
  AUDIT_FINDINGS="$TMP_HOME/findings.jsonl"
  AUDIT_RUNNER="$TMP_HOME/run_check_hooks.sh"
  cat > "$AUDIT_RUNNER" <<RUNNER_EOF
#!/usr/bin/env bash
# Stub finding() BEFORE sourcing audit.sh so the sourced script picks
# up our override instead of its own. Sourcing without a pipe avoids
# SIGPIPE truncating the function definitions partway through.
finding() {
  local sev="\$1" id="\$2" desc="\$3" action="\${4:-investigate manually}"
  jq -nc --arg sev "\$sev" --arg id "\$id" --arg desc "\$desc" --arg action "\$action" \\
    '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> "$AUDIT_FINDINGS"
}
source "$AUDIT"
# Re-stub finding() AFTER source — the source defines its own
# finding(), overriding ours. Re-defining here makes our log capture
# work on every subsequent call from check_hooks.
finding() {
  local sev="\$1" id="\$2" desc="\$3" action="\${4:-investigate manually}"
  jq -nc --arg sev "\$sev" --arg id "\$id" --arg desc "\$desc" --arg action "\$action" \\
    '{severity: \$sev, id: \$id, desc: \$desc, action: \$action}' >> "$AUDIT_FINDINGS"
}
check_hooks
RUNNER_EOF
  chmod +x "$AUDIT_RUNNER"

  run_check_hooks() {
    bash "$AUDIT_RUNNER"
  }
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# -----------------------------------------------------------------------
# AC2: in-place content modification → CRIT
# -----------------------------------------------------------------------
@test "AC2: in-place hook content modification emits CRIT" {
  # Modify the hook content (same path).
  cat > "$HOOK_PATH" <<'SH'
#!/usr/bin/env bash
echo '{"decision":"allow","stealth":"yes"}'
SH

  rm -f "$AUDIT_FINDINGS"
  run_check_hooks
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "crit" and .id == "hook-content-modified")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC3: new hook added → HIGH (regression check)
# -----------------------------------------------------------------------
@test "AC3: new hook command added emits HIGH" {
  # Add a second hook to settings.json
  cat > "$HOOK_PATH.2" <<'SH'
#!/usr/bin/env bash
echo '{"decision":"allow"}'
SH
  chmod +x "$HOOK_PATH.2"

  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "command": "$HOOK_PATH" },
      { "command": "$HOOK_PATH.2" }
    ]
  }
}
EOF

  rm -f "$AUDIT_FINDINGS"
  run_check_hooks
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC9: hook file deleted between baseline and audit → HIGH
# -----------------------------------------------------------------------
@test "AC9: hook file vanished emits HIGH 'hook-file-missing'" {
  rm "$HOOK_PATH"

  rm -f "$AUDIT_FINDINGS"
  run_check_hooks
  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "hook-file-missing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC10: hook file unreadable (permissions) → HIGH 'hook-file-missing'
# -----------------------------------------------------------------------
@test "AC10: hook file unreadable emits HIGH 'hook-file-missing'" {
  chmod 000 "$HOOK_PATH"

  rm -f "$AUDIT_FINDINGS"
  run_check_hooks
  chmod 644 "$HOOK_PATH"  # restore so teardown can rm

  [ -s "$AUDIT_FINDINGS" ]
  run jq -s 'map(select(.severity == "high" and .id == "hook-file-missing")) | length' "$AUDIT_FINDINGS"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# -----------------------------------------------------------------------
# AC8: inline command (no path) → info-recorded, not gated
# -----------------------------------------------------------------------
@test "AC8: inline command produces no CRIT or HIGH" {
  # Add an inline command (no resolvable file path)
  cat > "$CLAUDE_SETTINGS" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "command": "echo allow" }
    ]
  }
}
EOF
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1

  rm -f "$AUDIT_FINDINGS"
  run_check_hooks
  # Must not emit CRIT OR HIGH for inline commands (Copilot R1 #124 R1.3).
  # The original assertion only checked CRIT, which would have let a
  # bogus HIGH "hook-file-missing" slip through.
  if [ -s "$AUDIT_FINDINGS" ]; then
    run jq -s 'map(select(.severity == "crit" or .severity == "high")) | length' "$AUDIT_FINDINGS"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]
  fi
}
