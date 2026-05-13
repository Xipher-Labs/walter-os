#!/usr/bin/env bash
# Walter-VM Singer prereqs checker
#
# Checks that all required env vars and API approvals are in place
# before running Singer taps. Reports PENDING for unapproved APIs.
# Does NOT block deployment — informs and exits 0.
#
# Usage:
#   ./check-prereqs.sh
#   ./check-prereqs.sh --strict    # Exit 1 if any required prereq is missing
#
# Refs: docs/specs/devrel-analytics-stack.md
#       docs/operational/council-v2-prereqs.md (V-prereq-1 through V-prereq-9)

STRICT=false
[[ "${1:-}" == "--strict" ]] && STRICT=true

STATUS_OK=0
STATUS_PENDING=0
STATUS_MISSING=0

check_var() {
  local var="$1"
  local label="$2"
  local prereq="$3"
  local tier="${4:-}"

  local val="${!var:-}"
  if [[ -z "$val" ]]; then
    echo "  PENDING  $label — $var not set"
    echo "           Prereq: $prereq"
    [[ -n "$tier" ]] && echo "           Tier: $tier"
    STATUS_PENDING=$((STATUS_PENDING + 1))
  elif [[ "$val" == "PENDING_APPROVAL" || "$val" == "PENDING_APP_REVIEW" || "$val" == "CHANGE_ME" ]]; then
    echo "  PENDING  $label — $var is placeholder"
    echo "           Action: $prereq"
    STATUS_PENDING=$((STATUS_PENDING + 1))
  else
    echo "  OK       $label — configured"
    STATUS_OK=$((STATUS_OK + 1))
  fi
}

check_bin() {
  local bin="$1"
  local pkg="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  OK       $bin installed ($(command -v "$bin"))"
    STATUS_OK=$((STATUS_OK + 1))
  else
    echo "  missing  $bin — install: pip install $pkg"
    STATUS_MISSING=$((STATUS_MISSING + 1))
  fi
}

echo "=== Walter DevRel Analytics — Singer Prereqs Check ==="
echo ""

echo "── Tier 1 (no approval needed) ──────────────────────"
check_var "ANALYTICS_DB_URL"   "Analytics DB"     "Set postgresql:// URL in Infisical or .env"
check_var "YT_CHANNEL_ID"      "YouTube Channel"  "Set your YouTube channel ID (no API approval needed)"
check_var "PLAUSIBLE_URL"      "Plausible URL"    "Set self-hosted Plausible URL (e.g. http://plausible.walter.lan)"
check_var "GITHUB_ORG"         "GitHub Org"       "Set GitHub org/user (e.g. your-org)"
check_var "GITHUB_REPO"        "GitHub Repo"      "Set target repo name"
check_var "BSKY_HANDLE"        "Bluesky Handle"   "Set handle (e.g. you.bsky.social)"

echo ""
echo "── Tier 2 (API approval, 3-15 days) ─────────────────"
check_var "GOOGLE_ADS_DEVELOPER_TOKEN" \
  "Google Ads Developer Token" \
  "V-prereq-1: Apply at ads.google.com → Tools → API Center (3-5 days)" \
  "Tier 2"
check_var "META_ACCESS_TOKEN" \
  "Meta App Review" \
  "V-prereq-2: Submit app for ads_read scope at developers.facebook.com (5-15 days)" \
  "Tier 2"
check_var "GA4_PROPERTY_ID" \
  "Google Analytics 4" \
  "GA4 is optional — only needed if Plausible doesn't cover enough" \
  "Tier 2 (optional)"

echo ""
echo "── Tier 3 (LinkedIn — multi-week) ───────────────────"
check_var "LINKEDIN_ACCESS_TOKEN" \
  "LinkedIn Marketing Developer Platform" \
  "V-prereq-3: Apply at learn.microsoft.com/en-us/linkedin/marketing/integrations" \
  "Tier 3 (may take weeks)"

echo ""
echo "── Python Singer packages (install on walter-vm) ────"
check_bin "tap-google-ads"       "tap-google-ads"
check_bin "tap-facebook"         "tap-facebook"
check_bin "tap-google-analytics" "tap-google-analytics"
check_bin "tap-linkedin-ads"     "tap-linkedin-ads"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Results: OK=$STATUS_OK  PENDING=$STATUS_PENDING  MISSING=$STATUS_MISSING"

if [[ "$STATUS_MISSING" -gt 0 ]]; then
  echo ""
  echo "ACTION REQUIRED: Install missing packages on walter-vm:"
  echo "  pip install singer-python tap-google-ads tap-facebook tap-google-analytics tap-linkedin-ads"
fi

if [[ "$STATUS_PENDING" -gt 0 ]]; then
  echo ""
  echo "NOTE: $STATUS_PENDING item(s) PENDING approval."
  echo "  Tier 1 items can be configured immediately."
  echo "  Tier 2/3 require paperwork — start the process NOW if not done."
fi

if $STRICT && [[ "$STATUS_MISSING" -gt 0 ]]; then
  exit 1
fi

exit 0
