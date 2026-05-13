#!/usr/bin/env bats
# Tests for scripts/install-pre-commit.sh — the gitleaks pre-commit installer.
#
# The installer must:
#   1. Refuse to run when gitleaks is not on PATH (exits non-zero with hint).
#   2. Write .git/hooks/pre-commit invoking gitleaks protect --staged.
#   3. Be idempotent (running twice does not duplicate the line).
#   4. Preserve existing pre-commit content by prepending the gitleaks call.
#   5. Actually block a commit containing a known-leaky string when gitleaks
#      runs the hook (smoke test against a real fixture).
#
# Tests use a throwaway tmp git repo and a stub PATH so they do not modify
# the worktree's real .git/hooks. The installer is invoked from there.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALLER="$REPO_ROOT/scripts/install-pre-commit.sh"
  GITLEAKS_CONFIG_SRC="$REPO_ROOT/.gitleaks.toml"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q -b feature/test
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"

  # Provide a .gitleaks.toml in the tmp repo so the installer (which records
  # an absolute path to the config) has a real file to point at when invoked
  # from inside the tmp repo. We copy the repo's config so the rule set is
  # consistent with what operators will actually use.
  if [[ -f "$GITLEAKS_CONFIG_SRC" ]]; then
    cp "$GITLEAKS_CONFIG_SRC" "$TMPDIR_TEST/.gitleaks.toml"
  fi

  # Stub PATH used by the "gitleaks missing" test cases. By default we
  # keep the real PATH so gitleaks-installed tests see the real binary.
  STUBDIR="$TMPDIR_TEST/_stubpath"
  mkdir -p "$STUBDIR"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ---------- gitleaks-missing path ----------

@test "installer exits non-zero with install hint when gitleaks is missing" {
  # Run with a PATH that has zero gitleaks. Keep /usr/bin and /bin so git
  # itself still works inside the installer.
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" bash "$INSTALLER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gitleaks"* ]]
  [[ "$output" == *"brew install gitleaks"* || "$output" == *"apt install gitleaks"* || "$output" == *"go install"* ]]
}

# ---------- happy path ----------

@test "installer writes pre-commit hook invoking gitleaks protect --staged" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed (CI without gitleaks step)"
  run bash "$INSTALLER"
  [ "$status" -eq 0 ]
  [ -f .git/hooks/pre-commit ]
  grep -q "gitleaks protect --staged" .git/hooks/pre-commit
  grep -q "walter-os: gitleaks pre-commit" .git/hooks/pre-commit
  # Executable bit set.
  [ -x .git/hooks/pre-commit ]
}

@test "installer prints a one-line success message on success" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed (CI without gitleaks step)"
  run bash "$INSTALLER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-commit"* ]]
}

# ---------- idempotency ----------

@test "installer is idempotent: running twice does not duplicate the gitleaks line" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed (CI without gitleaks step)"
  bash "$INSTALLER" >/dev/null
  bash "$INSTALLER" >/dev/null
  # Exactly one occurrence of the walter-os marker line.
  count="$(grep -c "walter-os: gitleaks pre-commit" .git/hooks/pre-commit)"
  [ "$count" -eq 1 ]
  # And exactly one occurrence of the gitleaks invocation.
  invocations="$(grep -c "gitleaks protect --staged" .git/hooks/pre-commit)"
  [ "$invocations" -eq 1 ]
}

# ---------- preservation of existing hook content ----------

@test "installer preserves pre-existing pre-commit content" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed (CI without gitleaks step)"
  mkdir -p .git/hooks
  cat >.git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
echo "pre-existing dummy hook line"
EOF
  chmod +x .git/hooks/pre-commit

  bash "$INSTALLER" >/dev/null
  # Dummy line must still be present.
  grep -q "pre-existing dummy hook line" .git/hooks/pre-commit
  # And the gitleaks invocation added.
  grep -q "gitleaks protect --staged" .git/hooks/pre-commit
}

# ---------- end-to-end: hook blocks a leaky commit ----------

@test "installed hook blocks a commit containing a fake GitHub PAT" {
  # Requires real gitleaks on PATH (CI + dev machine).
  if ! command -v gitleaks >/dev/null 2>&1; then
    skip "gitleaks not installed; smoke test requires the real binary"
  fi

  bash "$INSTALLER" >/dev/null

  # Stage a file with an obvious fake secret matching gitleaks' built-in
  # github-pat rule (ghp_ prefix + 36 alphanumerics).
  printf 'github_pat = "%s%s"\n' \
    "ghp_" \
    "1234567890abcdefghijklmnopqrstuvwx12" > leaky.txt
  git add leaky.txt

  # Run the hook directly (not `git commit`) so the test does not depend on
  # core.hooksPath quirks or git pager interactions.
  run .git/hooks/pre-commit
  [ "$status" -ne 0 ]
}

# ---------- --dry-run is a no-op ----------

@test "installer --dry-run does not write the hook file" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed (CI without gitleaks step)"
  run bash "$INSTALLER" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f .git/hooks/pre-commit ]
}
