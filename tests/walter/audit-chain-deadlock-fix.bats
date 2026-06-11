#!/usr/bin/env bats
# tests/walter/audit-chain-deadlock-fix.bats
#
# Coverage for docs/specs/enforcement-audit-deadlock-fix.md
#   D1 — a delegated append is a no-op success (the un-sandboxed
#        sandbox-hook-runner writes the real row instead of the sandboxed
#        child, which cannot read the signing key nor write the audit dir).
#   D2 — append verifies only the chain tail, so a corrupt EARLIER row no
#        longer bricks subsequent appends, while full verify still catches it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-chain.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-05-31"
  export WALTER_AUDIT_NOW="2026-05-31T12:00:00Z"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
  bash -c "source '$SESSION_LIB'; walter_session_touch '$REPO_ROOT'" >/dev/null
  state_file="$(bash -c "source '$SESSION_LIB'; walter_session_state_file '$REPO_ROOT'")"
  export WALTER_SESSION_ID="$(jq -r '.session_id' "$state_file")"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-audit-chain.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-05-31.jsonl\n' "$WALTER_CONFIG"
}

_append() {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash '$1' allow network-gate ''"
}

@test "D1: WALTER_AUDIT_DELEGATED=1 makes walter_audit_append a no-op success" {
  run bash -c "source '$AUDIT_LIB'; WALTER_AUDIT_DELEGATED=1 walter_audit_append Bash 'git status' allow network-gate ''"
  [ "$status" -eq 0 ]
  # The delegated (no-op) append must not have created any chain file; the
  # un-sandboxed runner is responsible for the real row.
  [ ! -e "$(_chain_path)" ]
}

@test "D1: delegated flag does NOT suppress audit-critical un-sandboxed hooks" {
  # An ambient WALTER_AUDIT_DELEGATED=1 must not silence approval-gate's own
  # audit row — only network-gate/bash-denylist (run via the runner) are
  # delegated.
  run bash -c "source '$AUDIT_LIB'; WALTER_AUDIT_DELEGATED=1 walter_audit_append Bash 'rm -rf /' block approval-gate 'blocked'"
  [ "$status" -eq 0 ]
  [ -s "$(_chain_path)" ]
  [ "$(wc -l < "$(_chain_path)")" -eq 1 ]
}

@test "D1: append still writes exactly one row when WALTER_AUDIT_DELEGATED is unset" {
  run _append "git status"
  [ "$status" -eq 0 ]
  [ -s "$(_chain_path)" ]
  [ "$(wc -l < "$(_chain_path)")" -eq 1 ]
}

@test "D2: append accepts a new row when an EARLIER row is corrupted (tail still valid)" {
  _append "one" >/dev/null
  _append "two" >/dev/null
  chain="$(_chain_path)"
  [ "$(wc -l < "$chain")" -eq 2 ]
  # Corrupt the FIRST row's recorded input_summary; the tail (row 2) + root
  # remain consistent, so append must still succeed under tail-only verify.
  run perl -0pi -e 's/"input_summary":"one"/"input_summary":"bad"/' "$chain"
  [ "$status" -eq 0 ]
  run _append "three"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$chain")" -eq 3 ]
}

@test "D2: full verify still FAILS on the corrupted earlier row" {
  _append "one" >/dev/null
  _append "two" >/dev/null
  chain="$(_chain_path)"
  perl -0pi -e 's/"input_summary":"one"/"input_summary":"bad"/' "$chain"
  run bash -c "source '$AUDIT_LIB'; _walter_audit_verify_chain_file_unlocked '$chain'"
  [ "$status" -ne 0 ]
}

@test "D1: a sandboxed hook via the runner writes exactly one signed row with the hook decision_source" {
  command -v sandbox-exec >/dev/null 2>&1 || skip "sandbox-exec not available on this platform"
  RUNNER="$REPO_ROOT/scripts/walter/sandbox-hook-runner.sh"
  STUB="$BATS_TEST_TMPDIR/stub-hook.sh"
  cat > "$STUB" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '{"decision":"allow"}'
SH
  chmod +x "$STUB"

  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}' | WALTER_OS_HOME='$REPO_ROOT' '$RUNNER' -- '$STUB'"

  # The child decision is relayed unchanged...
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "allow"'
  # ...and the un-sandboxed runner wrote exactly one signed row for it, with
  # decision_source = the hook basename and decision = the emitted decision.
  [ "$(wc -l < "$(_chain_path)" | tr -d ' ')" -eq 1 ]
  jq -e '.decision_source == "stub-hook" and .decision == "allow" and (.sig | length) > 0' "$(_chain_path)"
}

@test "D1: runner fails closed when the captured stdin cannot be read" {
  # Exercises _runner_audit_append's read-failure guard directly (Copilot
  # review round 2): a missing input file must be treated as an append
  # failure, not signed as an empty-context row.
  run bash -c "
    set -uo pipefail
    export WALTER_OS_HOME='$REPO_ROOT'
    WALTER_SANDBOX_HOOK_RUNNER_LIB=1 source '$REPO_ROOT/scripts/walter/sandbox-hook-runner.sh'
    out='$BATS_TEST_TMPDIR/out.json'; printf '%s' '{\"decision\":\"allow\"}' > \"\$out\"
    _runner_audit_append '$BATS_TEST_TMPDIR/does-not-exist' \"\$out\" '/x/stub-hook.sh' allow
  "
  [ "$status" -ne 0 ]
  [ ! -e "$(_chain_path)" ]
}
