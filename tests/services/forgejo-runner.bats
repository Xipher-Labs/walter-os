#!/usr/bin/env bats
# Static-analysis assertions for the optional Forgejo Actions runner profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER_DIR="$REPO_ROOT/setup/walter-host/services/forgejo-runner"
  COMPOSE_FILE="$RUNNER_DIR/compose.yml"
  SOCKET_COMPOSE_FILE="$RUNNER_DIR/compose.docker-socket.yml"
  ENV_TEMPLATE="$RUNNER_DIR/.env.template"
  README_FILE="$RUNNER_DIR/README.md"
  CONFIG_TEMPLATE="$RUNNER_DIR/config.yml.template"
}

@test "forgejo runner service files exist" {
  [[ -f "$COMPOSE_FILE" ]]
  [[ -f "$SOCKET_COMPOSE_FILE" ]]
  [[ -f "$ENV_TEMPLATE" ]]
  [[ -f "$README_FILE" ]]
  [[ -f "$CONFIG_TEMPLATE" ]]
}

@test "compose gates the runner behind the forgejo-runner profile" {
  grep -q "profiles:" "$COMPOSE_FILE"
  grep -q "forgejo-runner" "$COMPOSE_FILE"
}

@test "compose uses the official pinned Forgejo runner image" {
  grep -q "code.forgejo.org/forgejo/runner:12.10.2" "$COMPOSE_FILE"
}

@test "compose does not require registration token during interpolation" {
  ! grep -qE '\$\{FORGEJO_RUNNER_REGISTRATION_TOKEN:\?' "$COMPOSE_FILE"
  grep -q 'FORGEJO_RUNNER_REGISTRATION_TOKEN: ${FORGEJO_RUNNER_REGISTRATION_TOKEN:-}' "$COMPOSE_FILE"
}

@test "entrypoint requires registration token only before .runner exists" {
  grep -Fq 'if [ ! -f /data/.runner ]; then' "$COMPOSE_FILE"
  grep -Fq 'FORGEJO_RUNNER_REGISTRATION_TOKEN is required when /data/.runner is absent' "$COMPOSE_FILE"
}

@test "env template does not contain a real registration token" {
  grep -q "FORGEJO_RUNNER_REGISTRATION_TOKEN=" "$ENV_TEMPLATE"
  ! grep -qE 'FORGEJO_RUNNER_REGISTRATION_TOKEN=.+[A-Za-z0-9]{20,}' "$ENV_TEMPLATE"
}

@test "runner state persists in a named volume" {
  grep -q "forgejo-runner-data:" "$COMPOSE_FILE"
  grep -q "forgejo-runner-data:/data" "$COMPOSE_FILE"
}

@test "default compose does not mount the Docker socket" {
  ! grep -Fq "/var/run/docker.sock:/var/run/docker.sock" "$COMPOSE_FILE"
  ! grep -Fq "/var/run/docker.sock" "$CONFIG_TEMPLATE"
}

@test "docker socket override is explicit and documented as high risk" {
  grep -q "profiles:" "$SOCKET_COMPOSE_FILE"
  grep -q "forgejo-runner-docker-socket" "$SOCKET_COMPOSE_FILE"
  grep -Fq "/var/run/docker.sock:/var/run/docker.sock" "$SOCKET_COMPOSE_FILE"
  grep -qi "docker socket" "$README_FILE"
  grep -qi "high-risk" "$README_FILE"
}

@test "compose includes no-new-privileges hardening" {
  grep -q "no-new-privileges:true" "$COMPOSE_FILE"
}

@test "service files do not use latest tags" {
  ! grep -R --line-number -E '(:latest|@latest)' "$RUNNER_DIR"
}

@test "readme mentions runner credentials and labels" {
  grep -Fq ".runner" "$README_FILE"
  grep -Fq "docker:docker://node:20-bullseye" "$README_FILE"
}
