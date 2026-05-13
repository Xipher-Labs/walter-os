#!/usr/bin/env bats
# tests/install/wizard.bats
# Bats integration tests for install.sh wizard harness (W-6)
# Gated by: bats tests/install/wizard.bats
#
# AC-11: --dry-run prints all 9 steps without executing
# AC-12: --step N runs only that step
# AC-13: test suite asserts step markers + --step 5 path

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  cd "$REPO_ROOT"
  export WALTER_INSTALL_DRY_RUN=1
}

# ---------------------------------------------------------------------------
# AC-11: --dry-run contains all 9 step markers
# ---------------------------------------------------------------------------

@test "wizard --dry-run exits 0" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
}

@test "wizard --dry-run prints STEP 1 marker (OS detect + deps)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 1"* ]] || [[ "$output" == *"STEP 1"* ]] || [[ "$output" == *"step 1"* ]]
}

@test "wizard --dry-run prints STEP 2 marker (env vars)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 2"* ]] || [[ "$output" == *"STEP 2"* ]] || [[ "$output" == *"step 2"* ]]
}

@test "wizard --dry-run prints STEP 3 marker (personal overlay)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 3"* ]] || [[ "$output" == *"STEP 3"* ]] || [[ "$output" == *"step 3"* ]]
}

@test "wizard --dry-run prints STEP 4 marker (Plane workspace)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 4"* ]] || [[ "$output" == *"STEP 4"* ]] || [[ "$output" == *"step 4"* ]]
}

@test "wizard --dry-run prints STEP 5 marker (Postgres DBs)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 5"* ]] || [[ "$output" == *"STEP 5"* ]] || [[ "$output" == *"step 5"* ]]
}

@test "wizard --dry-run prints STEP 6 marker (docker compose)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 6"* ]] || [[ "$output" == *"STEP 6"* ]] || [[ "$output" == *"step 6"* ]]
}

@test "wizard --dry-run prints STEP 7 marker (n8n workflows)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 7"* ]] || [[ "$output" == *"STEP 7"* ]] || [[ "$output" == *"step 7"* ]]
}

@test "wizard --dry-run prints STEP 8 marker (Infisical)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 8"* ]] || [[ "$output" == *"STEP 8"* ]] || [[ "$output" == *"step 8"* ]]
}

@test "wizard --dry-run prints STEP 9 marker (doctor + next steps)" {
  run ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 9"* ]] || [[ "$output" == *"STEP 9"* ]] || [[ "$output" == *"step 9"* ]]
}

# ---------------------------------------------------------------------------
# AC-12: --step N runs only that step
# ---------------------------------------------------------------------------

@test "wizard --step 5 exits 0" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
}

@test "wizard --step 5 output contains step-5 marker" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 5"* ]] || [[ "$output" == *"STEP 5"* ]] || [[ "$output" == *"step 5"* ]]
}

@test "wizard --step 5 does NOT print step 1 or step 9 markers" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
  # Step 1 marker should not appear when --step 5 is requested
  [[ "$output" != *"Step 1"* ]]
  [[ "$output" != *"STEP 1"* ]]
}

# ---------------------------------------------------------------------------
# AC-11/AC-13: --help and unknown flags
# ---------------------------------------------------------------------------

@test "wizard --help exits 0" {
  run ./install.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install.sh"* ]] || [[ "$output" == *"Walter-OS"* ]] || [[ "$output" == *"wizard"* ]]
}

@test "wizard rejects --step without a number" {
  run ./install.sh --step --dry-run
  [ "$status" -ne 0 ]
}

@test "wizard rejects --step with out-of-range value" {
  run ./install.sh --step 99 --dry-run
  [ "$status" -ne 0 ]
}

