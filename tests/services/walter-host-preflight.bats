#!/usr/bin/env bats
# Coverage for Walter-host capacity preflight and sizing docs.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PREFLIGHT="$REPO_ROOT/setup/walter-host/preflight-check.sh"
  WALTER_HOST_README="$REPO_ROOT/setup/walter-host/README.md"
  RESOURCE_BUDGET="$REPO_ROOT/docs/operational/resource-budget.md"
}

@test "preflight blocks full profile below 32GB RAM" {
  [[ -x "$PREFLIGHT" ]]

  run env \
    WALTER_PREFLIGHT_RAM_MB=16384 \
    WALTER_PREFLIGHT_VCPU=8 \
    WALTER_PREFLIGHT_DISK_GB=240 \
    "$PREFLIGHT" full

  [ "$status" -eq 1 ]
  echo "$output" | grep -Fq "FULL profile requires at least 32 GB RAM"
}

@test "preflight allows full profile on CX53-class capacity" {
  [[ -x "$PREFLIGHT" ]]

  run env \
    WALTER_PREFLIGHT_RAM_MB=32768 \
    WALTER_PREFLIGHT_VCPU=16 \
    WALTER_PREFLIGHT_DISK_GB=320 \
    "$PREFLIGHT" full

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "profile=full"
  echo "$output" | grep -Fq "capacity preflight passed"
}

@test "preflight supports explicit override for undersized full hosts" {
  [[ -x "$PREFLIGHT" ]]

  run env \
    WALTER_PREFLIGHT_RAM_MB=16384 \
    WALTER_PREFLIGHT_VCPU=8 \
    WALTER_PREFLIGHT_DISK_GB=240 \
    WALTER_PREFLIGHT_ALLOW_UNDERSIZED=1 \
    "$PREFLIGHT" full

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "override accepted"
}

@test "Walter-host docs recommend CX53 for full profile" {
  [[ -f "$WALTER_HOST_README" ]]
  [[ -f "$RESOURCE_BUDGET" ]]

  grep -Fq "FULL profile" "$WALTER_HOST_README"
  grep -Fq "CX53" "$WALTER_HOST_README"
  grep -Fq "16 vCPU / 32 GB RAM" "$WALTER_HOST_README"
  grep -Fq "Full stack, single operator" "$RESOURCE_BUDGET"
  grep -Fq "CX53" "$RESOURCE_BUDGET"
}
