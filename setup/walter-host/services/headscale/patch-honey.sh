#!/bin/sh
# patch-honey.sh — runs at headscale-admin container startup.
#
# Defense in depth against the Honey/PayPal extension localStorage injection
# collision. The extension writes `debug=honey:core-sdk:*` globally; SvelteKit
# then JSON.parses that string at deserialize time and crashes (the
# "purple-screen" / blank-content bug). Two-stage fix:
#
#   1. Inject a one-liner into index.html that clears localStorage.debug if
#      it starts with "honey".
#   2. Wrap every JSON.parse call across all SvelteKit JS chunks with a
#      try/catch fallback that returns null on bad input.
#
# Both stages are idempotent (guard checks skip already-patched files).
# Lives outside compose.yml so YAML escape rules don't break the regex
# patterns. Mounted into /usr/local/bin/patch-honey.sh by compose.

set -u

echo "[honey-fix] starting patch pass at $(date -u +%FT%TZ)"

INDEX=/app/admin/index.html
CHUNK_GLOB='/app/admin/_app/immutable/chunks/*.js /app/admin/_app/immutable/entry/*.js'

# Stage 1: index.html cleanup script.
if ! grep -q 'honey-fix' "$INDEX" 2>/dev/null; then
  sed -i 's|<head>|<head><script id="honey-fix">try{var d=localStorage.getItem("debug");if(d \&\& d.indexOf("honey")===0){localStorage.removeItem("debug");}}catch(e){}</script>|' "$INDEX"
  echo "[honey-fix]   index.html: injected cleanup script"
else
  echo "[honey-fix]   index.html: already patched"
fi

# Stage 2: wrap JSON.parse in every chunk that has it. Idempotent — guards
# against already-wrapped files via the wrapper signature.
patched=0
skipped=0
unpatched_chunks=$(eval "ls $CHUNK_GLOB" 2>/dev/null)
for f in $unpatched_chunks; do
  [ -f "$f" ] || continue
  if grep -q 'JSON\.parse' "$f" 2>/dev/null && ! grep -q 'try{return JSON\.parse' "$f" 2>/dev/null; then
    sed -i 's|JSON\.parse|((s)=>{try{return JSON.parse(s)}catch{return null}})|g' "$f"
    patched=$((patched + 1))
    echo "[honey-fix]     patched: $f"
  else
    skipped=$((skipped + 1))
  fi
done
echo "[honey-fix]   chunks: patched=$patched skipped=$skipped"

# Stage 3: write Caddyfile that redirects / → /admin/ (idempotent — same
# content every run).
cat > /etc/caddy/Caddyfile <<'CADDYFILE'
:80
root * /app
encode gzip zstd
@root path /
redir @root /admin/ 302
try_files {path}.html {path}
file_server
CADDYFILE
echo "[honey-fix] handing off to caddy"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