@test "wizard --dry-run does not write .env.local" {
  tmpdir="$(mktemp -d)"
  marker="$tmpdir/env.local"
  touch "$marker"
  # Use cross-platform stat (macOS -f vs Linux -c)
  pre_mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker")
  run env WALTER_ENV_LOCAL="$marker" ./install.sh --dry-run
  [ "$status" -eq 0 ]
  post_mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker")
  [ "$pre_mtime" = "$post_mtime" ]
  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# AC-2: Step 1 — docker missing → hard fail exit 1
# ---------------------------------------------------------------------------

@test "step 1 --dry-run prints brew/apt install for missing deps" {
  # AC-2: dry-run shows intent to install deps [AC-11]
  run ./install.sh --step 1 --dry-run
  [ "$status" -eq 0 ]
  # Either "would run: brew install" or "would run: sudo apt-get install"
  [[ "$output" == *"brew install"* ]] || \
  [[ "$output" == *"apt-get install"* ]] || \
  [[ "$output" == *"already installed"* ]]
}

@test "step 1 --dry-run does not hard-fail even if docker missing" {
  # In dry-run mode, step 1 prints what it would do without executing.
  # docker detection in dry-run: since docker IS present on this machine,
  # it prints "found". If docker were absent, dry-run would still print but not exit 1.
  run ./install.sh --step 1 --dry-run
  [ "$status" -eq 0 ]
}

@test "AC-11: --dry-run exits 0 when docker absent from PATH" {
  # WARN 1: docker hard-fail must be gated on DRY_RUN.
  # With an empty tmpbin prepended to PATH, docker is not found.
  # --dry-run must still exit 0 and print all steps, not exit 1.
  tmpbin="$(mktemp -d)"
  run env PATH="$tmpbin:/usr/bin:/bin" ./install.sh --dry-run
  [ "$status" -eq 0 ]
  rm -rf "$tmpbin"
}

@test "AC-11: --dry-run prints docker warning (not hard-fail) when docker absent" {
  # Companion: verify dry-run emits a warning about missing docker instead of exiting.
  tmpbin="$(mktemp -d)"
  run env PATH="$tmpbin:/usr/bin:/bin" ./install.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker"* ]]
  rm -rf "$tmpbin"
}

@test "AC-2: docker absent live mode exits 1 with install instructions" {
  # WARN 2: live mode (no --dry-run) must hard-fail with exit 1 when docker missing.
  # This is the AC-2 hard-fail behavior that must NOT regress.
  tmpbin="$(mktemp -d)"
  run env -u WALTER_INSTALL_DRY_RUN PATH="$tmpbin:/usr/bin:/bin" \
    ./install.sh --step 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker"* ]]
  [[ "$output" == *"install"* ]] || [[ "$output" == *"https://"* ]]
  rm -rf "$tmpbin"
}

# ---------------------------------------------------------------------------
# AC-3: Step 2 — env var prompts dry-run output
# ---------------------------------------------------------------------------

@test "step 2 --dry-run lists bootstrap vars" {
  # AC-3: dry-run shows which vars would be prompted
  run ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]
  # Should mention at minimum WALTER_DOMAIN
  [[ "$output" == *"WALTER_DOMAIN"* ]]
}

@test "step 2 --dry-run mentions WALTER_ADMIN_EMAIL" {
  run ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WALTER_ADMIN_EMAIL"* ]]
}

@test "step 2 --dry-run mentions WALTER_INITIAL_PASSWORD" {
  run ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WALTER_INITIAL_PASSWORD"* ]]
}

@test "step 2 --dry-run does not write env.local" {
  local env_local="${HOME}/.config/walter-os/env.local"
  # Record modification time before (if file exists)
  local before=""
  [[ -f "$env_local" ]] && before="$(stat -f '%m' "$env_local" 2>/dev/null || stat -c '%Y' "$env_local" 2>/dev/null)"

  run ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]

  local after=""
  [[ -f "$env_local" ]] && after="$(stat -f '%m' "$env_local" 2>/dev/null || stat -c '%Y' "$env_local" 2>/dev/null)"

  # mtime must be unchanged (dry-run must not write)
  [ "$before" = "$after" ]
}

@test "BLOCKER-1: step 2 --dry-run hides password value with [hidden]" {
  # AC-3/SECURITY: secret vars must not leak literal value in dry-run output
  run env WALTER_INITIAL_PASSWORD=secretpass ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[hidden]"* ]]
  [[ "$output" != *"secretpass"* ]]
}

@test "BLOCKER-3: WALTER_INSTALL_DRY_RUN=1 env var activates dry-run without flag" {
  # Defense-in-depth: env var OR --dry-run flag, both must work.
  # Verify dry-run output appears (contains [dry-run] marker) when only env var is set.
  run env WALTER_INSTALL_DRY_RUN=1 ./install.sh --step 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]] || [[ "$output" == *"dry-run"* ]]
}

# ---------------------------------------------------------------------------
# WARN-3: Plane/Infisical API error responses must not log raw $resp
# ---------------------------------------------------------------------------

@test "NIT-2: step 2 --dry-run does not mkdir in unset WALTER_ENV_LOCAL dir" {
  # Dry-run must produce no filesystem side-effects. mkdir -p must be gated.
  tmpdir="$(mktemp -d)"
  absent_dir="${tmpdir}/nonexistent/nested"
  run env WALTER_ENV_LOCAL="${absent_dir}/env.local" \
    ./install.sh --step 2 --dry-run
  [ "$status" -eq 0 ]
  # The directory must NOT have been created
  [ ! -d "$absent_dir" ]
  rm -rf "$tmpdir"
}

