#!/usr/bin/env bats
# tests/install/uninstall-restore.bats
#
# Closes #191. Verifies four behaviour gaps in install.sh's link_safe
# + do_uninstall flow that operators reported as friction points:
#
#   Gap 1: do_uninstall doesn't restore the operator's pre-Walter-OS file
#          from the OLDEST `.pre-walter-os.<ts>` backup.
#   Gap 2: link_safe creates a redundant backup when the existing dest
#          is already a Walter-OS symlink (rolling .pre-walter-os.<n>
#          accumulation across upgrade runs).
#   Gap 3: backup naming opaque (`.pre-walter-os.1712345678`) — replaced
#          with `.pre-walter-os.<ISO-8601-Z>.<unix>`.
#   Gap 4: no `walter-os uninstall` CLI subcommand.
#
# Critical: install.sh resolves REPO_ROOT from its own location, NOT
# from env vars. To test in isolation we COPY install.sh into the
# fake repo + run that copy. The copy detects $FAKE_REPO as its
# REPO_ROOT and operates entirely in the temp dir.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export WALTER_OS_HOME="$REPO_ROOT"

  # Build a fake repo with install.sh + a minimal source tree. install.sh
  # uses `$(dirname "$0")` to find its own REPO_ROOT, so copying it here
  # makes FAKE_REPO act as a self-contained repo for these tests.
  FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
  mkdir -p "$FAKE_REPO"
  cp "$REPO_ROOT/install.sh" "$FAKE_REPO/install.sh"
  # Minimal AGENTS.md + CLAUDE.md sources so link_safe has something
  # to point at if a test exercises that path.
  echo "# AGENTS.md fixture" > "$FAKE_REPO/AGENTS.md"
  echo "# CLAUDE.md fixture" > "$FAKE_REPO/CLAUDE.md"
}

# ---------------------------------------------------------------------------
# Gap 3: new backup naming includes ISO-8601 UTC datestamp
# ---------------------------------------------------------------------------

@test "Gap 3 (#191): link_safe backup naming includes ISO-8601 datestamp" {
  # Source the new naming pattern out of install.sh and assert it
  # matches `.pre-walter-os.<ISO>.<unix>` not just `.pre-walter-os.<unix>`.
  # Both stamps emitted from a SINGLE `date` call to avoid the
  # second-boundary race (Copilot R1 #201): assert via grep that the
  # iso + unix tokens are in a single command, and that the final
  # filename concatenates both.
  grep -qE 'date -u \+"%Y-%m-%dT%H-%M-%SZ %s"' "$REPO_ROOT/install.sh"
  grep -qE 'read -r stamp_iso stamp_unix' "$REPO_ROOT/install.sh"
  grep -qE 'backup="\$\{dest\}\.pre-walter-os\.\$\{stamp_iso\}\.\$\{stamp_unix\}"' \
    "$REPO_ROOT/install.sh"
}

# ---------------------------------------------------------------------------
# Gap 2: link_safe skips backup when existing dest is a Walter-OS symlink
# ---------------------------------------------------------------------------

@test "Gap 2 (#191): link_safe skips backup when existing dest points into REPO_ROOT" {
  # Verify the new code path: replace-existing-symlink branch checks
  # whether the readlink target starts with REPO_ROOT — if so, NO
  # backup is created.
  grep -qE 'if \[\[ "\$current" == "\$REPO_ROOT/"\* \]\]' "$REPO_ROOT/install.sh"
  grep -qE 'Replacing existing Walter-OS symlink' "$REPO_ROOT/install.sh"
}

# ---------------------------------------------------------------------------
# Gap 1: _restore_oldest_backup helper exists + do_uninstall calls it
# ---------------------------------------------------------------------------

@test "Gap 1 (#191): _restore_oldest_backup helper exists in install.sh" {
  grep -qE '^_restore_oldest_backup\(\)' "$REPO_ROOT/install.sh"
}

@test "Gap 1 (#191): do_uninstall invokes _restore_oldest_backup for CLAUDE.md + AGENTS.md" {
  # The helper must be called inside the for-loop that processes
  # CLAUDE.md and AGENTS.md, so the operator's pristine file gets
  # restored after the symlink is removed.
  awk '/^do_uninstall\(\)/,/^}$/' "$REPO_ROOT/install.sh" \
    | grep -qE '_restore_oldest_backup "\$f"'
}

@test "Gap 1 (#191): --restore-backups flag sets RESTORE_BACKUPS=yes" {
  grep -qE '\-\-restore-backups\)' "$REPO_ROOT/install.sh"
  grep -qE 'RESTORE_BACKUPS=yes' "$REPO_ROOT/install.sh"
}

@test "Gap 1 (#191): --no-restore-backups flag sets RESTORE_BACKUPS=no" {
  grep -qE '\-\-no-restore-backups\)' "$REPO_ROOT/install.sh"
  grep -qE 'RESTORE_BACKUPS=no' "$REPO_ROOT/install.sh"
}

