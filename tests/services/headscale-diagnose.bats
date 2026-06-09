#!/usr/bin/env bats
# Coverage for Headscale registration diagnostics.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DIAGNOSE="$REPO_ROOT/setup/walter-host/services/headscale/diagnose.sh"
  DEPLOY="$REPO_ROOT/setup/walter-host/services/headscale/deploy.sh"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_BIN"
}

@test "headscale diagnose detects capver rejection signature" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'ERR user msg: capability version must be set code=400\n' > "$log_file"

  run "$DIAGNOSE" \
    --mock-log "$log_file" \
    --headscale-version "Headscale 0.26.0" \
    --tailscale-version "1.96.4"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "capability-version rejection signature detected"
  echo "$output" | grep -Fq "manual curl to /key without a capver query"
  echo "$output" | grep -Fq "before treating the finding as confirmed client/server drift"
  echo "$output" | grep -Fq "Headscale: Headscale 0.26.0"
  echo "$output" | grep -Fq "Tailscale client: 1.96.4"
  echo "$output" | grep -Fq "Hetzner Cloud Firewall SSH allow-list"
  echo "$output" | grep -Fq "RUNBOOK.md"
}

@test "headscale diagnose can run from stdin for remote inspection" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'INFO registration request completed\n' > "$log_file"

  run bash -s -- --mock-log "$log_file" < "$DIAGNOSE"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "Headscale registration diagnostic"
  echo "$output" | grep -Fq "no known runtime or registration blocker found"
}

@test "headscale diagnose detects stopped container before reading stale logs" {
  [[ -x "$DIAGNOSE" ]]

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "exec" ]]; then
  exit 1
fi
if [[ "$1" == "inspect" ]]; then
  echo "exited"
  exit 0
fi
if [[ "$1" == "logs" ]]; then
  echo "INFO registration request completed"
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_BIN/docker"

  run env PATH="$TEST_BIN:/usr/bin:/bin" "$DIAGNOSE"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "Headscale container is not running"
  echo "$output" | grep -Fq "docker compose -f"
  echo "$output" | grep -Fq "deploy.sh --diagnose"
}

@test "headscale diagnose treats missing container as not running" {
  [[ -x "$DIAGNOSE" ]]

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "exec" ]]; then
  exit 1
fi
if [[ "$1" == "inspect" ]]; then
  echo "No such object: headscale" >&2
  exit 1
fi
if [[ "$1" == "logs" ]]; then
  echo "INFO stale registration request completed"
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_BIN/docker"

  run env PATH="$TEST_BIN:/usr/bin:/bin" "$DIAGNOSE"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "Container state: missing"
  echo "$output" | grep -Fq "Headscale container is not running"
  ! echo "$output" | grep -Fq "stale registration request completed"
}

@test "headscale diagnose keeps docker daemon inspect errors inconclusive" {
  [[ -x "$DIAGNOSE" ]]

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "exec" ]]; then
  exit 1
fi
if [[ "$1" == "inspect" ]]; then
  echo "Cannot connect to the Docker daemon" >&2
  exit 1
fi
if [[ "$1" == "logs" ]]; then
  echo "Cannot connect to the Docker daemon" >&2
  exit 1
fi
exit 1
EOF
  chmod +x "$TEST_BIN/docker"

  run env PATH="$TEST_BIN:/usr/bin:/bin" "$DIAGNOSE"

  [ "$status" -eq 3 ]
  ! echo "$output" | grep -Fq "Container state: missing"
  ! echo "$output" | grep -Fq "Headscale container is not running"
  echo "$output" | grep -Fq "could not inspect Headscale logs"
  echo "$output" | grep -Fq "Cannot connect to the Docker daemon"
}

@test "headscale diagnose detects TS2021 websocket proxy warning" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf '%s\n' \
    'WRN No Upgrade header in TS2021 request. If headscale is behind a reverse proxy, make sure it is configured to pass WebSockets through.' \
    > "$log_file"

  run "$DIAGNOSE" --mock-log "$log_file"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "TS2021 WebSocket proxy warning detected"
  echo "$output" | grep -Fq "reverse proxy is not passing WebSocket upgrade headers"
  echo "$output" | grep -Fq "Cloudflare Tunnel/Caddy route"
  echo "$output" | grep -Fq 'headscale.${WALTER_DOMAIN}'
  ! echo "$output" | grep -Fq 'headscale.${WALTER_DOMAIN}.'
}

@test "headscale diagnose exits cleanly without capver signature" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'INFO registration request completed\n' > "$log_file"

  run "$DIAGNOSE" --mock-log "$log_file"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "no known runtime or registration blocker found"
  ! echo "$output" | grep -Fq "no known capability-version drift signature"
  echo "$output" | grep -Fq "live client registration"
}

@test "headscale diagnose rejects unreadable mock log" {
  [[ -x "$DIAGNOSE" ]]

  run "$DIAGNOSE" --mock-log "$BATS_TEST_TMPDIR/missing.log"

  [ "$status" -eq 2 ]
  echo "$output" | grep -Fq "mock log is not readable"
}