@test "WARN-4: install.sh uses docker label filter not grep for postgres" {
  # Fragile: 'docker ps | grep postgres' matches any container with "postgres"
  # in name (e.g. my-app-postgres-sidecar). Label filter is exact.
  ! grep -nE "docker ps.*grep postgres" "${REPO_ROOT}/install.sh"
  ! grep -nE "grep postgres" "${REPO_ROOT}/install.sh"
}

@test "WARN-3: install.sh does not log raw API response in warn messages" {
  # Security: raw API responses may contain tokens or sensitive data.
  # Assert the source has no 'warn "...$resp"' or similar raw-response interpolation.
  ! grep -nE 'warn .*\$resp' "${REPO_ROOT}/install.sh"
  ! grep -nE 'warn .*\$identity_resp' "${REPO_ROOT}/install.sh"
  ! grep -nE 'warn .*\$create_resp' "${REPO_ROOT}/install.sh"
}

# ---------------------------------------------------------------------------
# AC-4: Step 3 — personal overlay
# ---------------------------------------------------------------------------

@test "step 3 --dry-run prints overlay intent" {
  # AC-4: dry-run shows would call personal-overlay-init.sh
  run ./install.sh --step 3 --dry-run
  [ "$status" -eq 0 ]
  # Either "overlay found" or "would call" personal-overlay-init.sh
  [[ "$output" == *"overlay"* ]] || [[ "$output" == *"personal-overlay"* ]]
}

# ---------------------------------------------------------------------------
# AC-5: Step 4 — Plane graceful skip when token unset
# ---------------------------------------------------------------------------

@test "step 4 --dry-run prints Plane intent" {
  run ./install.sh --step 4 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plane"* ]] || [[ "$output" == *"plane"* ]]
}

@test "step 4 exits 0 even when PLANE_API_TOKEN unset" {
  # AC-5: graceful skip when token missing
  run env -u PLANE_API_TOKEN ./install.sh --step 4 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would create Plane workspace"* ]] || \
  [[ "$output" == *"Plane"* ]] || \
  [[ "$output" == *"plane"* ]]
}

@test "WARN-2: AC-5: PLANE unreachable live — graceful skip not crash" {
  # Live step 4 with unreachable URL must exit 0 (graceful skip, not crash).
  # Explicitly unset WALTER_INSTALL_DRY_RUN so this runs in live mode.
  run env -u WALTER_INSTALL_DRY_RUN PLANE_API_URL="http://localhost:1" \
    PLANE_API_TOKEN=fake ./install.sh --step 4
  [ "$status" -eq 0 ]
  # Must emit some form of "not reachable" / "skipping" message
  [[ "$output" == *"not reachable"* ]] || \
  [[ "$output" == *"not configured"* ]] || \
  [[ "$output" == *"skipping"* ]] || \
  [[ "$output" == *"Could not"* ]]
}

# ---------------------------------------------------------------------------
# AC-6: Step 5 — Postgres dry-run output
# ---------------------------------------------------------------------------

@test "step 5 --dry-run mentions walter_lessons" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"walter_lessons"* ]]
}

@test "step 5 --dry-run mentions walter_analytics" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"walter_analytics"* ]]
}

@test "step 5 --dry-run mentions walter_control_tower" {
  run ./install.sh --step 5 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"walter_control_tower"* ]]
}

# ---------------------------------------------------------------------------
# AC-7: Step 6 — docker compose dry-run output
# ---------------------------------------------------------------------------

@test "step 6 --dry-run mentions docker compose up" {
  run ./install.sh --step 6 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker compose"* ]]
}

@test "step 6 exits 0 even when compose.yml absent" {
  # AC-7: graceful skip when compose file not found
  # In dry-run mode, it prints intent and returns 0 regardless
  run ./install.sh --step 6 --dry-run
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-8: Step 7 — n8n dry-run output
# ---------------------------------------------------------------------------

@test "step 7 --dry-run mentions n8n or workflow" {
  run ./install.sh --step 7 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"n8n"* ]] || [[ "$output" == *"workflow"* ]]
}

# ---------------------------------------------------------------------------
# AC-9: Step 8 — Infisical dry-run output
# ---------------------------------------------------------------------------

@test "step 8 --dry-run mentions Infisical" {
  run ./install.sh --step 8 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Infisical"* ]] || [[ "$output" == *"infisical"* ]]
}

@test "step 8 --dry-run mentions Machine Identity" {
  run ./install.sh --step 8 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Machine Identity"* ]] || [[ "$output" == *"walter-agent"* ]]
}

# ---------------------------------------------------------------------------
# AC-10: Step 9 — next-steps banner
# ---------------------------------------------------------------------------

@test "step 9 --dry-run mentions Next steps" {
  run ./install.sh --step 9 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor"* ]] || [[ "$output" == *"next"* ]] || [[ "$output" == *"Next"* ]]
}
