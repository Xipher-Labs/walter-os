#!/usr/bin/env bats
# Tests for the Makefile audit targets — AC-8

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  cd "$REPO_ROOT"
}

@test "makefile_exists: Makefile exists at repo root" {
  [ -f Makefile ]
}

@test "audit_target_exists: make -n audit exits 0 (dry-run)" {
  run make -n audit
  [ "$status" -eq 0 ]
}

@test "audit_dry_run_contains_shellcheck: make -n audit includes shellcheck" {
  run make -n audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'shellcheck'
}

@test "audit_dry_run_contains_gitleaks: make -n audit includes gitleaks" {
  run make -n audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'gitleaks'
}

@test "audit_dry_run_contains_osv: make -n audit includes osv-scanner" {
  run make -n audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'osv-scanner'
}

@test "audit_ci_target_exists: make -n audit-ci exits 0 (dry-run)" {
  run make -n audit-ci
  [ "$status" -eq 0 ]
}
