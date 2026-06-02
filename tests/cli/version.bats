#!/usr/bin/env bats
# tests/cli/version.bats
#
# Covers: AC-6 — walter-os version exit code, semver output, VERSION parity,
#         and _version_is_newer comparison logic.
#
# AC-6: walter-os version exits 0, output contains semver, matches VERSION,
#       _version_is_newer helper handles newer/older/equal/pre-release cases.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"

# Override WALTER_OS_HOME so the binary finds VERSION in the test repo.
export WALTER_OS_HOME="${REPO_ROOT}"

# Disable update check during tests (no network, no GITHUB_TOKEN).
export WALTER_OS_SKIP_UPDATE_CHECK="1"

# -----------------------------------------------------------------------
# setup: source the canonical lib so _version_is_newer unit tests
# exercise the single-source-of-truth implementation, not a local copy.
# -----------------------------------------------------------------------
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export WALTER_CONFIG="$BATS_TEST_TMPDIR/walter-config"
  export WALTER_OS_HOME="${REPO_ROOT}"
  export WALTER_OS_SKIP_UPDATE_CHECK="1"
  mkdir -p "$HOME" "$WALTER_CONFIG"
  # shellcheck source=scripts/walter/lib/version-compare.sh
  source "${REPO_ROOT}/scripts/walter/lib/version-compare.sh"
}

