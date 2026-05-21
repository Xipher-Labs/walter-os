#!/usr/bin/env bats
# tests/compose/cf-access-coverage.bats
#
# Closes #136: every site that imports `admin_auth_gate` in
# `setup/caddy/Caddyfile.template` MUST have a matching CF Access app
# in `setup/walter-host/cloudflare/04-create-access.sh`. Without that
# pairing, the admin_auth_gate's CF-Access-header check is satisfied
# for the wrong subset of subdomains (or none at all), and the
# tier-4.md install verification command (`curl ... | expect 302`)
# silently breaks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CADDYFILE="$REPO_ROOT/setup/caddy/Caddyfile.template"
  CF_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/04-create-access.sh"
  [[ -f "$CADDYFILE" && -f "$CF_SCRIPT" ]] || skip "missing fixtures"
}

# -----------------------------------------------------------------------
# AC: tower has a CF Access app
# -----------------------------------------------------------------------
@test "#136: 04-create-access.sh includes tower in the subdomain loop" {
  # Loose match — tolerates line-continuation formatting in the for loop.
  grep -qE '\btower\b' "$CF_SCRIPT"
}

# -----------------------------------------------------------------------
# AC: every site that imports admin_auth_gate has a CF Access app.
# This is the structural assertion that prevents future drift.
# -----------------------------------------------------------------------
@test "#136: every admin_auth_gate site has a CF Access app (except documented exclusions)" {
  # Extract the subdomains that import admin_auth_gate.
  local gated_subs
  gated_subs=$(awk '
    /^[a-z][a-z0-9-]*\.\$\{WALTER_DOMAIN\} \{/ {
      sub(/\..*/, "", $1)
      site=$1
    }
    /import admin_auth_gate/ {
      print site
    }
  ' "$CADDYFILE" | sort -u)

  # Extract the for-loop subdomain list from the CF script. Slurp every
  # line between `for sub in` and the matching `; do`, then split on
  # whitespace + line continuations.
  local cf_subs
  cf_subs=$(awk '
    /^for sub in/ {flag=1}
    flag {print}
    /; do$/ && flag {flag=0}
  ' "$CF_SCRIPT" | tr -d '\\' | tr '\n' ' ' | sed 's/for sub in //;s/; do.*//' | tr ' ' '\n' | grep -v '^$' | sort -u)

  # Compute set difference: subs that have admin_auth_gate but no CF app.
  # No exclusions: this commit aligned the CF script's subdomain
  # naming with the Caddy site labels (`hs` → `headscale-admin`).
  # Future admin sites added to the Caddyfile MUST also be added
  # to the CF script's loop — this assertion catches the drift.
  local exclusions=""
  local missing
  missing=$(comm -23 <(printf '%s\n' "$gated_subs") <(printf '%s\n' "$cf_subs"))
  # Remove any documented exclusions.
  if [ -n "$exclusions" ]; then
    while read -r ex; do
      missing=$(printf '%s\n' "$missing" | grep -v "^${ex}$" || true)
    done <<<"$exclusions"
  fi

  if [ -n "$missing" ]; then
    printf 'admin_auth_gate sites missing a CF Access app:\n%s\n' "$missing" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# AC: the documented exclusion (headscale) is intentional + documented.
# -----------------------------------------------------------------------
@test "#136: headscale exclusion is documented in CF script comment" {
  grep -qE "'headscale'.*EXCLUDED" "$CF_SCRIPT"
}
