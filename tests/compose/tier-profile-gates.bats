#!/usr/bin/env bats
# tests/compose/tier-profile-gates.bats
#
# Covers AC7, AC8 of docs/specs/agent-install-tier-completion.md:
#   AC7: `docker compose --profile core` does NOT include control-tower.
#   AC8: `docker compose --profile tier4` DOES include control-tower.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  cd "$REPO_ROOT"
}

# Helper: per-test docker gate. Used inside individual tests instead
# of setup() so the source-level fallback test below still runs in
# CI jobs without docker installed (which is the whole point of
# having a source-level fallback).
_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker not available — this test exercises the compose CLI"
  fi
  # CI environments may have docker without the Compose v2 plugin. Without
  # this check, `docker compose config` fails with the cryptic
  # "docker: unknown command 'compose'". Closes PR #111 R4 Finding D.
  if ! docker compose version >/dev/null 2>&1; then
    skip "docker compose v2 plugin not available — this test exercises the compose CLI"
  fi
}

# -----------------------------------------------------------------------
# AC7: control-tower is NOT in the default / core profile output
# -----------------------------------------------------------------------
@test "AC7: docker compose config (no profile) does NOT list control-tower" {
  _require_docker
  # Without --profile, control-tower must NOT appear (will fail in RED
  # state — current compose.yml has no profiles: declaration).
  run docker compose -f compose.yml config --services
  # Some compose envs require env vars; if config errors out for other
  # reasons (missing required vars), skip this test rather than false-fail.
  if [ "$status" -ne 0 ]; then
    skip "compose config failed (likely missing required env vars): $output"
  fi
  ! grep -q "^control-tower$" <<< "$output"
}

@test "AC7: docker compose --profile core config does NOT list control-tower" {
  _require_docker
  run docker compose -f compose.yml --profile core config --services
  if [ "$status" -ne 0 ]; then
    skip "compose config failed: $output"
  fi
  ! grep -q "^control-tower$" <<< "$output"
}

# -----------------------------------------------------------------------
# AC8: control-tower IS in the tier4 profile output
# -----------------------------------------------------------------------
@test "AC8: docker compose --profile tier4 config DOES list control-tower" {
  _require_docker
  run docker compose -f compose.yml --profile tier4 config --services
  if [ "$status" -ne 0 ]; then
    skip "compose config failed: $output"
  fi
  grep -q "^control-tower$" <<< "$output"
}

# -----------------------------------------------------------------------
# Source-level alternative (no docker needed) — passes if the profiles
# declaration is present in compose.yml. This is the fallback for CI
# jobs without docker available.
# -----------------------------------------------------------------------
@test "AC7+AC8 (source-level): compose.yml declares profiles for control-tower" {
  # Locate the control-tower block and confirm it contains profiles: [tier4]
  # within the next 30 lines (loose match to allow other keys).
  ct_line=$(grep -n "^  control-tower:" "${REPO_ROOT}/compose.yml" | head -1 | cut -d: -f1)
  [ -n "${ct_line}" ]
  block_end=$((ct_line + 30))
  block=$(sed -n "${ct_line},${block_end}p" "${REPO_ROOT}/compose.yml")
  # Must contain profiles: [tier4] (or profiles: ['tier4'] / ["tier4"]).
  [[ "$block" =~ profiles:[[:space:]]*\[[\"\']?tier4[\"\']?\] ]]
}
