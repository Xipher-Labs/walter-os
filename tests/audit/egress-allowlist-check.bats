#!/usr/bin/env bats
# tests/audit/egress-allowlist-check.bats
#
# OSS Trust A-2 — AC-5 (R2 B6) coverage. Pins `check_egress_allowlist`
# in skills/daily-supply-chain-audit/scripts/audit.sh.
#
# The three findings from spec AC-5:
#   - file missing      → info "egress-allowlist-missing"
#   - file empty        → info "egress-allowlist-empty"
#   - private-IP entry  → high "egress-allowlist-private-ip"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"
  [[ -f "$AUDIT" ]] || skip "audit.sh missing"

  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_CFG"
  ALLOWLIST="$TMP_CFG/egress-allowlist.txt"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# Helper: source the audit lib + stub `finding` to capture calls into
# $FINDINGS_LOG, then call check_egress_allowlist.
_run_check() {
  local out
  out="$(bash -c "
    # Minimal stubs so audit.sh's globals are happy.
    SEVERITY=0; INFO_COUNT=0; HIGH_COUNT=0; CRIT_COUNT=0; FINDINGS=()
    finding() {
      local sev=\$1 id=\$2 detail=\$3 fix=\$4
      printf 'finding|%s|%s|%s|%s\n' \"\$sev\" \"\$id\" \"\$detail\" \"\$fix\"
    }
    # Source only the function we want — sourcing the whole file would
    # try to run main(). Extract via awk.
    eval \"\$(awk '/^check_egress_allowlist\(\)/,/^}\$/' '$AUDIT')\"
    check_egress_allowlist
  " 2>&1)"
  printf '%s\n' "$out"
}

@test "AC-5 (R2 B6): file missing → info egress-allowlist-missing" {
  rm -f "$ALLOWLIST"
  run _run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"finding|info|egress-allowlist-missing|"* ]]
  # The fix-hint must mention the bundled example.
  [[ "$output" == *"contexts/_examples/egress-allowlist.example.txt"* ]]
}

@test "AC-5 (R2 B6): empty file → info egress-allowlist-empty" {
  : > "$ALLOWLIST"
  run _run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"finding|info|egress-allowlist-empty|"* ]]
}

@test "AC-5 (R2 B6): file with only comments → info egress-allowlist-empty" {
  cat > "$ALLOWLIST" <<'EOF'
# nothing here
   # also nothing

EOF
  run _run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"finding|info|egress-allowlist-empty|"* ]]
}

@test "AC-5 (R2 B6): file with real entries → no missing/empty finding" {
  cat > "$ALLOWLIST" <<'EOF'
api.github.com
pypi.org
EOF
  run _run_check
  [ "$status" -eq 0 ]
  # No missing / empty findings (private-IP check may or may not fire
  # depending on whether the test host can resolve these public hosts).
  [[ "$output" != *"egress-allowlist-missing"* ]]
  [[ "$output" != *"egress-allowlist-empty"* ]]
}

@test "AC-5 (Codex R7 CR7-B): IPv4 literal entries are NOT flagged as private (operator-explicit)" {
  # The remediation hint tells operators to replace a hostname with
  # a literal IP if the private destination is intentional. Without
  # this skip, operators following the remediation got the same
  # `egress-allowlist-private-ip` alert daily forever.
  cat > "$ALLOWLIST" <<'EOF'
192.168.1.10
127.0.0.1
10.0.0.1
EOF
  run _run_check
  [ "$status" -eq 0 ]
  [[ "$output" != *"egress-allowlist-private-ip"* ]]
  # And the file isn't reported as empty.
  [[ "$output" != *"egress-allowlist-empty"* ]]
}

@test "AC-5 (R2 B6): wildcard entries are skipped (no false-positive on '*')" {
  cat > "$ALLOWLIST" <<'EOF'
*.openrouter.ai
EOF
  run _run_check
  [ "$status" -eq 0 ]
  # The wildcard is NOT resolved → no private-IP finding for it.
  [[ "$output" != *"egress-allowlist-private-ip"* ]]
  # And the file isn't reported as empty (one valid entry present).
  [[ "$output" != *"egress-allowlist-empty"* ]]
}
