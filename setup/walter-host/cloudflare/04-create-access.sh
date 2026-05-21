#!/usr/bin/env bash
# 04-create-access.sh — create CF Access apps + email-domain policies.
#
# RUN AFTER: zone is in 'active' status (NS change propagated to CF).
#
# Required env: CF_EMAIL, CF_KEY, CF_ACCOUNT
# Args:
#   $1 = SERVICE_DOMAIN  (where services live, e.g. ${WALTER_DOMAIN})
#   $2 = AUTH_DOMAIN     (email domain allowed to login, e.g. example.com)
#                         If omitted, defaults to SERVICE_DOMAIN.
#   $3 = IDP_MODE        Optional: "otp" (default) | "otp+google"
#                         Use "otp+google" only if Google IdP is properly
#                         configured in CF (OAuth client exists in GCP).
#
# Idempotent: safe to re-run. Updates existing apps via PUT.

set -euo pipefail

: "${CF_EMAIL:?must set CF_EMAIL}"
: "${CF_KEY:?must set CF_KEY}"
: "${CF_ACCOUNT:?must set CF_ACCOUNT}"

SERVICE_DOMAIN="${1:?usage: $0 <service-domain> [auth-email-domain] [otp|otp+google]}"
AUTH_DOMAIN="${2:-$SERVICE_DOMAIN}"
IDP_MODE="${3:-otp}"

cf() {
  curl -sS -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" "$@"
}

echo "==> Verify zone $SERVICE_DOMAIN is active..."
ZONE_ID=$(cf "https://api.cloudflare.com/client/v4/zones?name=$SERVICE_DOMAIN&account.id=$CF_ACCOUNT" | jq -r '.result[0].id // empty')
[[ -z "$ZONE_ID" ]] && { echo "Zone $SERVICE_DOMAIN not found"; exit 2; }
ZONE_STATUS=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" | jq -r '.result.status')
[[ "$ZONE_STATUS" != "active" ]] && { echo "Zone status=$ZONE_STATUS; need active"; exit 2; }
echo "Zone active."

echo "==> Resolve IdPs..."
idps=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/identity_providers")
OTP_IDP=$(echo "$idps" | jq -r '.result[]? | select(.type=="onetimepin") | .id' | head -1)
GOOGLE_IDP=$(echo "$idps" | jq -r '.result[]? | select(.type=="google") | .id' | head -1)

if [[ -z "$OTP_IDP" ]]; then
  echo "Creating One-Time PIN IdP..."
  resp=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/identity_providers" \
    -d '{"name":"Email OTP","type":"onetimepin","config":{}}')
  OTP_IDP=$(echo "$resp" | jq -r '.result.id')
fi

case "$IDP_MODE" in
  otp)
    ALLOWED_IDPS="[\"$OTP_IDP\"]"
    echo "IdP mode: OTP-to-email only"
    ;;
  otp+google)
    if [[ -z "$GOOGLE_IDP" ]]; then
      echo "ERROR: --google requested but no Google IdP found in account."
      echo "Configure Google IdP in CF dashboard first (requires OAuth client in GCP)."
      exit 3
    fi
    ALLOWED_IDPS="[\"$OTP_IDP\",\"$GOOGLE_IDP\"]"
    echo "IdP mode: OTP + Google"
    echo "WARNING: Google IdP must have a working OAuth client in GCP. If you see"
    echo "         'OAuth client was deleted / Error 401: deleted_client', the"
    echo "         IdP is broken — re-create OAuth client or use 'otp' mode."
    ;;
  *) echo "Unknown IDP_MODE: $IDP_MODE (use 'otp' or 'otp+google')"; exit 2 ;;
esac

