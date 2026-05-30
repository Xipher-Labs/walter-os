#!/usr/bin/env bats
# tests/install/egress-import-prompt.bats
#
# OSS Trust A-2 — AC-5 first-run-prompt coverage. Pins:
#   - The function exists in install.sh
#   - run_step_0 invokes it after setup_git_hooks
#   - Skips cleanly when there's no TTY (the CI default)
#   - Skips cleanly when the allowlist file already exists
#   - The DRY_RUN path is non-destructive (writes nothing to disk)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALL_SH="$REPO_ROOT/install.sh"
  [[ -f "$INSTALL_SH" ]] || skip "install.sh missing"
}

@test "AC-5: prompt_egress_import function exists in install.sh" {
  grep -qE '^prompt_egress_import\(\)' "$INSTALL_SH"
}

@test "AC-5: run_step_0 invokes prompt_egress_import after setup_git_hooks" {
  # awk-extract run_step_0 body, then assert the invocation appears
  # AFTER setup_git_hooks (so the hook is registered + the CLI is
  # linked before we prompt).
  body="$(awk '/^run_step_0\(\)/,/^}$/' "$INSTALL_SH")"
  echo "$body" | grep -q 'prompt_egress_import'
  echo "$body" | grep -q 'setup_git_hooks'

  # Order check
  hooks_line=$(echo "$body" | grep -n 'setup_git_hooks' | head -1 | cut -d: -f1)
  prompt_line=$(echo "$body" | grep -n 'prompt_egress_import' | head -1 | cut -d: -f1)
  [ -n "$hooks_line" ]
  [ -n "$prompt_line" ]
  [ "$hooks_line" -lt "$prompt_line" ]
}

@test "AC-5: prompt skips cleanly when no TTY (non-interactive default)" {
  # Build a harness that actually CALLS prompt_egress_import in a
  # non-TTY context, and verify both the no-write invariant AND the
  # function-level signal (a stderr WARN with the manual-import hint).
  # Previously this test only sourced install.sh + checked no file was
  # written — it would have passed even if prompt_egress_import never
  # ran. Copilot R2 finding.
  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"

  HARNESS="$TMP_HOME/harness.sh"
  cat > "$HARNESS" <<HARNESS_EOF
#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT='$REPO_ROOT'
WALTER_CONFIG='$TMP_CFG'
DRY_RUN=0
# Minimal stubs (install.sh uses these for colored output).
step() { echo "STEP: \$*"; }
say()  { echo "\$*"; }
warn() { echo "WARN: \$*"; }
ok()   { echo "OK: \$*"; }
err()  { echo "ERR: \$*" >&2; }
dry()  { echo "DRY: \$*"; }
# Extract + invoke just the function.
eval "\$(awk '/^prompt_egress_import\(\) {/,/^}\$/' '$INSTALL_SH')"
prompt_egress_import
HARNESS_EOF
  chmod +x "$HARNESS"

  # `< /dev/null` ensures stdin is NOT a TTY; bats redirects stdout too,
  # so [[ -t 0 ]] && [[ -t 1 ]] in the function is false → non-TTY branch.
  run bash "$HARNESS" < /dev/null
  [ "$status" -eq 0 ]
  # Non-TTY branch must emit the "No TTY — skipping" hint with the
  # manual-import command.
  [[ "$output" == *"No TTY"* ]] || [[ "$output" == *"Skipping"* ]] || { echo "expected non-TTY skip message: $output"; return 1; }
  [[ "$output" == *"walter-os egress import"* ]]
  # And no allowlist file gets written.
  [[ ! -f "$TMP_CFG/egress-allowlist.txt" ]]

  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

@test "AC-5: prompt is a no-op when allowlist file already exists" {
  # Pre-create the allowlist + call the function via DRY_RUN=0. Since
  # the file is present, the function must say so + leave the file
  # alone. (Skipping the TTY check entirely keeps this test
  # deterministic across CI vs interactive runs.)
  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"
  echo "preexisting.example" > "$TMP_CFG/egress-allowlist.txt"

  # Use a tiny harness script that sources install.sh's function defs.
  HARNESS="$TMP_HOME/harness.sh"
  cat > "$HARNESS" <<HARNESS_EOF
#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT='$REPO_ROOT'
WALTER_CONFIG='$TMP_CFG'
DRY_RUN=0
# Define no-op helpers so the function's say/step/dry/warn calls work
# without sourcing the full install.sh (which would actually run the
# wizard).
step() { echo "STEP: \$*"; }
say()  { echo "\$*"; }
warn() { echo "WARN: \$*"; }
ok()   { echo "OK: \$*"; }
err()  { echo "ERR: \$*" >&2; }
dry()  { echo "DRY: \$*"; }
# Extract just the prompt_egress_import function and eval it.
eval "\$(awk '/^prompt_egress_import\(\) {/,/^}\$/' '$INSTALL_SH')"
prompt_egress_import
HARNESS_EOF
  chmod +x "$HARNESS"

  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  # Pre-existing file MUST still be there, unchanged.
  grep -qxF "preexisting.example" "$TMP_CFG/egress-allowlist.txt"
  # And the function should have said so.
  [[ "$output" == *"already at"* ]]

  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

@test "AC-5: DRY_RUN path writes nothing" {
  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"

  HARNESS="$TMP_HOME/harness.sh"
  cat > "$HARNESS" <<HARNESS_EOF
#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT='$REPO_ROOT'
WALTER_CONFIG='$TMP_CFG'
DRY_RUN=1
step() { echo "STEP: \$*"; }
say()  { echo "\$*"; }
warn() { echo "WARN: \$*"; }
ok()   { echo "OK: \$*"; }
err()  { echo "ERR: \$*" >&2; }
dry()  { echo "DRY: \$*"; }
eval "\$(awk '/^prompt_egress_import\(\) {/,/^}\$/' '$INSTALL_SH')"
prompt_egress_import
HARNESS_EOF
  chmod +x "$HARNESS"

  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  [[ ! -f "$TMP_CFG/egress-allowlist.txt" ]]
  [[ "$output" == *"DRY"* ]]

  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}
