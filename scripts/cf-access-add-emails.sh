#!/usr/bin/env bash
# cf-access-add-emails.sh — add extra emails / domains / users to a Walter-VM
# Cloudflare Access app's allow policy. The default policy is "@${WALTER_DOMAIN}" only;
# this script lets you add specific emails (collaborators) or other domains.
#
# Usage:
#   cf-access-add-emails.sh <subdomain> <email-or-domain>...
#
# Examples:
#   # Add specific email to grafana
#   cf-access-add-emails.sh grafana socio@example.com
#
#   # Add specific email + a 3rd-party domain to plane (collaborators with [Company])
#   cf-access-add-emails.sh plane @[company].com teammate@example.com
#
# The script appends to the EXISTING policy (preserves @${WALTER_DOMAIN}). It does NOT
# delete current allow rules.

set -euo pipefail
[[ -f "$HOME/.config/walter-os/secrets.env" ]] && source "$HOME/.config/walter-os/secrets.env"
: "${WALTER_DOMAIN:?WALTER_DOMAIN required — source secrets.env first}"
: "${CF_EMAIL:?required}"
: "${CF_KEY:?required}"
: "${CF_ACCOUNT:?required}"

cf() { curl -fsS -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_KEY}" -H "Content-Type: application/json" "$@"; }

[[ $# -lt 2 ]] && { echo "Usage: $0 <subdomain> <email-or-@domain>..."; exit 2; }
sub="$1"; shift
domain="${sub}.${WALTER_DOMAIN}"

# Find app
APP=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps" \
  | jq -r --arg d "$domain" '.result[] | select(.domain==$d) | .id')
[[ -z "$APP" ]] && { echo "✗ no Access app for $domain"; exit 2; }

# Find existing allow policy
POL=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$APP/policies" \
  | jq -r '.result[] | select(.decision=="allow") | .id' | head -1)

if [[ -z "$POL" ]]; then
  echo "✗ no allow policy on $domain — create the app first via 04-create-access.sh"
  exit 2
fi

# Fetch the FULL existing policy. CF Access PUT replaces the whole resource —
# if we only sent name/decision/include we'd silently drop `require` (MFA),
# `exclude` (deny rules), `purpose_justification_required`, `approval_groups`,
# `isolation_required`, `connection_rules`, etc. Round-trip the full body and
# only mutate `include`.
CURRENT_POLICY=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$APP/policies/$POL" \
  | jq '.result')

# Compute the new `include` array (existing + new).
NEW_INCLUDE=$(jq -n --argjson cur "$(echo "$CURRENT_POLICY" | jq '.include')" '
  $cur as $existing |
  reduce $ARGS.positional[] as $arg (
    {existing: $existing, new: []};
    if ($arg | startswith("@")) then
      .new += [{"email_domain": {"domain": ($arg | ltrimstr("@"))}}]
    else
      .new += [{"email": {"email": $arg}}]
    end
  )
  | .existing + .new
' --args "$@")

# Patch only `include` on the full policy body. Strip the read-only `id` /
# `created_at` / `updated_at` fields CF rejects on PUT.
PATCH=$(echo "$CURRENT_POLICY" | jq --argjson include "$NEW_INCLUDE" '
  .include = $include
  | del(.id, .created_at, .updated_at, .uid, .reusable)
')

resp=$(cf -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/apps/$APP/policies/$POL" -d "$PATCH")
ok=$(echo "$resp" | jq -r '.success')

if [[ "$ok" == "true" ]]; then
  echo "✓ updated $domain — included rules:"
  echo "$resp" | jq -r '.result.include[] | "    - " + (.email.email // ("@" + .email_domain.domain) // "?")'
else
  echo "✗ failed: $(echo "$resp" | jq -c '.errors')"
  exit 1
fi
