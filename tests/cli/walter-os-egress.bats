#!/usr/bin/env bats
# tests/cli/walter-os-egress.bats
#
# OSS Trust A-2 — AC-3 coverage. `walter-os egress` CLI subcommand.
# Spec: docs/specs/network-egress-allowlist.md
# Parent: #122 OSS Trust epic
#
# Subcommands under test:
#   walter-os egress add <host>      idempotent append
#   walter-os egress remove <host>   idempotent remove
#   walter-os egress list            print allowlist
#   walter-os egress test <host>     query loader, exit 0/1
#   walter-os egress import <path>   overwrite from file with envsubst

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"

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

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

@test "AC-3: egress add creates the file when missing + writes the entry" {
  run bash "$WALTER_OS_BIN" egress add api.github.com
  [ "$status" -eq 0 ]
  [[ -f "$ALLOWLIST" ]]
  grep -qxF "api.github.com" "$ALLOWLIST"
}

@test "AC-3: egress add is idempotent (no duplicate lines)" {
  bash "$WALTER_OS_BIN" egress add api.github.com >/dev/null
  bash "$WALTER_OS_BIN" egress add api.github.com >/dev/null
  bash "$WALTER_OS_BIN" egress add api.github.com >/dev/null
  count="$(grep -cxF "api.github.com" "$ALLOWLIST")"
  [ "$count" -eq 1 ]
}

@test "AC-3: egress add multiple distinct hosts appends each on its own line" {
  bash "$WALTER_OS_BIN" egress add api.github.com >/dev/null
  bash "$WALTER_OS_BIN" egress add pypi.org >/dev/null
  bash "$WALTER_OS_BIN" egress add '*.openrouter.ai' >/dev/null
  [ "$(grep -cxF 'api.github.com' "$ALLOWLIST")" -eq 1 ]
  [ "$(grep -cxF 'pypi.org' "$ALLOWLIST")" -eq 1 ]
  [ "$(grep -cxF '*.openrouter.ai' "$ALLOWLIST")" -eq 1 ]
}

@test "AC-3: egress add rejects empty host" {
  run bash "$WALTER_OS_BIN" egress add ""
  [ "$status" -ne 0 ]
}

@test "AC-3: egress add rejects a host with embedded whitespace" {
  # `egress add 'foo bar.com'` is almost certainly a shell-quoting mistake,
  # NOT a real DNS entry. Reject loud rather than silently writing junk
  # the loader will never match.
  run bash "$WALTER_OS_BIN" egress add 'foo bar.com'
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------

@test "AC-3: egress remove deletes the matching line" {
  printf '%s\n' "api.github.com" "pypi.org" > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress remove pypi.org
  [ "$status" -eq 0 ]
  ! grep -qxF "pypi.org" "$ALLOWLIST"
  grep -qxF "api.github.com" "$ALLOWLIST"
}

@test "AC-3: egress remove is idempotent (removing a missing entry is OK)" {
  printf '%s\n' "api.github.com" > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress remove evil.example
  [ "$status" -eq 0 ]
  grep -qxF "api.github.com" "$ALLOWLIST"
}

@test "AC-3: egress remove on a missing allowlist file does not crash" {
  rm -f "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress remove api.github.com
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

@test "AC-3: egress list prints the current allowlist" {
  printf '%s\n' "# header comment" "api.github.com" "*.openrouter.ai" > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress list
  [ "$status" -eq 0 ]
  [[ "$output" == *"api.github.com"* ]]
  [[ "$output" == *"*.openrouter.ai"* ]]
}

@test "AC-3: egress list on a missing file prints empty + clear hint" {
  rm -f "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress list
  [ "$status" -eq 0 ]
  # Hint must mention import OR add so the operator knows what to do.
  [[ "$output" == *"import"* ]] || [[ "$output" == *"add"* ]]
}

# ---------------------------------------------------------------------------
# test
# ---------------------------------------------------------------------------

@test "AC-3: egress test <allowed-host> prints 'allowed' + exits 0" {
  echo 'api.github.com' > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress test api.github.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowed"* ]]
}

@test "AC-3: egress test <denied-host> prints 'denied' + exits 1" {
  echo 'api.github.com' > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress test evil.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"denied"* ]]
}

