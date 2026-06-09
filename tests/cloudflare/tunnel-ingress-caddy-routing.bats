#!/usr/bin/env bats
# tests/cloudflare/tunnel-ingress-caddy-routing.bats
#
# Regression guard for issue #174 — cloudflared tunnel ingress map gap.
# After the fix, the tunnel must route every Cloudflare-compatible subdomain
# that Caddy already handles. Protocol-incompatible services must be listed in
# DIRECT_ROUTE_SUBDOMAINS with an explicit comment and stay out of the tunnel.
# The default architecture is:
#
#     internet --(TLS)--> cloudflared --(plain HTTP)--> Caddy --(Docker DNS)--> container
#
# Cloudflared is the public TLS edge; Caddy is the internal reverse proxy.
# The old config bypassed Caddy and routed 8 subdomains directly to host
# ports, leaving 15+ services (grafana, matrix, element, posthog, n8n,
# rocketchat, metabase, drawio, penpot, syncthing, openclaw, control-tower,
# vpn, sync, posthog, postiz, hermes, etc.) publicly unreachable.
#
# The fix routes every compatible subdomain to Caddy on host port 80, so the
# routing table lives in ONE place (the Caddyfile) instead of being split
# across cloudflared and Caddy with drift between them.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TUNNEL_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/02-create-tunnel.sh"
  CADDYFILE_TEMPLATE="$REPO_ROOT/setup/caddy/Caddyfile.template"
}

# ---------------------------------------------------------------------------
# Helpers — separated so each test asserts against the right source-of-truth
# (Copilot R1 #188 finding):
#
#   _subdomains_array     : ONLY the SUBDOMAINS bash array literal — the
#                           single source-of-truth the ingress emitter
#                           iterates. AC-1 / AC-4 validate against this.
#                           A subdomain that drops out of SUBDOMAINS but
#                           lingers in some legacy for-loop must NOT
#                           silently pass.
#
#   _for_loop_subdomains  : the CNAME-create for-loop's word list. After
#                           Copilot R1, the loop iterates `${SUBDOMAINS[@]}`
#                           directly — in that case this helper just
#                           defers back to the array, which keeps any
#                           future drift detectable.
#
#   _direct_route_exclusions : protocol-incompatible subdomains that Caddy
#                              still serves but Cloudflare Tunnel must not.
# ---------------------------------------------------------------------------
_subdomains_array() {
  awk '/^SUBDOMAINS=\(/{capture=1; next} capture && /^\)/{capture=0} capture {print}' "$TUNNEL_SCRIPT" \
    | tr -s ' \t' '\n' \
    | grep -E '^[a-z][a-z0-9-]*$'
}

_direct_route_exclusions() {
  awk '/^DIRECT_ROUTE_SUBDOMAINS=\(/{capture=1; next} capture && /^\)/{capture=0} capture {print}' "$TUNNEL_SCRIPT" \
    | tr -s ' \t' '\n' \
    | grep -E '^[a-z][a-z0-9-]*$' || true
}

_for_loop_subdomains() {
  local block
  block=$(awk '/for sub in/,/do$/' "$TUNNEL_SCRIPT")
  if [[ "$block" == *'"${SUBDOMAINS[@]}"'* ]]; then
    # Loop iterates the array literal — defer to the array. Any drift
    # surfaces in AC-1 (against the array) rather than producing a
    # false-positive AC-4 from a stale flat list.
    _subdomains_array
    return
  fi
  printf '%s\n' "$block" \
    | tr '\\' ' ' \
    | tr -s ' \t' '\n' \
    | grep -E '^[a-z][a-z0-9-]*$' \
    | grep -vE '^(for|sub|in|do)$'
}

# ---------------------------------------------------------------------------
# AC-1: every compatible Caddy subdomain has a tunnel ingress entry
# ---------------------------------------------------------------------------

