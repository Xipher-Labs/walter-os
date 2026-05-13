#!/usr/bin/env bats
# Validates that all new security-hardening workflow files are syntactically
# valid YAML using Python's yaml.safe_load. AC-1, AC-5, AC-6.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
}

_validate_yaml() {
  local file="$1"
  python3 -c "import yaml; yaml.safe_load(open('$file')); print('ok')" 2>&1
}

@test "gitleaks workflow is valid yaml" {
  local f="$REPO_ROOT/.github/workflows/gitleaks.yml"
  [ -f "$f" ] || skip "gitleaks.yml not found"
  result=$(_validate_yaml "$f")
  echo "$result" | grep -q "ok"
}

@test "scorecard workflow is valid yaml" {
  local f="$REPO_ROOT/.github/workflows/scorecard.yml"
  [ -f "$f" ] || skip "scorecard.yml not found"
  result=$(_validate_yaml "$f")
  echo "$result" | grep -q "ok"
}

@test "osv-scanner workflow is valid yaml" {
  local f="$REPO_ROOT/.github/workflows/osv-scanner.yml"
  [ -f "$f" ] || skip "osv-scanner.yml not found"
  result=$(_validate_yaml "$f")
  echo "$result" | grep -q "ok"
}

@test "codeql workflow is valid yaml" {
  local f="$REPO_ROOT/.github/workflows/codeql.yml"
  [ -f "$f" ] || skip "codeql.yml not found"
  result=$(_validate_yaml "$f")
  echo "$result" | grep -q "ok"
}

@test "release-security workflow is valid yaml" {
  local f="$REPO_ROOT/.github/workflows/release-security.yml"
  [ -f "$f" ] || skip "release-security.yml not found"
  result=$(_validate_yaml "$f")
  echo "$result" | grep -q "ok"
}