@test "AC-3: egress test honours wildcards (loader semantics)" {
  echo '*.openrouter.ai' > "$ALLOWLIST"
  run bash "$WALTER_OS_BIN" egress test api.openrouter.ai
  [ "$status" -eq 0 ]
  run bash "$WALTER_OS_BIN" egress test openrouter.ai
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# import
# ---------------------------------------------------------------------------

@test "AC-3: egress import overwrites the allowlist with file contents" {
  echo 'preexisting.example' > "$ALLOWLIST"
  local src="$TMP_HOME/src.txt"
  printf '%s\n' "api.github.com" "pypi.org" > "$src"

  run bash "$WALTER_OS_BIN" egress import "$src"
  [ "$status" -eq 0 ]
  grep -qxF "api.github.com" "$ALLOWLIST"
  grep -qxF "pypi.org" "$ALLOWLIST"
  # Pre-existing line should be gone (overwrite, not merge).
  ! grep -qxF "preexisting.example" "$ALLOWLIST"
}

@test "AC-3: egress import expands \${VAR} via envsubst when var is set" {
  local src="$TMP_HOME/src.txt"
  printf '%s\n' 'llm.${WALTER_DOMAIN}' > "$src"

  WALTER_DOMAIN=example.tld run bash "$WALTER_OS_BIN" egress import "$src"
  [ "$status" -eq 0 ]
  grep -qxF "llm.example.tld" "$ALLOWLIST"
  # The literal ${WALTER_DOMAIN} must NOT appear in the on-disk file.
  ! grep -qF '${WALTER_DOMAIN}' "$ALLOWLIST"
}

@test "AC-3: egress import SKIPS lines with unset \${VAR} + WARN on stderr" {
  local src="$TMP_HOME/src.txt"
  printf '%s\n' "api.github.com" 'llm.${WALTER_DOMAIN}' 'secrets.${WALTER_DOMAIN}' > "$src"

  # Run with WALTER_DOMAIN unset.
  run bash -c "unset WALTER_DOMAIN; bash '$WALTER_OS_BIN' egress import '$src' 2>&1"
  [ "$status" -eq 0 ]
  # The unset-VAR lines are SKIPPED (not present in on-disk file).
  ! grep -qF '${WALTER_DOMAIN}' "$ALLOWLIST"
  ! grep -q '^llm\.$' "$ALLOWLIST"   # would be the result of empty-substitution
  ! grep -q '^secrets\.$' "$ALLOWLIST"
  # And the SET-host stays put.
  grep -qxF "api.github.com" "$ALLOWLIST"
  # WARN message on stderr must mention WALTER_DOMAIN.
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"WALTER_DOMAIN"* ]]
}

@test "AC-3: egress import preserves comments + blanks" {
  local src="$TMP_HOME/src.txt"
  printf '%s\n' "# header comment" "" "api.github.com" > "$src"

  run bash "$WALTER_OS_BIN" egress import "$src"
  [ "$status" -eq 0 ]
  grep -q "^# header comment$" "$ALLOWLIST"
  grep -qxF "api.github.com" "$ALLOWLIST"
}

@test "AC-3: egress import errors on missing source path" {
  run bash "$WALTER_OS_BIN" egress import "$TMP_HOME/does-not-exist.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"does-not-exist"* ]]
}

# ---------------------------------------------------------------------------
# Dispatch + help
# ---------------------------------------------------------------------------

@test "AC-3: 'egress' subcommand is reachable from main dispatch" {
  run bash "$WALTER_OS_BIN" egress list
  [ "$status" -eq 0 ]
}

@test "AC-3: 'egress' with no args prints usage + exits non-zero" {
  run bash "$WALTER_OS_BIN" egress
  [ "$status" -ne 0 ]
  [[ "$output" == *"add"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"test"* ]]
  [[ "$output" == *"import"* ]]
}

@test "AC-3: 'egress <unknown-subcommand>' prints usage + exits non-zero" {
  run bash "$WALTER_OS_BIN" egress wibble
  [ "$status" -ne 0 ]
}