echo "==> Create/update Access app per service..."
# Single source of truth for which subdomains get a CF Access app.
# Add new services here when their cloudflared ingress lands — without an
# Access policy they'd be publicly reachable.
# NOTE: 'headscale' (control plane / federation) is intentionally EXCLUDED
# — Tailscale clients can't do interactive Google OAuth on the control
# plane. The HS admin UI is a separate Caddy site ('headscale-admin')
# and IS protected here.
for sub in vault llm plane git status home secrets uptime \
           n8n grafana penpot draw chat sync element claw headscale-admin vpn \
           tower metabase postiz; do
  # Per #136 + Codex R1 catch: any subdomain that imports admin_auth_gate
  # in the Caddy template needs a matching CF Access app. The
  # admin_auth_gate accepts either Tailscale tailnet IP OR a valid
  # CF-Access-Authenticated-User-Email header. Without a CF Access app
  # the public-internet path fails 403 even with valid auth elsewhere.
  # Codex R1 R1.1 caught that 'hs' (the old short name in this script)
  # didn't match 'headscale-admin' (the actual Caddy site label) —
  # renamed to keep the symmetry; operators with a legacy 'hs' Access
  # app can delete it manually. tests/compose/cf-access-coverage.bats
  # locks the symmetry in to prevent future drift.
  hostname="${sub}.${SERVICE_DOMAIN}"

  existing_apps=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps")
  app_id=$(echo "$existing_apps" | jq -r --arg d "$hostname" '.result[]? | select(.domain==$d) | .id' | head -1)

  app_payload="{
    \"name\": \"Walter-VM ${sub}\",
    \"domain\": \"${hostname}\",
    \"type\": \"self_hosted\",
    \"session_duration\": \"24h\",
    \"allowed_idps\": $ALLOWED_IDPS,
    \"auto_redirect_to_identity\": $([ "$IDP_MODE" = "otp" ] && echo true || echo false)
  }"

  if [[ -n "$app_id" ]]; then
    resp=$(cf -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$app_id" -d "$app_payload")
    if [[ "$(echo "$resp" | jq -r '.success')" == "true" ]]; then
      printf "  ✓ %s (updated)\n" "$hostname"
    else
      printf "  ✗ %s update — %s\n" "$hostname" "$(echo "$resp" | jq -c '.errors')"
      continue
    fi
  else
    resp=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps" -d "$app_payload")
    app_id=$(echo "$resp" | jq -r '.result.id // empty')
    if [[ -n "$app_id" ]]; then
      printf "  ✓ %s (created)\n" "$hostname"
    else
      printf "  ✗ %s — %s\n" "$hostname" "$(echo "$resp" | jq -c '.errors')"
      continue
    fi
  fi

  # Policy: allow only emails @AUTH_DOMAIN
  pol_list=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$app_id/policies")
  pol_id=$(echo "$pol_list" | jq -r '.result[0].id // empty')

  pol_payload="{
    \"name\": \"Allow @${AUTH_DOMAIN}\",
    \"decision\": \"allow\",
    \"include\": [{\"email_domain\": {\"domain\": \"${AUTH_DOMAIN}\"}}],
    \"session_duration\": \"24h\",
    \"precedence\": 1
  }"

  if [[ -n "$pol_id" ]]; then
    pol=$(cf -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$app_id/policies/$pol_id" -d "$pol_payload")
  else
    pol=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$app_id/policies" -d "$pol_payload")
  fi
  [[ "$(echo "$pol" | jq -r '.success')" == "true" ]] \
    && printf "    ✓ policy: allow @%s\n" "$AUTH_DOMAIN" \
    || printf "    ✗ policy — %s\n" "$(echo "$pol" | jq -c '.errors')"
done

echo
echo "==> Done. Services on *.${SERVICE_DOMAIN} require email auth from @${AUTH_DOMAIN}."
echo "==> Login methods: $([ "$IDP_MODE" = "otp" ] && echo 'OTP-to-email only' || echo 'OTP + Google')"
[[ "$IDP_MODE" = "otp" ]] && echo "    To add Google one-click: see setup/walter-host/cloudflare/google-idp-fix.md"
echo "==> Test: open https://vault.${SERVICE_DOMAIN} — should redirect to Access login."
