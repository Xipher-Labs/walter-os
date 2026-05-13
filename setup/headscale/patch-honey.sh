#!/bin/sh
# patch-honey.sh — fix headscale-admin localStorage.debug crash
#
# Custom entrypoint for goodieshq/headscale-admin. Patches index.html
# to clear localStorage.debug if populated by Honey/PayPal browser
# extensions (which inject debug=honey:core-sdk:*; SvelteKit then
# JSON.parse-crashes).
#
# Upstream bug — fix lives here until goodieshq/headscale-admin wraps
# its localStorage deserialize in try/catch.

set -e

INDEX="/app/build/index.html"

if [ -f "$INDEX" ]; then
  # Prepend a script to clear debug key before SvelteKit hydrates
  sed -i 's|<head>|<head><script>try{var d=localStorage.getItem("debug");if(d\&\&d.indexOf("honey")>-1)localStorage.removeItem("debug")}catch(e){}</script>|' "$INDEX" 2>/dev/null || true
fi

# Start the original server
exec node /app/build/index.js