@test "Gap 1 (#191): non-TTY default is SAFE (skip restore, don't silently delete)" {
  # The helper checks `[[ -t 0 ]] && [[ -t 1 ]]` for TTY; on non-TTY
  # (CI / pipe / scripted) it must skip restore + emit the manual
  # mv command for the operator. Verifies we don't silently DELETE
  # operator backups in headless contexts.
  awk '/^_restore_oldest_backup\(\)/,/^}$/' "$REPO_ROOT/install.sh" \
    | grep -qE 'No TTY|Skipping restore'
}

# ---------------------------------------------------------------------------
# Gap 1 — full restore behaviour, exercised through a copied install.sh
# ---------------------------------------------------------------------------

@test "Gap 1 (#191): restore picks OLDEST backup (operator pristine) not newest" {
  # Setup:
  #   - $FAKE_REPO/install.sh is the install.sh copy
  #   - claude_home/ holds CLAUDE.md symlink + 2 backups (oldest = pristine)
  local claude_home="$BATS_TEST_TMPDIR/claude_home"
  local codex_home="$BATS_TEST_TMPDIR/codex_home"
  local launch_agents="$BATS_TEST_TMPDIR/launch_agents"
  mkdir -p "$claude_home" "$codex_home" "$launch_agents"

  # Two backups with distinguishable contents:
  #   .pre-walter-os.2026-05-23T00-00-00Z.1000 = OPERATOR PRISTINE
  #   .pre-walter-os.2026-05-23T00-00-01Z.2000 = STALE WALTER LINK CAPTURE
  echo "OPERATOR PRISTINE" > "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-00Z.1000"
  echo "STALE LATER CAPTURE" > "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-01Z.2000"
  # Active Walter-OS symlink to be removed by uninstall.
  ln -s "$FAKE_REPO/CLAUDE.md" "$claude_home/CLAUDE.md"

  # Run the install.sh copy with the test-scoped HOME dirs. We have to
  # use a SUBPROCESS that we can control: install.sh sources its config
  # of CLAUDE_HOME from $HOME (the standard pattern), so we override.
  run env \
    CLAUDE_HOME="$claude_home" \
    CODEX_HOME="$codex_home" \
    LAUNCH_AGENTS="$launch_agents" \
    DAILY_AUDIT_LABEL="walter-os.daily-audit" \
    bash "$FAKE_REPO/install.sh" --uninstall --restore-backups

  # The symlink should be gone; in its place, the OPERATOR PRISTINE
  # content should be restored as a regular file.
  [[ ! -L "$claude_home/CLAUDE.md" ]]
  [[ -f "$claude_home/CLAUDE.md" ]]
  grep -q "OPERATOR PRISTINE" "$claude_home/CLAUDE.md"
  # Stale extra backup should be cleaned up.
  [[ ! -f "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-01Z.2000" ]]
  # And the oldest backup file should also be gone (it was MOVED into
  # CLAUDE.md, not copied).
  [[ ! -f "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-00Z.1000" ]]
}

@test "Gap 1 (#191): --no-restore-backups leaves backups in place" {
  local claude_home="$BATS_TEST_TMPDIR/claude_home"
  local codex_home="$BATS_TEST_TMPDIR/codex_home"
  local launch_agents="$BATS_TEST_TMPDIR/launch_agents"
  mkdir -p "$claude_home" "$codex_home" "$launch_agents"

  echo "OPERATOR PRISTINE" > "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-00Z.1000"
  ln -s "$FAKE_REPO/CLAUDE.md" "$claude_home/CLAUDE.md"

  run env \
    CLAUDE_HOME="$claude_home" \
    CODEX_HOME="$codex_home" \
    LAUNCH_AGENTS="$launch_agents" \
    DAILY_AUDIT_LABEL="walter-os.daily-audit" \
    bash "$FAKE_REPO/install.sh" --uninstall --no-restore-backups

  # Symlink gone (uninstall removed it). Backup untouched.
  [[ ! -L "$claude_home/CLAUDE.md" ]]
  [[ ! -f "$claude_home/CLAUDE.md" ]]   # no restore
  [[ -f "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-00Z.1000" ]]
  grep -q "OPERATOR PRISTINE" "$claude_home/CLAUDE.md.pre-walter-os.2026-05-23T00-00-00Z.1000"
}

# ---------------------------------------------------------------------------
# Gap 4: walter-os uninstall CLI subcommand
# ---------------------------------------------------------------------------

@test "Gap 4 (#191): walter-os uninstall dispatches to install.sh --uninstall" {
  grep -qE 'cmd_uninstall \"\$@\"' "$REPO_ROOT/bin/walter-os"
  awk '/^cmd_uninstall\(\)/,/^}$/' "$REPO_ROOT/bin/walter-os" \
    | grep -qE 'install\.sh.*--uninstall'
}

@test "Gap 4 (#191): cmd_uninstall errors clearly when install.sh is missing" {
  awk '/^cmd_uninstall\(\)/,/^}$/' "$REPO_ROOT/bin/walter-os" \
    | grep -qE 'install\.sh not found'
}

@test "Gap 4 (#191): cmd_uninstall forwards extra args" {
  # `walter-os uninstall --restore-backups` must propagate the flag
  # to install.sh — verified by the `"$@"` forwarding pattern.
  awk '/^cmd_uninstall\(\)/,/^}$/' "$REPO_ROOT/bin/walter-os" \
    | grep -qE 'exec bash.*--uninstall.*"\$@"'
}
