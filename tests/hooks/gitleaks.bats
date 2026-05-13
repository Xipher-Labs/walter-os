#!/usr/bin/env bats
# Tests for gitleaks integration — AC-1
# Covers: protect --staged behavior and allowlist enforcement.
#
# Note on test fixture: gitleaks 8.x default rules detect RSA private key
# headers reliably. AWS-format public test fixtures may be allowlisted in some
# gitleaks versions.
# We use RSA key header as the canonical fake-secret fixture.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# Fake RSA key content for tests (deliberately NOT a real key)
FAKE_RSA_KEY="-----BEGIN RSA PRIVATE"" KEY-----"$'\n'
FAKE_RSA_KEY+="MIIEowIBAAKCAQEA2a2rwplBQLF_FAKE_NOT_REAL_KEY_FOR_TESTING_ONLY_XXXX"$'\n'
FAKE_RSA_KEY+="-----END RSA PRIVATE"" KEY-----"

setup_file() {
  # Skip all tests if gitleaks is not installed
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed"
}

setup() {
  # Create a temporary git repo for each test
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test User"
  # Create an initial commit so HEAD exists
  git commit --quiet --allow-empty -m "init"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "gitleaks_blocks_fake_secret: protect --staged exits non-zero for RSA private key" {
  # Write a file with a fake RSA private key header (reliably detected by gitleaks default rules)
  printf '%s\n' "$FAKE_RSA_KEY" > secrets.txt
  git add secrets.txt

  # gitleaks protect --staged should detect this and exit non-zero
  run gitleaks protect --staged --no-banner 2>/dev/null
  [ "$status" -ne 0 ]
}

@test "gitleaks_allows_clean_file: protect --staged exits zero for file with no secrets" {
  printf 'Hello, world!\nThis is a clean file with no credentials.\n' > clean.txt
  git add clean.txt

  run gitleaks protect --staged --no-banner 2>/dev/null
  [ "$status" -eq 0 ]
}

@test "gitleaks_respects_allowlist: protect --staged exits zero for fake key in tests/fixtures/" {
  # Create the path structure matching the allowlist in .gitleaks.toml
  mkdir -p tests/fixtures
  printf '%s\n' "$FAKE_RSA_KEY" > tests/fixtures/fake-rsa-key.txt
  git add tests/fixtures/fake-rsa-key.txt

  # Using the repo's .gitleaks.toml which allowlists tests/fixtures/
  run gitleaks protect --staged --no-banner --config="$REPO_ROOT/.gitleaks.toml" 2>/dev/null
  [ "$status" -eq 0 ]
}

# --- .githooks/pre-commit hook file assertions (no live gitleaks required) ---

@test ".githooks/pre-commit exists in repo" {
  [[ -f "$REPO_ROOT/.githooks/pre-commit" ]]
}

@test ".githooks/pre-commit is executable" {
  [[ -x "$REPO_ROOT/.githooks/pre-commit" ]]
}

@test ".githooks/pre-commit invokes gitleaks protect --staged" {
  grep -q "gitleaks protect --staged" "$REPO_ROOT/.githooks/pre-commit"
}

@test ".githooks/pre-commit has walter-os marker comment" {
  grep -q "walter-os: gitleaks pre-commit" "$REPO_ROOT/.githooks/pre-commit"
}

@test ".githooks/pre-commit prints install hint when gitleaks missing" {
  grep -q "brew install gitleaks" "$REPO_ROOT/.githooks/pre-commit"
}

@test "scripts/setup-githooks.sh exists and is executable" {
  [[ -f "$REPO_ROOT/scripts/setup-githooks.sh" ]]
  [[ -x "$REPO_ROOT/scripts/setup-githooks.sh" ]]
}

@test "scripts/setup-githooks.sh --dry-run exits zero" {
  run bash -c "cd '$REPO_ROOT' && bash scripts/setup-githooks.sh --dry-run"
  [ "$status" -eq 0 ]
}

@test "install.sh calls setup-githooks.sh (setup_git_hooks wired)" {
  grep -q "setup.git.hooks\|setup-githooks" "$REPO_ROOT/install.sh"
}
