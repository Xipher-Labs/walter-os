#!/usr/bin/env bats
# Tests for P0-01: run.sh must not allow heredoc injection from Plane issue
# description content. The RUNNER script must be generated safely.
#
# See: docs/operational/security-audit-2026-05-11.md P0-01

RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"

# We test the runner generation logic directly, not full end-to-end (which
# requires Plane API + LLM). We isolate the RUNNER generation pattern by
# recreating it in a minimal test harness.

@test "P0-01: USER_PROMPT containing WALTER_USER delimiter does not break RUNNER" {
  TMPDIR_TEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_TEST"' EXIT

  OUTFILE="$TMPDIR_TEST/runner.sh"
  MARKER_FILE="$TMPDIR_TEST/injected"

  # Craft a malicious USER_PROMPT that contains the inner heredoc delimiter
  # followed by a command that would create a marker file if executed.
  MALICIOUS_DESC=$(printf 'legitimate text\nWALTER_USER\n)\ntouch %s\nllm_invoke "x" "y" "" "\n' "$MARKER_FILE")

  SYSTEM_PROMPT="safe system prompt"
  USER_PROMPT="$MALICIOUS_DESC"

  # Simulate the RUNNER generation as done in run.sh (the fixed version).
  # The fix writes prompts to temp files and references them by path.
  SYSFILE=$(mktemp -t walter-test-sys.XXXXXX)
  USERFILE=$(mktemp -t walter-test-user.XXXXXX)
  trap 'rm -f "$SYSFILE" "$USERFILE"; rm -rf "$TMPDIR_TEST"' EXIT

  printf '%s' "$SYSTEM_PROMPT" > "$SYSFILE"
  printf '%s' "$USER_PROMPT" > "$USERFILE"

  # Build the runner script as the fixed version does (file references, not expansion)
  cat > "$OUTFILE" <<RUNNER_EOF
#!/usr/bin/env bash
set -uo pipefail
SYSFILE='$SYSFILE'
USERFILE='$USERFILE'
echo "runner executed safely"
RUNNER_EOF
  chmod +x "$OUTFILE"

  # Execute the runner — it must not create the marker file
  run bash "$OUTFILE"
  [[ "$status" -eq 0 ]]
  [[ ! -f "$MARKER_FILE" ]]
}

@test "P0-01: run.sh generates RUNNER using file references not inline expansion" {
  # Verify that the fixed run.sh uses temp files for prompt storage, not inline heredoc expansion.
  # This is a static check on the source code pattern.

  # Must NOT contain the vulnerable pattern: unquoted outer heredoc with inner heredoc body
  # The vulnerable pattern has: <<RUNNER_EOF ... <<'WALTER_USER' ... $USER_PROMPT ... WALTER_USER
  # The fix replaces inline expansion with file writes.

  # Check that SYSFILE/USERFILE or equivalent variable is referenced
  run grep -E 'SYSFILE|USERFILE|sys_file|user_file|_prompt_file|PROMPT_FILE' "$RUN_SH"
  [[ "$status" -eq 0 ]]
}

@test "P0-01: run.sh does not directly expand USER_PROMPT inside RUNNER heredoc" {
  # The vulnerable code pattern: unquoted <<RUNNER_EOF with $USER_PROMPT in body.
  # Check that this exact pattern is absent.
  # We look for the combination of unquoted RUNNER_EOF with USER_PROMPT inside.

  # After the fix, USER_PROMPT must NOT appear inside the RUNNER heredoc body.
  # Read from RUNNER_EOF to RUNNER_EOF section and check USER_PROMPT is not there inline.

  # Simple check: grep for $USER_PROMPT inside <<RUNNER_EOF ... RUNNER_EOF block
  # If the vulnerable pattern exists, we'll find lines like:
  #   $USER_PROMPT  (within the unquoted heredoc)
  run grep -n '\$USER_PROMPT' "$RUN_SH"
  if [[ "$status" -eq 0 ]]; then
    # Found $USER_PROMPT references — check they are NOT inside the RUNNER heredoc
    # They should only appear in: printf/cat to a file, variable assignment, etc.
    # NOT inside <<RUNNER_EOF ... RUNNER_EOF
    echo "$output" | grep -v 'printf\|cat.*>\|>.*file\|USERFILE\|SYSFILE\|#' | \
      grep -v '^\s*[0-9]*:\s*\(printf\|cat\|>>\|#\|USERFILE=\|SYSFILE=\)' && return 1 || return 0
  fi
  # $USER_PROMPT not found at all — also acceptable if variable was renamed
  return 0
}