@test "AC-1: tunnel ingress includes every compatible subdomain from Caddyfile.template" {
  [[ -f "$CADDYFILE_TEMPLATE" ]] || skip "Caddyfile.template missing"
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # Extract the subdomain prefix (the bit before `.${WALTER_DOMAIN}`) from
  # every site block in Caddyfile.template.
  local caddy_subs
  caddy_subs=$(grep -E '^[a-z][a-z0-9.-]*\.\$\{WALTER_DOMAIN\} \{' \
    "$CADDYFILE_TEMPLATE" \
    | sed -E 's/\.\$\{WALTER_DOMAIN\}.*//' \
    | sort -u)

  [[ -n "$caddy_subs" ]] || skip "no subdomains parsed from Caddyfile.template"

  # Validate against the SUBDOMAINS array specifically — NOT a combined
  # set with the for-loop fallback (Copilot R1 #188). The ingress emitter
  # only iterates SUBDOMAINS, so that array is the source of truth that
  # must contain every Caddy subdomain.
  local script_subs direct_subs
  script_subs=$(_subdomains_array | sort -u)
  direct_subs=$(_direct_route_exclusions | sort -u)

  local missing=()
  while read -r sub; do
    if grep -qE "^${sub}$" <<< "$direct_subs"; then
      continue
    fi
    if ! grep -qE "^${sub}$" <<< "$script_subs"; then
      missing+=("$sub")
    fi
  done <<< "$caddy_subs"

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing from SUBDOMAINS array: %s\n' "${missing[*]}"
    printf 'SUBDOMAINS currently contains:\n%s\n' "$script_subs"
    printf 'DIRECT_ROUTE_SUBDOMAINS currently contains:\n%s\n' "$direct_subs"
    return 1
  fi
}

@test "AC-1b: headscale is direct-routed, not Cloudflare-tunnelled" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  _direct_route_exclusions | grep -Fxq "headscale"
  ! _subdomains_array | grep -Fxq "headscale"
  grep -Fq "Cloudflare does not support the WebSocket POSTs required by Headscale" "$TUNNEL_SCRIPT"
}

# ---------------------------------------------------------------------------
# AC-2: ingress entries route to Caddy, except documented service overrides
# ---------------------------------------------------------------------------

@test "AC-2: no ingress entry routes directly to undocumented per-service host ports" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # Per-service ports that the old broken config referenced (8222 / 4000 /
  # 8090 / 3000 / 3001 / 3010 / 8800) are no longer the dispatch target —
  # Caddy at port 80 is. Allow port 80 and 443 in the script (Caddy's
  # ports) plus the documented PostHog proxy override on port 8100; flag
  # any other 127.0.0.1:<port> reference anywhere in non-comment lines.
  #
  # Use `|| true` after each pipe so an empty-result grep doesn't propagate
  # exit 1 (which bats would treat as a test failure on the assignment).
  local bad
  bad=$( { grep -nE "http://127\\.0\\.0\\.1:[0-9]+" "$TUNNEL_SCRIPT" || true; } \
    | { grep -vE 'http://127\.0\.0\.1:(80|443|8100)([^0-9]|$)' || true; } \
    | { grep -vE ':\s*#' || true; } )

  if [[ -n "$bad" ]]; then
    printf 'Ingress entries bypassing Caddy (should route to :80):\n%s\n' "$bad"
    return 1
  fi
}

@test "AC-2b: PostHog override targets its proxy and rewrites Host header" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  grep -q "port_map_lookup posthog tunnel host_port" "$TUNNEL_SCRIPT"
  grep -q "port_map_lookup posthog tunnel container_port" "$TUNNEL_SCRIPT"
  grep -q "httpHostHeader: localhost:%s" "$TUNNEL_SCRIPT"
}

@test "AC-2c: tunnel script stays compatible with macOS bash 3.2" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  ! grep -q 'declare -A' "$TUNNEL_SCRIPT"
}

