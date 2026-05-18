---
name: syncthing-cli
description: Manage Syncthing folder registration and configuration on a remote hub VM via the REST API over SSH. Use this skill when the operator asks to "register a folder", "check sync status", "add a new sync folder", "reconcile Syncthing config", or anything that involves the Syncthing REST API on a remote host. Replaces the removed scripts/syncthing-bootstrap.sh; operators must supply their own bootstrap script via the overlay.
---

# Syncthing CLI (REST over SSH)

Direct Syncthing management via the REST API, tunneled over SSH. No Syncthing
MCP exists with sufficient trust score; this pattern is more reliable and
auditable than a community plugin.

## Why CLI instead of MCP

- Syncthing exposes a full REST API on `127.0.0.1:8384` by default (not
  exposed on the network interface).
- All operations are achievable via `ssh <alias> curl` — no extra tooling,
  no credential surface beyond SSH.
- Syncthing MCPs in community registries: low-star, single-maintainer.
  Trusting them with SSH access to a hub VM is a supply-chain risk.
- Scripts are auditable, version-controlled, and idempotent by design.

## Setup

### Prerequisites

- SSH alias `${WALTER_VM_SSH_ALIAS}` configured in `~/.ssh/config`.
- Syncthing container running on the hub VM, API accessible at
  `http://127.0.0.1:8384` from the hub's localhost.
- `jq` installed on the hub VM (`apt-get install jq` or equivalent).
- Syncthing API key stored in `~/.config/walter-os/secrets.env` as
  `SYNCTHING_API_KEY`. Never hardcode in scripts.

```bash
# Verify SSH alias resolves
ssh "${WALTER_VM_SSH_ALIAS}" echo ok

# Verify Syncthing API is reachable from hub
ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf -H "X-API-Key: ${SYNCTHING_API_KEY}" \
  http://127.0.0.1:8384/rest/system/ping
# Expected: {"ping":"pong"}
```

## Common operations

### Check Syncthing health

```bash
ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf \
    -H "X-API-Key: ${SYNCTHING_API_KEY}" \
    http://127.0.0.1:8384/rest/system/ping
```

### List configured folders

```bash
ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf \
    -H "X-API-Key: ${SYNCTHING_API_KEY}" \
    http://127.0.0.1:8384/rest/config/folders \
  | jq '[.[] | {id: .id, label: .label, path: .path}]'
```

### Check if a specific folder is already configured

```bash
ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf \
    -H "X-API-Key: ${SYNCTHING_API_KEY}" \
    http://127.0.0.1:8384/rest/config/folders \
  | jq --arg id "${SYNC_FOLDER_ID}" '.[] | select(.id == $id) | .id' \
  | grep -q "${SYNC_FOLDER_ID}" && echo "already configured" || echo "not found"
```

### Add a new folder (idempotent pattern)

```bash
# Build the folder object. Adjust rescanIntervalS and other fields per folder.
FOLDER_JSON="$(jq -n \
  --arg id   "${SYNC_FOLDER_ID}" \
  --arg label "${SYNC_FOLDER_LABEL}" \
  --arg path  "${HUB_DATA_PATH}/${SYNC_FOLDER_ID}" \
  '{
    id: $id,
    label: $label,
    path: $path,
    type: "receiveonly",
    rescanIntervalS: 3600,
    fsWatcherEnabled: true,
    fsWatcherDelayS: 10,
    ignorePerms: false,
    autoNormalize: true,
    devices: []
  }')"

ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf -X POST \
    -H "X-API-Key: ${SYNCTHING_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "${FOLDER_JSON}" \
    http://127.0.0.1:8384/rest/config/folders
```

### Reload Syncthing config after changes

```bash
ssh "${WALTER_VM_SSH_ALIAS}" \
  curl -sf -X POST \
    -H "X-API-Key: ${SYNCTHING_API_KEY}" \
    http://127.0.0.1:8384/rest/config/restart
```

## Idempotent reconciliation pattern

Use this pseudocode when writing an operator bootstrap script. All
operator-specific values (`${SYNC_FOLDER_ID}`, `${WALTER_VM_SSH_ALIAS}`,
`${HUB_DATA_PATH}`) must come from the operator's environment — never
hardcoded in a shared script.

