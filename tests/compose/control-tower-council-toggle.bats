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
# These tests assert the image keeps the CLI available while constraining
# the writable surface to Control Tower's own mode-state volume. Runtime
# API behavior is covered by the Control Tower test suite; these static
# guards catch image / compose drift before a container is built.

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

@test "AC-1 (#176): Dockerfile sets WALTER_CONFIG to Control Tower state dir" {
  grep -qE "^ENV[[:space:]]+WALTER_CONFIG=/var/lib/walter-os/control-tower" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile sets WALTER_CONFIG_DIR (CT route alignment)" {
  # apps/control-tower/app/api/mode/route.ts reads WALTER_CONFIG_DIR
  # while bin/walter-os + mode.sh read WALTER_CONFIG. Both must point at
  # the same path so the read (CT route) and write (CLI exec) paths
  # agree (Copilot R1 #194).
  grep -qE "^ENV[[:space:]]+WALTER_CONFIG_DIR=/var/lib/walter-os/control-tower" "$DOCKERFILE"
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

@test "AC-1 (#176): Dockerfile installs su-exec for privilege drop" {
  grep -qE "apk add .* su-exec" "$DOCKERFILE" || grep -qE "apk add .*su-exec" "$DOCKERFILE"
}

@test "AC-1 (#176): Dockerfile uses entrypoint to prepare mode state volume" {
  grep -qE "^COPY[[:space:]]+apps/control-tower/docker-entrypoint\\.sh[[:space:]]+/usr/local/bin/control-tower-entrypoint" "$DOCKERFILE"
  grep -qE '^ENTRYPOINT[[:space:]]+\["control-tower-entrypoint"\]' "$DOCKERFILE"
}

# ---------------------------------------------------------------------------
# AC-2: container drops privileges after preparing the volume
# ---------------------------------------------------------------------------

@test "AC-2 (#176): entrypoint prepares volume then execs as node" {
  local entrypoint="$REPO_ROOT/apps/control-tower/docker-entrypoint.sh"
  [[ -f "$entrypoint" ]]
  grep -Fq 'chown -R node:node "$WALTER_CONFIG_DIR"' "$entrypoint"
  grep -Fq 'exec su-exec node "$@"' "$entrypoint"
}

@test "AC-2 (#176): entrypoint aligns WALTER_CONFIG and WALTER_CONFIG_DIR" {
  local entrypoint="$REPO_ROOT/apps/control-tower/docker-entrypoint.sh"
  [[ -f "$entrypoint" ]]
  grep -Fq 'export WALTER_CONFIG="${WALTER_CONFIG:-$default_state_dir}"' "$entrypoint"
  grep -Fq 'export WALTER_CONFIG_DIR="${WALTER_CONFIG_DIR:-$WALTER_CONFIG}"' "$entrypoint"
}

# ---------------------------------------------------------------------------
# AC-3: compose mounts only Control Tower mode state RW
# ---------------------------------------------------------------------------

@test "AC-3 (#176): root compose.yml mounts dedicated Control Tower state RW" {
  [[ -f "$ROOT_COMPOSE" ]] || skip "root compose.yml missing"
  awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -qE 'control_tower_config:/var/lib/walter-os/control-tower:rw'
  grep -qE '^  control_tower_config:$' "$ROOT_COMPOSE"
}

@test "AC-3 (#176): root compose.yml does not mount operator config RW into CT" {
  [[ -f "$ROOT_COMPOSE" ]] || skip "root compose.yml missing"
  ! awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -qE '/root/\.config/walter-os'
}

@test "AC-3 (#176): standalone compose.yml mounts dedicated Control Tower state RW" {
  [[ -f "$STANDALONE_COMPOSE" ]] || skip "standalone compose missing"
  grep -qE 'control_tower_config:/var/lib/walter-os/control-tower:rw' "$STANDALONE_COMPOSE"
  grep -qE '^  control_tower_config:$' "$STANDALONE_COMPOSE"
}

@test "AC-3 (#176): standalone compose.yml does not mount operator config RW into CT" {
  [[ -f "$STANDALONE_COMPOSE" ]] || skip "standalone compose missing"
  ! grep -qE '/root/\.config/walter-os' "$STANDALONE_COMPOSE"
}

@test "AC-3 (#176): root compose.yml hardens Control Tower privileges" {
  awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -qE 'no-new-privileges:true'
  awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -qE 'cap_drop:'
  awk '/^  control-tower:/{flag=1;next} flag && /^  [a-z][a-z0-9-]+:/{flag=0} flag' \
    "$ROOT_COMPOSE" \
    | grep -qE '^[[:space:]]+-[[:space:]]+ALL$'
}

@test "AC-3 (#176): standalone compose.yml hardens Control Tower privileges" {
  grep -qE 'no-new-privileges:true' "$STANDALONE_COMPOSE"
  grep -qE 'cap_drop:' "$STANDALONE_COMPOSE"
  grep -qE '^[[:space:]]+-[[:space:]]+ALL$' "$STANDALONE_COMPOSE"
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