# ---------------------------------------------------------------------------
# AC-3: the wildcard catch-all 404 is the LAST ingress rule
# ---------------------------------------------------------------------------

@test "AC-3: catch-all http_status:404 is the final ingress entry" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # Two assertions (Copilot R1 #188):
  #   (a) the http_status:404 literal appears EXACTLY ONCE in the script
  #       (no accidental duplicate would silently become the catch-all)
  #   (b) the 404 printf is the LAST ingress-emitting printf — i.e., no
  #       `hostname:`-emitting printf appears after it. Otherwise
  #       cloudflared would short-circuit on the 404 before reaching the
  #       real ingress.
  #
  # NB: avoid `count=$(grep -c ... || echo 0)` — when grep finds 0
  # matches, it exits 1, and the `|| echo 0` produces a multi-line value.
  # Use grep -c with a fallback assignment that doesn't chain echo.
  local count
  count=$(grep -c 'http_status:404' "$TUNNEL_SCRIPT" || true)
  count=${count:-0}
  [[ "$count" -eq 1 ]] || {
    printf 'http_status:404 occurrences: %d (expected exactly 1)\n' "$count" >&2
    return 1
  }

  # Ordering: extract the config-generation block (between the printf for
  # 'ingress:\n' and the redirect to config.yml) and confirm no `hostname:`
  # printf appears AFTER the 404 line.
  local block_lines
  block_lines=$(awk '/printf .ingress:/,/} > .*config\.yml/' "$TUNNEL_SCRIPT")
  local last_ingress_printf
  last_ingress_printf=$(printf '%s\n' "$block_lines" \
    | grep -nE 'printf .* (hostname|http_status):' \
    | tail -1)
  [[ "$last_ingress_printf" == *"http_status:404"* ]] || {
    echo "Last ingress printf is NOT the http_status:404 catch-all:" >&2
    echo "  $last_ingress_printf" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC-4: CNAME loop covers every compatible Caddy subdomain too
# ---------------------------------------------------------------------------

@test "AC-4: add_cname loop covers every tunnel-compatible subdomain in the ingress" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"
  [[ -f "$CADDYFILE_TEMPLATE" ]] || skip "Caddyfile.template missing"

  # Every subdomain in the Caddy template must appear in the CNAME-create
  # loop. Use the same multi-line-aware helper as AC-1.
  local caddy_subs
  caddy_subs=$(grep -E '^[a-z][a-z0-9.-]*\.\$\{WALTER_DOMAIN\} \{' \
    "$CADDYFILE_TEMPLATE" \
    | sed -E 's/\.\$\{WALTER_DOMAIN\}.*//' \
    | sort -u)

  # Validate against the CNAME for-loop specifically. _for_loop_subdomains
  # returns the array (via fallback) when the loop iterates
  # `${SUBDOMAINS[@]}`, so this asserts a real "would the CNAME be
  # created" property regardless of whether the loop is direct or array-
  # backed.
  local loop_subs direct_subs
  loop_subs=$(_for_loop_subdomains | sort -u)
  direct_subs=$(_direct_route_exclusions | sort -u)

  local missing=()
  while read -r sub; do
    if grep -qE "^${sub}$" <<< "$direct_subs"; then
      continue
    fi
    if ! grep -qE "^${sub}$" <<< "$loop_subs"; then
      missing+=("$sub")
    fi
  done <<< "$caddy_subs"

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'CNAME loop missing Caddy subdomains: %s\n' "${missing[*]}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-5: documentation — the script header references the architecture
# ---------------------------------------------------------------------------

@test "AC-5: script header documents the cloudflared -> Caddy -> container chain" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # The cloudflared -> Caddy -> container architecture must be documented
  # in the script header so an operator reading the file understands why
  # the ingress points at port 80 and not per-service ports.
  head -40 "$TUNNEL_SCRIPT" | grep -qiE "Caddy" || {
    echo "Script header does not mention Caddy — architecture is undocumented." >&2
    return 1
  }
}
