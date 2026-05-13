#!/usr/bin/env bash
# syncthing-bootstrap.sh — register Walter-VM Syncthing folders via REST API.
#
# The compose.yml comments document four expected folders + we add agent-memory
# in Phase 2. This script connects to the Syncthing REST API on walter-vm
# (via SSH tunnel through cloudflared) and creates / updates each folder.
#
# Idempotent — checks existing config and only adds folders that are missing.
# Does NOT pair operator devices (that's interactive and stays in the web UI).
#
# Prereqs:
#   - SSH access to walter-vm via cloudflared (verify: ssh walter-vm hostname)
#   - Syncthing container running on walter-vm
#
# Usage:
#   walter-os syncthing-bootstrap              # use defaults
#   walter-os syncthing-bootstrap --dry-run    # show what would happen

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

WALTER_VM="${WALTER_VM_SSH_ALIAS:-walter-vm}"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

# Folders we expect to exist on the hub. (id, label, host_path, type)
# host_path is mapped to /sync/<name> inside the container per compose.yml.
# type=sendreceive — the hub mirrors changes from any paired device.
FOLDERS=(
  "obsidian-vault|Obsidian Vault|/sync/obsidian-vault|sendreceive"
  "projects-personal|Projects Personal|/sync/projects-personal|sendreceive"
  "personal|Personal Notes|/sync/personal|sendreceive"
  "screenshots|Screenshots|/sync/screenshots|sendreceive"
  "agent-memory|Agent Memory|/sync/agent-memory|sendreceive"
  "desktop|Desktop|/sync/desktop|sendreceive"
  "documents|Documents|/sync/documents|sendreceive"
  "downloads|Downloads|/sync/downloads|sendreceive"
  "work|Work|/sync/work|sendreceive"
)

# .stignore patterns per folder. SEEDED on the hub at
# /mnt/walter-vm-data/sync/<id>/.stignore — Syncthing then replicates the
# .stignore file itself to every paired device, so the patterns apply on
# both sides. Keeps node_modules / build artifacts / huge binaries OUT of
# sync. Operator can override locally — these are just the initial seeds.
declare -A IGNORE_PATTERNS=(
  [downloads]=$'# Walter-OS stignore — seed for ~/Downloads\n*.dmg\n*.pkg\n*.iso\n*.crdownload\n*.tmp\n*.partial\n.DS_Store\n# Anything > ~100MB you don\'t want sync\'d should go here\n*.zip\n*.tar.gz\n*.tar.zst'
  [work]=$'# Walter-OS stignore — seed for ~/work\n# Aggressive: keep repos lean. Source files + configs + docs only.\nnode_modules\n.next\n.nuxt\ndist\nbuild\ntarget\n.cargo\nout\ncoverage\n.cache\n.parcel-cache\n.turbo\n.svelte-kit\n.docusaurus\n.vercel\n.netlify\n.terraform\nvendor\n.venv\nvenv\n__pycache__\n.pytest_cache\n.mypy_cache\n.ruff_cache\n.tox\n# Build artifacts\n*.pyc\n*.so\n*.o\n*.a\n*.dylib\n# IDE local state\n.idea\n.vscode/.history\n.DS_Store'
  [documents]=$'# Walter-OS stignore — seed for ~/Documents\n.DS_Store\n*.tmp\n~$*'
  [desktop]=$'# Walter-OS stignore — seed for ~/Desktop\n.DS_Store\n*.tmp'
)

step "Fetch Syncthing API key from container"
# Use sed for portability — busybox/alpine grep lacks -P (PCRE).
API_KEY="$(ssh "$WALTER_VM" "docker exec syncthing sh -c 'sed -n \"s|.*<apikey>\\(.*\\)</apikey>.*|\\1|p\" /config/config.xml | head -1' 2>/dev/null" 2>/dev/null || true)"
if [[ -z "$API_KEY" ]]; then
  err "Could not read API key from /config/config.xml in syncthing container"
  err "  Verify: ssh $WALTER_VM 'docker ps --filter name=syncthing'"
  exit 1
fi
ok "API key obtained (${#API_KEY} chars)"

# Helper — exec a curl on the VM against the local Syncthing API. We can't
# hit the API from outside because CF Access is in front + the API doesn't
# accept browser tokens. Variables expand on the CLIENT side intentionally
# (we want the values baked into the remote command), so SC2029 is silenced.
sapi() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    # shellcheck disable=SC2029 # client-side expansion is intentional
    ssh "$WALTER_VM" "curl -fsS -X $method 'http://127.0.0.1:8384${path}' -H 'X-API-Key: $API_KEY' -H 'Content-Type: application/json' -d '$body'"
  else
    # shellcheck disable=SC2029
    ssh "$WALTER_VM" "curl -fsS -X $method 'http://127.0.0.1:8384${path}' -H 'X-API-Key: $API_KEY'"
  fi
}