```bash
#!/usr/bin/env bash
# Operator bootstrap script — lives in the operator overlay or a personal
# scripts repository outside the OSS repo.
# Place at: ~/.config/walter-os/overlay/scripts/syncthing-bootstrap.sh
# Or at:    ~/config-personal/scripts/syncthing-bootstrap.sh
#
# Required env vars:
#   WALTER_VM_SSH_ALIAS   — SSH config alias for the hub VM
#   SYNCTHING_API_KEY     — Syncthing API key (from secrets.env)
#   HUB_DATA_PATH         — Base path on the hub for sync data (e.g. /data/sync)

set -euo pipefail

API="http://127.0.0.1:8384/rest"

# Wrap ssh in a function so the alias is always properly quoted — avoids
# word-splitting if the operator's SSH config alias contains spaces.
ssh_to_hub() { ssh "${WALTER_VM_SSH_ALIAS}" "$@"; }

api_get()  { ssh_to_hub curl -sf -H "X-API-Key: ${SYNCTHING_API_KEY}" "${API}/$1"; }
api_post() { ssh_to_hub curl -sf -X POST -H "X-API-Key: ${SYNCTHING_API_KEY}" \
               -H "Content-Type: application/json" --data "$2" "${API}/$1"; }

ensure_folder() {
  local folder_id="$1" folder_label="$2" folder_path="$3"
  local existing
  existing="$(api_get "config/folders" | jq --arg id "$folder_id" '.[] | select(.id==$id) | .id')"
  if [[ -n "$existing" ]]; then
    echo "  [ok] ${folder_id} already registered"
    return 0
  fi
  echo "  [add] registering ${folder_id} at ${folder_path}"
  local payload
  payload="$(jq -n \
    --arg id "$folder_id" --arg label "$folder_label" --arg path "$folder_path" \
    '{id:$id, label:$label, path:$path, type:"receiveonly",
      rescanIntervalS:3600, fsWatcherEnabled:true, fsWatcherDelayS:10,
      ignorePerms:false, autoNormalize:true, devices:[]}')"
  api_post "config/folders" "$payload"
  ssh_to_hub mkdir -p "$folder_path"
}

# Operator populates FOLDERS array with their actual folder inventory.
# Format: "folder-id:Folder Label:${HUB_DATA_PATH}/folder-id"
FOLDERS=(
  "${SYNC_FOLDER_ID}:${SYNC_FOLDER_LABEL}:${HUB_DATA_PATH}/${SYNC_FOLDER_ID}"
  # Add additional folders here.
)

for entry in "${FOLDERS[@]}"; do
  IFS=: read -r fid flabel fpath <<< "$entry"
  ensure_folder "$fid" "$flabel" "$fpath"
done

# Reload to apply changes
api_post "config/restart" "{}"
echo "Done. Syncthing config reloaded."
```

## .stignore seeding

Write `.stignore` via SSH stdin redirect. Syncthing reads this file at
next rescan or immediately if `fsWatcherEnabled=true`.

```bash
# Seed .stignore for a folder
ssh "${WALTER_VM_SSH_ALIAS}" "cat > ${HUB_DATA_PATH}/${SYNC_FOLDER_ID}/.stignore" <<'IGNORE'
// Generated by syncthing-bootstrap. Edit in place on the hub.
(?d).DS_Store
(?d).localized
(?d)__pycache__
(?d).cache
(?d).Trash
(?d)node_modules
(?d).git
(?d)*.pyc
IGNORE
```

Note: `.stignore` changes take effect on next rescan. Force rescan via the
API if immediate effect is needed.

## Hard rules

- **Never hardcode folder inventory in a shared OSS script.** Folder IDs,
  labels, and hub paths are operator-specific. They belong in the operator's
  personal scripts repository or the overlay — not in the walter-os repository.
- **Always run with `--dry-run` first** if your bootstrap script supports it.
  Add a `DRY_RUN` guard before any `api_post` call.
- **Never store `SYNCTHING_API_KEY` in scripts.** Load from `secrets.env` or
  Infisical at runtime.
- **Use `receiveonly` type on the hub for laptop-to-hub sync.** Prevents the
  hub from sending edits back unexpectedly.
- **Verify SSH connectivity before looping over folders.** Fail fast with a
  health check ping; don't register 10 folders before discovering SSH is down.

## Operator customization pointer

Your bootstrap script must live outside the walter-os OSS repository.
Supported locations (in discovery order used by `walter-os syncthing-bootstrap`):

1. `${WALTER_OPERATOR_SCRIPTS_DIR}/syncthing-bootstrap.sh` (env var, highest priority)
2. `~/.config/walter-os/overlay/scripts/syncthing-bootstrap.sh` (overlay convention)
3. `~/config-personal/scripts/syncthing-bootstrap.sh` (personal scripts fallback)

Run `walter-os syncthing-bootstrap --help` for the live discovery order.

## Integration with other skills

- `hcloud-cli` — provision the hub VM where Syncthing runs.
- `secrets-yubikey-unlock` — unlock `SYNCTHING_API_KEY` from the secrets store.
- `agent-memory` — after registering folders, run `walter-os agent-memory setup`
  to wire the `~/.claude/memory` directory into Syncthing.

## What this skill does NOT cover

- Syncthing device pairing (GUI or web UI required for first-time device add).
- TLS/HTTPS configuration for the Syncthing API (use SSH tunnel pattern above).
- Multi-device topologies beyond laptop-to-hub-VM (star topology).
- Syncthing relay server configuration.
- Conflict resolution strategies beyond "hub is receive-only".