@test "headscale diagnose help is location agnostic" {
  [[ -x "$DIAGNOSE" ]]

  run "$DIAGNOSE" --help

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "Usage: diagnose.sh [options]"
  echo "$output" | grep -Fq "No known runtime or registration blocker found"
  ! echo "$output" | grep -Fq "setup/walter-host/services/headscale/diagnose.sh"
}

@test "headscale diagnose falls back to compose image when docker exec fails" {
  [[ -x "$DIAGNOSE" ]]

  compose_file="$BATS_TEST_TMPDIR/compose.yml"
  cat >"$compose_file" <<'EOF'
services:
  headscale:
    image: headscale/headscale:9.9.9-test
EOF

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "exec" ]]; then
  exit 1
fi
if [[ "$1" == "inspect" ]]; then
  echo "running"
  exit 0
fi
if [[ "$1" == "logs" ]]; then
  echo "INFO registration request completed"
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_BIN/docker"

  run env PATH="$TEST_BIN:/usr/bin:/bin" "$DIAGNOSE" --compose "$compose_file"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "Headscale: Headscale 9.9.9-test"
  echo "$output" | grep -Fq "no known runtime or registration blocker found"
}

@test "headscale diagnose fails inconclusive when docker logs cannot be inspected" {
  [[ -x "$DIAGNOSE" ]]

  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "exec" ]]; then
  exit 1
fi
if [[ "$1" == "inspect" ]]; then
  echo "running"
  exit 0
fi
if [[ "$1" == "logs" ]]; then
  echo "Cannot connect to the Docker daemon" >&2
  exit 1
fi
exit 1
EOF
  chmod +x "$TEST_BIN/docker"

  run env PATH="$TEST_BIN:/usr/bin:/bin" "$DIAGNOSE"

  [ "$status" -eq 3 ]
  echo "$output" | grep -Fq "could not inspect Headscale logs"
  echo "$output" | grep -Fq "Cannot connect to the Docker daemon"
}

@test "headscale diagnose fails inconclusive when docker is unavailable" {
  [[ -x "$DIAGNOSE" ]]

  if PATH="/bin:/usr/bin" command -v docker >/dev/null 2>&1; then
    skip "docker is available in the minimal PATH on this runner"
  fi

  run env PATH="/bin:/usr/bin" "$DIAGNOSE"
  [ "$status" -eq 3 ]
  echo "$output" | grep -Fq "docker not available"
}

@test "headscale diagnose is documented from the runbook" {
  runbook="$REPO_ROOT/setup/walter-host/services/headscale/RUNBOOK.md"
  [[ -f "$runbook" ]]

  grep -Fq "deploy.sh --diagnose" "$runbook"
  grep -Fq "capability-version rejection signature detected" "$runbook"
  grep -Fq "curl /key" "$runbook"
  grep -Fq "Headscale container is not running" "$runbook"
  grep -Fq "TS2021 WebSocket proxy warning detected" "$runbook"

  diagnose_line="$(grep -Fn "deploy.sh --diagnose" "$runbook" | head -n1 | cut -d: -f1)"
  rollout_line="$(grep -Fn "walter-os upgrade --local" "$runbook" | head -n1 | cut -d: -f1)"
  [[ -n "$diagnose_line" ]]
  [[ -n "$rollout_line" ]]
  (( rollout_line > diagnose_line ))
  (( rollout_line - diagnose_line < 40 ))

  grep -Fq "walter-os upgrade --local" "$runbook"
  grep -Fq "walter deploy headscale" "$runbook"
  grep -Fq '`walter deploy headscale` is not read-only' "$runbook"
  grep -Fq "docker compose pull" "$runbook"
  grep -Fq "docker compose up -d" "$runbook"
  ! grep -Fq 'Start it with `docker compose -f /opt/walter-vm/services/headscale/compose.yml' "$runbook"
}

@test "headscale deploy exposes diagnose mode" {
  [[ -x "$DEPLOY" ]]

  grep -Fq -- "--diagnose" "$DEPLOY"
  grep -Fq "diagnose.sh" "$DEPLOY"
  grep -Fq "client registration fails" "$DEPLOY"
  ! grep -Fq "WALTER_DOMAIN=yourdomain.com ./deploy.sh --diagnose" "$DEPLOY"
}

@test "headscale deploy diagnose forwards diagnostic args without WALTER_DOMAIN" {
  [[ -x "$DEPLOY" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'ERR user msg: capability version must be set code=400\n' > "$log_file"

  run "$DEPLOY" --diagnose \
    --mock-log "$log_file" \
    --headscale-version "Headscale 0.26.0" \
    --tailscale-version "1.96.4"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "capability-version rejection signature detected"
  echo "$output" | grep -Fq "Headscale: Headscale 0.26.0"
}
