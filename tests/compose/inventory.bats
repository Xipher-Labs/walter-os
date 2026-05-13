#!/usr/bin/env bats
# RED test: SERVICES-INVENTORY.md must exist and contain every service
# Covers: Task 1 verification (manual review gate)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INVENTORY="$REPO_ROOT/setup/SERVICES-INVENTORY.md"
}

@test "setup/SERVICES-INVENTORY.md exists" {
  [ -f "$INVENTORY" ]
}

@test "inventory contains postgres entry" {
  grep -qi "postgres" "$INVENTORY"
}

@test "inventory contains plane entry" {
  grep -qi "plane" "$INVENTORY"
}

@test "inventory contains forgejo entry" {
  grep -qi "forgejo" "$INVENTORY"
}

@test "inventory contains infisical entry" {
  grep -qi "infisical" "$INVENTORY"
}

@test "inventory contains litellm entry" {
  grep -qi "litellm" "$INVENTORY"
}

@test "inventory contains grafana entry" {
  grep -qi "grafana" "$INVENTORY"
}

@test "inventory contains prometheus entry" {
  grep -qi "prometheus" "$INVENTORY"
}

@test "inventory contains n8n entry" {
  grep -qi "n8n" "$INVENTORY"
}

@test "inventory contains caddy entry" {
  grep -qi "caddy" "$INVENTORY"
}

@test "inventory contains wireguard entry" {
  grep -qi "wireguard\|wg-easy" "$INVENTORY"
}

@test "inventory contains headscale entry" {
  grep -qi "headscale" "$INVENTORY"
}

@test "inventory contains syncthing entry" {
  grep -qi "syncthing" "$INVENTORY"
}

@test "inventory contains uptime-kuma entry" {
  grep -qi "uptime.kuma" "$INVENTORY"
}

@test "inventory contains postiz entry" {
  grep -qi "postiz" "$INVENTORY"
}

@test "inventory contains penpot entry" {
  grep -qi "penpot" "$INVENTORY"
}

@test "inventory contains drawio entry" {
  grep -qi "drawio" "$INVENTORY"
}

@test "inventory contains openclaw entry" {
  grep -qi "openclaw" "$INVENTORY"
}

@test "inventory contains synapse entry" {
  grep -qi "synapse" "$INVENTORY"
}

@test "inventory contains rocketchat entry" {
  grep -qi "rocketchat\|rocket" "$INVENTORY"
}

@test "inventory contains homepage entry" {
  grep -qi "homepage" "$INVENTORY"
}
