#!/usr/bin/env bats
# tests/walter/version-compare.bats
# Unit tests for _version_is_newer — verifies the documented pre-release
# semantics (intentionally simpler than full SemVer).
# Refs: PR-47-copilot-round-2 (R2-10)

VERSION_COMPARE_SH="$BATS_TEST_DIRNAME/../../scripts/walter/lib/version-compare.sh"

setup() {
  # shellcheck source=/dev/null
  source "$VERSION_COMPARE_SH"
}

# --- Standard semver core ---

@test "newer patch release is newer" {
  _version_is_newer "0.2.1" "0.2.0"
}

@test "same version is NOT newer" {
  ! _version_is_newer "0.2.0" "0.2.0"
}

@test "older patch release is NOT newer" {
  ! _version_is_newer "0.1.9" "0.2.0"
}

@test "newer minor version is newer" {
  _version_is_newer "0.3.0" "0.2.0"
}

@test "newer major version is newer" {
  _version_is_newer "1.0.0" "0.9.9"
}

# --- Pre-release semantics (documented: any release > any pre-release) ---

@test "release 0.2.0 is newer than pre-release 0.2.0-alpha" {
  _version_is_newer "0.2.0" "0.2.0-alpha"
}

@test "release 0.2.0 is newer than pre-release 0.2.0-beta" {
  _version_is_newer "0.2.0" "0.2.0-beta"
}

@test "pre-release 0.2.0-alpha is NOT newer than release 0.2.0" {
  ! _version_is_newer "0.2.0-alpha" "0.2.0"
}

# --- Two pre-releases with the same core compare equal (documented behavior) ---

@test "0.2.0-beta vs 0.2.0-alpha: returns NOT newer (equal treatment)" {
  ! _version_is_newer "0.2.0-beta" "0.2.0-alpha"
}

@test "0.2.0-alpha vs 0.2.0-beta: returns NOT newer (equal treatment)" {
  ! _version_is_newer "0.2.0-alpha" "0.2.0-beta"
}

@test "0.2.0-rc1 vs 0.2.0-rc1: returns NOT newer (identical)" {
  ! _version_is_newer "0.2.0-rc1" "0.2.0-rc1"
}
