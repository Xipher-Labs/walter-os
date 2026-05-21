#!/usr/bin/env bats
# tests/oss/no-latest-tags-walter-host.bats
#
# Audit P1-01 / P1-02 regression coverage: no service in
# `setup/walter-host/services/**` may pin a runtime dependency to
# `:latest`, `:stable`, or `@latest`. Each finding here would silently
# pull a new upstream version on the next `docker compose pull` /
# `docker compose up` / Dockerfile rebuild.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SERVICES_DIR="$REPO_ROOT/setup/walter-host/services"

# Filter helpers — strip lines that are obviously not pinned-dep refs.
# - "^\s*#"          : commented-out lines
# - "migration:latest": Infisical's npm script name, not a tag
# - "walter-control-tower:latest" : LOCAL build image, not a registry pull;
#                                   tracked separately, low supply-chain risk
# - "ghcr.io/xqdoo00o/chatgpt-to-api:latest" inside a comment block in
#   llm-proxies/compose.yml: opt-in alternative documented but not used.
#
# Any new exception MUST be justified in the PR body that adds it.
NOISE_PATTERN='^\s*#|migration:latest|walter-control-tower:latest|# *image: ghcr.io/xqdoo00o/chatgpt-to-api:latest'

@test "no compose service uses :latest tag (P1-02)" {
  run grep -rn 'image:[^#]*:latest\b' "$SERVICES_DIR" --include='compose.yml' --include='compose.*.yml'
  if [ "$status" -eq 0 ]; then
    # grep found matches — filter known-allowed
    filtered="$(echo "$output" | grep -Ev "$NOISE_PATTERN" || true)"
    if [ -n "$filtered" ]; then
      echo "FAIL: unpinned :latest image tag(s) found:" >&2
      echo "$filtered" >&2
      false
    fi
  fi
}

@test "no compose service uses :stable tag (P1-02)" {
  run grep -rn 'image:[^#]*:stable\b' "$SERVICES_DIR" --include='compose.yml' --include='compose.*.yml'
  if [ "$status" -eq 0 ]; then
    filtered="$(echo "$output" | grep -Ev "$NOISE_PATTERN" || true)"
    if [ -n "$filtered" ]; then
      echo "FAIL: unpinned :stable image tag(s) found:" >&2
      echo "$filtered" >&2
      false
    fi
  fi
}

@test "no Dockerfile uses @latest in npm install (P1-01)" {
  run grep -rn 'npm install[^#]*@latest\b' "$SERVICES_DIR" --include='Dockerfile*'
  if [ "$status" -eq 0 ]; then
    filtered="$(echo "$output" | grep -Ev "$NOISE_PATTERN" || true)"
    if [ -n "$filtered" ]; then
      echo "FAIL: npm install @latest found in Dockerfile(s):" >&2
      echo "$filtered" >&2
      false
    fi
  fi
}

@test "openclaw compose pins openclaw npm package to a version (P1-01)" {
  local compose="$SERVICES_DIR/openclaw/compose.yml"
  [ -f "$compose" ]

  # Must reference openclaw@<version>, never openclaw@latest, never bare openclaw
  grep -q 'npm install -g openclaw@[0-9]' "$compose"
  ! grep -q 'npm install -g openclaw@latest\b' "$compose"
  ! grep -E 'npm install -g openclaw[^@]' "$compose"
}
