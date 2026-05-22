#!/usr/bin/env bats
# tests/compose/control-tower-council-toggle.bats
#
# Regression guard for issue #176 — Council toggle in Control Tower
# was failing because:
#   1. The walter-os CLI was not present in the Control Tower container
#      image (the Dockerfile only copied the Next.js standalone bundle).
#   2. ~/.config/walter-os was mounted read-only, so even if the CLI
#      were present, it couldn't write mode.json.
#
# These tests assert both fixes stay in place. The actual `mode consensus
# on|off` exec path is exercised by Playwright in apps/control-tower/tests/
# but that requires a running container — these static guards catch the
# image / compose drift that broke the toggle in the first place.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DOCKERFILE="$REPO_ROOT/apps/control-tower/Dockerfile"
  ROOT_COMPOSE="$REPO_ROOT/compose.yml"
  STANDALONE_COMPOSE="$REPO_ROOT/setup/walter-host/services/control-tower/compose.yml"
}

# ---------------------------------------------------------------------------
# AC-1: Dockerfile copies the walter-os CLI + its mode-management library
# ---------------------------------------------------------------------------

@test "AC-1 (#176): Dockerfile copies bin/walter-os to /usr/local/bin/" {
  [[ -f "$DOCKERFILE" ]] || skip "Dockerfile missing"
  grep -qE "^COPY[[:space:]]+bin/walter-os[[:space:]]+/usr/local/bin/walter-os" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile copies scripts/agents/lib/mode.sh" {
  grep -qE "^COPY[[:space:]]+scripts/agents/lib/mode\\.sh" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile copies VERSION file" {
  grep -qE "^COPY[[:space:]]+VERSION" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile chmods walter-os executable" {
  grep -qE "chmod \\+x /usr/local/bin/walter-os" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile sets WALTER_OS_HOME to /opt/walter-os" {
  grep -qE "^ENV[[:space:]]+WALTER_OS_HOME=/opt/walter-os" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile sets WALTER_CONFIG to /root/.config/walter-os" {
  grep -qE "^ENV[[:space:]]+WALTER_CONFIG=/root/\\.config/walter-os" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile sets WALTER_CONFIG_DIR (CT route alignment)" {
  # apps/control-tower/app/api/mode/route.ts reads WALTER_CONFIG_DIR
  # while bin/walter-os + mode.sh read WALTER_CONFIG. Both must point at
  # the same path so the read (CT route) and write (CLI exec) paths
  # agree (Copilot R1 #194).
  grep -qE "^ENV[[:space:]]+WALTER_CONFIG_DIR=/root/\\.config/walter-os" "$DOCKERFILE"
}

@test "AC-1 (#176): .dockerignore allows the bundled paths (build context check)" {
  # The Dockerfile is in apps/control-tower but the build context is the
  # repo root (per compose.yml `build: { context: . }`). Without these
  # entries the COPY instructions error with "not found in build context"
  # at docker build time — caught by Copilot R1 #194.
  local ignore="$REPO_ROOT/.dockerignore"
  [[ -f "$ignore" ]] || skip ".dockerignore missing"
  grep -qE "^!bin/walter-os$" "$ignore"
  grep -qE "^!scripts/agents/lib/mode\\.sh$" "$ignore"
  grep -qE "^!VERSION$" "$ignore"
}

@test "AC-1 (#176): Dockerfile installs bash + jq (mode.sh + execFile prerequisites)" {
  # bash is needed because bin/walter-os is a bash script; node:22-alpine
  # ships BusyBox /bin/sh only. jq is needed by mode.sh's atomic
  # write/update of mode.json.
  grep -qE "apk add .* bash" "$DOCKERFILE" || grep -qE "apk add .*bash" "$DOCKERFILE"
  grep -qE "apk add .* jq" "$DOCKERFILE" || grep -qE "apk add .*jq" "$DOCKERFILE"
}

# ---------------------------------------------------------------------------
# AC-2: container does NOT run as the non-root nextjs user
# ---------------------------------------------------------------------------

@test "AC-2 (#176): Dockerfile does NOT set USER nextjs" {
  # /root/ on the host is mode 700 root:root. Running as a non-root UID
  # makes mode.json writes fail with EPERM even with :rw mount. The
  # trade-off (single-operator private VM) is documented in the
  # Dockerfile comments.
  ! grep -qE "^USER[[:space:]]+nextjs" "$DOCKERFILE"
}

# ---------------------------------------------------------------------------
# AC-3: compose mounts /root/.config/walter-os RW (not RO)
# ---------------------------------------------------------------------------

@test "AC-3 (#176): root compose.yml mounts walter-os config RW for control-tower" {
  [[ -f "$ROOT_COMPOSE" ]] || skip "root compose.yml missing"
  # Extract the control-tower service block and assert the config mount
  # is :rw (or unsuffixed, which defaults to RW for bind mounts).
  awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -E '/root/\.config/walter-os:/root/\.config/walter-os' \
    | grep -qvE ':ro($|\s)'
}

@test "AC-3 (#176): standalone compose.yml mounts walter-os config RW" {
  [[ -f "$STANDALONE_COMPOSE" ]] || skip "standalone compose missing"
  grep -E '/root/\.config/walter-os:/root/\.config/walter-os' "$STANDALONE_COMPOSE" \
    | grep -qvE ':ro($|\s)'
}

# ---------------------------------------------------------------------------
# AC-4: the mode-toggle API route still calls /usr/local/bin/walter-os
# (regression guard against future refactors that lose the canonical path)
# ---------------------------------------------------------------------------

@test "AC-4 (#176): /api/mode dispatches to /usr/local/bin/walter-os by default" {
  local route="$REPO_ROOT/apps/control-tower/app/api/mode/route.ts"
  [[ -f "$route" ]] || skip "mode route missing"
  grep -qE 'walterBin[[:space:]]*=[[:space:]]*process\.env\.WALTER_OS_BIN[[:space:]]*\?\?[[:space:]]*"/usr/local/bin/walter-os"' \
    "$route"
}