# -----------------------------------------------------------------------
# AC-6 test 1: exit code
# -----------------------------------------------------------------------
@test "walter-os version exits 0 [AC-6]" {
  run "${WALTER_OS_BIN}" version
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------
# AC-6 test 2: output contains semver string
# -----------------------------------------------------------------------
@test "walter-os version output contains semver string [AC-6]" {
  run "${WALTER_OS_BIN}" version
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'
}

# -----------------------------------------------------------------------
# AC-6 test 3: version matches content of VERSION file
# -----------------------------------------------------------------------
@test "walter-os version matches VERSION file content [AC-6]" {
  run "${WALTER_OS_BIN}" version
  [ "$status" -eq 0 ]
  local file_version
  file_version="$(cat "${REPO_ROOT}/VERSION")"
  echo "$output" | grep -qF "${file_version}"
}

# -----------------------------------------------------------------------
# AC-6 test 4: _version_is_newer — 0.2.0 is newer than 0.1.0
# -----------------------------------------------------------------------
@test "_version_is_newer: 0.2.0 newer than 0.1.0 returns true [AC-6]" {
  _version_is_newer "0.2.0" "0.1.0"
}

# -----------------------------------------------------------------------
# AC-6 test 5: _version_is_newer — 0.1.0 is NOT newer than 0.2.0
# -----------------------------------------------------------------------
@test "_version_is_newer: 0.1.0 not newer than 0.2.0 returns false [AC-6]" {
  ! _version_is_newer "0.1.0" "0.2.0"
}

# -----------------------------------------------------------------------
# AC-6 test 6: _version_is_newer — equal versions returns false
# -----------------------------------------------------------------------
@test "_version_is_newer: equal versions returns false [AC-6]" {
  ! _version_is_newer "0.2.0" "0.2.0"
}

# -----------------------------------------------------------------------
# AC-6 test 7: _version_is_newer — pre-release vs release
# -----------------------------------------------------------------------
@test "_version_is_newer: 0.2.0 newer than 0.2.0-alpha [AC-6]" {
  _version_is_newer "0.2.0" "0.2.0-alpha"
}

# -----------------------------------------------------------------------
# BLOCKER 1: curl calls must carry --max-time and --connect-timeout
# Verified by inspecting the source (no network required).
# -----------------------------------------------------------------------
@test "update-check curl calls have timeout flags [AC-2]" {
  # Both curl calls in the update-check function must carry --max-time and
  # --connect-timeout.  We count occurrences: expect at least 2 (one for
  # the authed path, one for the unauthed path).
  local count
  count="$(grep -cE "curl.*--max-time.*--connect-timeout|curl.*--connect-timeout.*--max-time" \
    "${WALTER_OS_BIN}")"
  [ "$count" -ge 2 ]
}

# -----------------------------------------------------------------------
# BLOCKER 2: update-available branch — mock curl to return newer tag
# Covers: AC-2 / AC-6
# -----------------------------------------------------------------------
@test "_version_is_newer sourced from shared lib [AC-6]" {
  # Verify the shared lib exists and exports _version_is_newer.
  local lib="${REPO_ROOT}/scripts/walter/lib/version-compare.sh"
  [ -f "$lib" ]
  # shellcheck source=/dev/null
  # Source the lib in a subshell and check the function is defined.
  bash -c "source '${lib}'; declare -f _version_is_newer >/dev/null"
}

@test "non-version subcommand works when version-compare.sh is missing [AC-6]" {
  # The lib must be sourced lazily (inside cmd_version only).
  # If source is at file scope, any subcommand invocation will fail when the
  # lib is absent.  This test renames the lib temporarily, runs 'help', and
  # expects exit 0.
  local lib="${REPO_ROOT}/scripts/walter/lib/version-compare.sh"
  local tmp_lib="${lib}.bak_test"
  mv "$lib" "$tmp_lib"
  run env WALTER_OS_HOME="${REPO_ROOT}" "${WALTER_OS_BIN}" help
  local rc="$status"
  mv "$tmp_lib" "$lib"   # restore unconditionally
  [ "$rc" -eq 0 ]
}

@test "WALTER_OS_UPDATE_REPO override controls API endpoint [AC-2]" {
  # When WALTER_OS_UPDATE_REPO is set to a custom org/repo, the update-check
  # curl call must use that repo, not a legacy hardcoded upstream owner.
  # We verify by capturing which URL the mock curl received.
  local mock_dir
  mock_dir="$(mktemp -d)"
  # Write the captured args to a tmp file so we can inspect them.
  cat > "${mock_dir}/curl" <<'MOCK'
#!/usr/bin/env bash
# Capture all args; return a valid (non-updating) response.
echo "$*" >> /tmp/walter_test_curl_args.txt
echo '{"tag_name":"v0.3.0","name":"Walter-OS v0.3.0"}'
MOCK
  chmod +x "${mock_dir}/curl"
  rm -f /tmp/walter_test_curl_args.txt

  run env \
    PATH="${mock_dir}:${PATH}" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OS_SKIP_UPDATE_CHECK="" \
    WALTER_OS_UPDATE_REPO="myorg/my-fork" \
    "${WALTER_OS_BIN}" version

  rm -rf "${mock_dir}"

  [ "$status" -eq 0 ]
  # The curl call must reference myorg/my-fork, not a legacy hardcoded upstream owner.
  grep -q "myorg/my-fork" /tmp/walter_test_curl_args.txt
  rm -f /tmp/walter_test_curl_args.txt
}

@test "walter-os version shows update-available when newer tag exists [AC-2]" {
  # Export a mock curl that returns a JSON payload with a newer version.
  # The real binary sources _check_for_update which calls curl.
  # We override curl in PATH so the subprocess picks it up.
  local mock_dir
  mock_dir="$(mktemp -d)"
  # The mock returns a tag deliberately far ahead of any plausible current
  # VERSION so the test does not have to be touched on every release bump.
  cat > "${mock_dir}/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl: ignore all args, return a fake GitHub releases/latest response.
echo '{"tag_name":"v99.0.0","name":"Walter-OS v99.0.0"}'
MOCK
  chmod +x "${mock_dir}/curl"

  run env \
    PATH="${mock_dir}:${PATH}" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OS_SKIP_UPDATE_CHECK="" \
    "${WALTER_OS_BIN}" version

  rm -rf "${mock_dir}"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q "(update available:"
  echo "$output" | grep -q "walter-os upgrade --dry-run"
  echo "$output" | grep -q "walter-os upgrade --target v99.0.0"
}

@test "invalid WALTER_OS_UPDATE_REPO prints warning and exits 0 [AC-2]" {
  # A value without a slash must not crash — it should warn on stderr and skip
  # the update check (exit 0).
  run env \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OS_SKIP_UPDATE_CHECK="" \
    WALTER_OS_UPDATE_REPO="noorgslash" \
    "${WALTER_OS_BIN}" version

  [ "$status" -eq 0 ]
  # The warning must appear on stderr (captured in $output by bats when mixed).
  echo "$output" | grep -q "WARN"
}
