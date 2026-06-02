#!/usr/bin/env bats
# tests/compose/port-allocation.bats
#
# Regression guard for issue #180: host-published Walter-VM ports need a
# central policy so new services do not silently collide or drift from the
# tunnel routing exceptions.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PORT_MAP="$REPO_ROOT/setup/walter-host/ports.tsv"
  PORT_DOC="$REPO_ROOT/setup/walter-host/PORTS.md"
  TUNNEL_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/02-create-tunnel.sh"
  [[ -f "$PORT_MAP" && -f "$PORT_DOC" && -f "$TUNNEL_SCRIPT" ]] || skip "missing port policy fixtures"
}

@test "#180: ports.tsv has the expected schema" {
  head -1 "$PORT_MAP" | grep -q $'^# service\trole\thost_port\tcontainer_port\tprotocol\texposure\tdeploy_group\tnotes$'

  awk -F '\t' '
    $0 ~ /^#/ { next }
    NF == 0 { next }
    NF != 8 { print "bad column count: " $0; bad = 1 }
    $3 !~ /^[0-9]+$/ { print "bad host_port: " $0; bad = 1 }
    $4 !~ /^[0-9]+$/ { print "bad container_port: " $0; bad = 1 }
    $5 !~ /^(tcp|udp)$/ { print "bad protocol: " $0; bad = 1 }
    $6 !~ /^(public|localhost)$/ { print "bad exposure: " $0; bad = 1 }
    END { exit bad ? 1 : 0 }
  ' "$PORT_MAP"
}

@test "#180: all-in-one host ports are unique by protocol" {
  local duplicates
  duplicates=$(awk -F '\t' '
    $0 ~ /^#/ { next }
    $7 == "all-in-one" {
      key = $3 "/" $5
      seen[key] = seen[key] ? seen[key] "," $1 ":" $2 : $1 ":" $2
      count[key]++
    }
    END {
      for (key in count) {
        if (count[key] > 1) print key " => " seen[key]
      }
    }
  ' "$PORT_MAP")

  if [[ -n "$duplicates" ]]; then
    printf 'Duplicate all-in-one host ports:\n%s\n' "$duplicates" >&2
    return 1
  fi
}

@test "#180: public all-in-one ports stay exceptional" {
  local unexpected
  unexpected=$(awk -F '\t' '
    $0 ~ /^#/ { next }
    $7 == "all-in-one" && $6 == "public" && $1 !~ /^(caddy|wireguard|syncthing)$/ {
      print $0
    }
  ' "$PORT_MAP")

  if [[ -n "$unexpected" ]]; then
    printf 'Unexpected public all-in-one ports:\n%s\n' "$unexpected" >&2
    return 1
  fi
}

@test "#180: tunnel PostHog override comes from ports.tsv" {
  grep -qF 'PORT_MAP_FILE=' "$TUNNEL_SCRIPT"
  grep -qF 'port map not readable' "$TUNNEL_SCRIPT"
  grep -qF 'missing port map entry' "$TUNNEL_SCRIPT"
  grep -qF 'port_map_lookup posthog tunnel host_port' "$TUNNEL_SCRIPT"
  grep -qF 'port_map_lookup posthog tunnel container_port' "$TUNNEL_SCRIPT"
  grep -q $'^posthog\ttunnel\t8100\t8000\ttcp\tlocalhost\tall-in-one\t' "$PORT_MAP"
}

@test "#180: known standalone published ports are listed" {
  grep -q $'^wireguard\tui\t51821\t51821\ttcp\tlocalhost\tstandalone/wireguard\t' "$PORT_MAP"
  grep -q $'^grafana\tui\t3030\t3000\ttcp\tlocalhost\tstandalone/observability\t' "$PORT_MAP"
}

@test "#180: runbook documents ranges and standalone collision rule" {
  grep -qF '3000-3099' "$PORT_DOC"
  grep -qF '5000-5999' "$PORT_DOC"
  grep -qF 'Standalone service compose files may reuse common ports' "$PORT_DOC"
  grep -qF 'setup/walter-host/ports.tsv' "$PORT_DOC"
}
