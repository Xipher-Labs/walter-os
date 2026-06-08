#!/usr/bin/env bats
# Coverage for Headscale registration diagnostics.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DIAGNOSE="$REPO_ROOT/setup/walter-host/services/headscale/diagnose.sh"
  DEPLOY="$REPO_ROOT/setup/walter-host/services/headscale/deploy.sh"
}

@test "headscale diagnose detects capver drift signature" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'ERR user msg: capability version must be set code=400\n' > "$log_file"

  run "$DIAGNOSE" \
    --mock-log "$log_file" \
    --headscale-version "Headscale 0.26.0" \
    --tailscale-version "1.96.4"

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "capability-version drift detected"
  echo "$output" | grep -Fq "Headscale: Headscale 0.26.0"
  echo "$output" | grep -Fq "Tailscale client: 1.96.4"
  echo "$output" | grep -Fq "Hetzner Cloud Firewall SSH allow-list"
  echo "$output" | grep -Fq "RUNBOOK.md"
}

@test "headscale diagnose exits cleanly without capver signature" {
  [[ -x "$DIAGNOSE" ]]

  log_file="$BATS_TEST_TMPDIR/headscale.log"
  printf 'INFO registration request completed\n' > "$log_file"

  run "$DIAGNOSE" --mock-log "$log_file"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "no known capability-version drift signature"
  echo "$output" | grep -Fq "live client registration"
}

@test "headscale diagnose rejects unreadable mock log" {
  [[ -x "$DIAGNOSE" ]]

  run "$DIAGNOSE" --mock-log "$BATS_TEST_TMPDIR/missing.log"

  [ "$status" -eq 2 ]
  echo "$output" | grep -Fq "mock log is not readable"
}

@test "headscale diagnose is documented from the runbook" {
  runbook="$REPO_ROOT/setup/walter-host/services/headscale/RUNBOOK.md"
  [[ -f "$runbook" ]]

  grep -Fq "deploy.sh --diagnose" "$runbook"
  grep -Fq "capability-version drift detected" "$runbook"
}

@test "headscale deploy exposes diagnose mode" {
  [[ -x "$DEPLOY" ]]

  grep -Fq -- "--diagnose" "$DEPLOY"
  grep -Fq "diagnose.sh" "$DEPLOY"
  grep -Fq "client registration fails" "$DEPLOY"
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
  echo "$output" | grep -Fq "capability-version drift detected"
  echo "$output" | grep -Fq "Headscale: Headscale 0.26.0"
}