step "Read current Syncthing config"
EXISTING="$(sapi GET /rest/config/folders 2>/dev/null || echo '[]')"
if [[ -z "$EXISTING" ]]; then
  err "Empty response from /rest/config/folders. Is the API key valid?"
  exit 1
fi
EXISTING_IDS="$(echo "$EXISTING" | jq -r '.[].id' | sort)"
info "Currently configured folders:"
if [[ -z "$EXISTING_IDS" ]]; then
  info "  (none)"
else
  printf '  %s\n' "${EXISTING_IDS//$'\n'/$'\n  '}"
fi

step "Reconcile expected folders"
ADDED=0; SKIPPED=0
for spec in "${FOLDERS[@]}"; do
  IFS='|' read -r id label path type <<< "$spec"

  if echo "$EXISTING_IDS" | grep -qx "$id"; then
    info "skip: $id (already configured)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Build folder object. Minimum required fields per Syncthing API.
  body=$(jq -nc \
    --arg id "$id" \
    --arg label "$label" \
    --arg path "$path" \
    --arg type "$type" \
    '{id: $id, label: $label, path: $path, type: $type, devices: [], rescanIntervalS: 60, fsWatcherEnabled: true, ignorePerms: false}')

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] would POST /rest/config/folders: $body"
    continue
  fi

  if sapi POST /rest/config/folders "$body" >/dev/null 2>&1; then
    ok "added: $id ($label) → $path"
    ADDED=$((ADDED + 1))
  else
    err "failed: $id"
  fi
done

echo
echo "Summary: added=${ADDED}  skipped=${SKIPPED}  dry_run=${DRY_RUN}"

# Host dirs + .stignore seeding runs on EVERY non-dry-run, not just when new
# folders were added. Operator may want to update ignore patterns over time
# (e.g., add a new build-artifact dir to skip in work/) — gating on ADDED>0
# would silently drop those updates.
if [[ "$DRY_RUN" -eq 0 ]]; then
  step "Ensure host directories exist"
  for spec in "${FOLDERS[@]}"; do
    IFS='|' read -r id _ _ _ <<< "$spec"
    # shellcheck disable=SC2029 # $id expands client-side intentionally
    if ssh "$WALTER_VM" "sudo mkdir -p /mnt/walter-vm-data/sync/$id && sudo chown 1000:1000 /mnt/walter-vm-data/sync/$id" 2>/dev/null; then
      ok "host dir: /mnt/walter-vm-data/sync/$id"
    else
      warn "could not ensure /mnt/walter-vm-data/sync/$id"
    fi
  done

  step "Seed .stignore on hub (replicates to local devices via Syncthing)"
  for id in "${!IGNORE_PATTERNS[@]}"; do
    pattern="${IGNORE_PATTERNS[$id]}"
    # Write .stignore via stdin redirect — avoids quoting hell with multiline.
    # shellcheck disable=SC2029 # $id intentionally expands client-side
    if printf '%s\n' "$pattern" | ssh "$WALTER_VM" "sudo tee /mnt/walter-vm-data/sync/$id/.stignore >/dev/null && sudo chown 1000:1000 /mnt/walter-vm-data/sync/$id/.stignore" 2>/dev/null; then
      ok ".stignore: $id"
    else
      warn ".stignore for $id failed"
    fi
  done
fi

cat <<NEXT

Next steps (manual, from operator's machine):

  1. Install Syncthing locally if not yet:
       brew install syncthing
       brew services start syncthing
  2. Open http://localhost:8384 to get YOUR device ID:
       Actions → Show ID
  3. Open https://sync.${WALTER_DOMAIN} (auth via CF Access — Google IdP).
  4. Add Remote Device → paste your local device ID, accept.
  5. Local Syncthing UI accepts the pairing prompt back.
  6. For each folder below, on local UI:
       Add Folder → enter exact folder ID + map to local path:
$(for spec in "${FOLDERS[@]}"; do IFS='|' read -r id label _ _ <<< "$spec"; printf "         %-18s → %s\n" "$id" "(see local mapping table)"; done)

Suggested local-path mapping:
  obsidian-vault     → ~/Obsidian/personal-vault
  projects-personal  → ~/Projects-Personal       (selective!)
  personal           → ~/personal
  screenshots        → ~/Pictures/Screenshots    (Shottr/CleanShot drop)
  agent-memory       → ~/sync/agent-memory       (already symlinked)
  desktop            → ~/Desktop
  documents          → ~/Documents
  downloads          → ~/Downloads               (heavy — .stignore filters)
  work               → ~/work                    (.stignore drops node_modules etc)

The folders are configured server-side; pairing + sharing stay interactive
because they involve cryptographic device-ID exchange.
NEXT
