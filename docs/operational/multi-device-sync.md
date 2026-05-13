# Multi-device sync

> **Audience**: operator who uses Walter-OS on more than one machine (e.g.,
> a work Mac and a home Mac, or a laptop and a home server).
>
> **TL;DR**: Walter-OS is designed for a single operator across multiple
> devices. Syncthing, running on Walter-VM (your always-on server), acts as
> the hub. All client devices sync to it. No device talks directly to another.

---

## What to sync and what not to sync

Not everything in your Walter-OS setup should be synced across devices.
The table below is the canonical answer.

| Directory | Sync? | Why |
|---|---|---|
| `~/sync/agent-memory/` | ✅ Yes | Agents' persistent memory. Without this, each device builds separate, diverging knowledge. |
| `~/sync/wiki/` | ✅ Yes | Karpathy-style LLM wiki. Single source of truth across devices. |
| `~/.config/walter-os/overlay/` | ✅ Yes (with care) | Your personal context files, `.env.local`, agent approvals. Treat this like a dotfiles repo. |
| `~/sync/agent-memory/cache/` | ❌ No | Ephemeral — regenerated per session. Syncing wastes bandwidth. |
| `~/.config/walter-os/cache/` | ❌ No | Same reason. |
| `*.tmp` directories | ❌ No | Ephemeral by definition. |
| Forgejo repos | ❌ No | Forgejo is itself the git host. Use `git push/pull`, not file sync. |
| Infisical data | ❌ No | Infisical self-hosted on Walter-VM is the source of truth for secrets. Access it via the API, not by syncing the container data dir. |
| Grafana dashboards | Optional | If you customize them and want the customization on all devices. Export JSON and put in `overlay/grafana/`. |

**Note on `overlay/.env.local`**: this file contains API tokens. Syncing it
via Syncthing is acceptable because Syncthing traffic is TLS-encrypted in
transit and the data stays within your own infrastructure (Walter-VM). It
is not acceptable to sync it via iCloud, Dropbox, or Google Drive — those
services process the content on third-party servers.

---

## Syncthing setup walkthrough

**Assumption**: Walter-VM is already running Syncthing. The onboarding
checklist (`docs/operational/onboarding-checklist.md`) shows it as healthy.

### Step 1 — Install Syncthing on the new device

**macOS**:
```bash
brew install syncthing
```

Start the daemon (runs in the background, survives reboots):
```bash
brew services start syncthing
```

**Linux (Ubuntu/Debian)**:
```bash
sudo apt install syncthing
sudo systemctl enable --now syncthing@$USER
```

### Step 2 — Open the local Syncthing UI

Syncthing has a web-based admin panel. By default it listens on localhost only.

```bash
open http://localhost:8384    # macOS (opens in browser)
# or on Linux: navigate to http://localhost:8384 in any browser
```

You should see the Syncthing dashboard for this new device.

### Step 3 — Get this device's ID

In the Syncthing UI: **Actions** (top right) → **Show ID**.

A long string of uppercase letters and numbers appears, grouped in blocks,
e.g. `AAAA-BBBB-CCCC-...`. This is your **Device ID** — it uniquely identifies
this Syncthing instance. Copy it.

### Step 4 — Add this device on Walter-VM

Option A — via Syncthing UI on Walter-VM:

1. Open Walter-VM's Syncthing UI. It's accessible at
   `https://syncthing.${WALTER_DOMAIN}` (via Cloudflare Access).
2. Click **+ Add Remote Device**.
3. Paste the Device ID you copied in Step 3.
4. Give the device a name (e.g., `mac-home`, `mac-work`, `laptop`).
5. Click **Save**.

Option B — via SSH to Walter-VM:

```bash
ssh walter-vm
# The Syncthing CLI can also add devices, but the web UI is simpler.
# Use the web UI approach above.
```

### Step 5 — Accept the connection on the new device

Within a few seconds of adding the device on Walter-VM, the new device's
Syncthing UI shows a notification: **"New Device: walter-vm wants to connect"**.
Click **Add Device** and accept.

### Step 6 — Share folders

On Walter-VM's Syncthing UI, for each folder you want to sync:

1. Click the folder name in the left panel (e.g., `agent-memory`).
2. Click **Edit**.
3. Go to the **Sharing** tab.
4. Check the checkbox next to your newly added device.
5. Click **Save**.

Repeat for `wiki` and `walter-overlay` (or whichever folders apply).

On the new device, Syncthing shows: **"Remote device wants to share folder X"**.
Accept each one and choose the local path where it should sync to.

Recommended local paths (adjust to your preference):
```
walter-overlay  →  ~/.config/walter-os/overlay/
agent-memory    →  ~/sync/agent-memory/
wiki            →  ~/sync/wiki/
```

### Step 7 — Verify sync

In Walter-VM's Syncthing UI, all synced folders should show **"Up to Date"**
next to the new device within a few minutes (depending on how much data needs
to transfer on first sync).

Check from the command line:
```bash
# On the new device:
ls ~/sync/agent-memory/       # should contain subdirectories from other devices
ls ~/.config/walter-os/overlay/   # should contain your .env.local, contexts/, etc.
```

If a folder shows **"Syncing"** for more than 10 minutes, check:
- Both devices are reachable (try `ping walter-vm` or the Tailscale IP).
- No firewall is blocking Syncthing's default port (22000 TCP/UDP).
- The folder path on the new device has write permissions.

---

## Conflict resolution

Syncthing resolves conflicts using file modification timestamps. If the same
file is modified on two devices while they are both offline (or before the
sync completes), Syncthing creates a **conflict file** with this naming pattern:

```
filename.sync-conflict-YYYY-MM-DD-HHMMSS-DEVICEID.ext
```

For example:
```
~/.config/walter-os/overlay/contexts/work/AGENTS.md.sync-conflict-2026-05-11-143022-AABBCC.md
```

The original file keeps the version from one device. The conflict file contains
the version from the other device. You compare them manually and delete the
one you don't want.

**For `agent-memory/`**: agent runners use file locks when writing memory
entries. Concurrent writes from two active agents on different devices are
very unlikely. If it happens, the conflict file will contain the losing write;
review and merge manually, then delete the conflict file.

**For `overlay/.env.local`**: this is almost never edited on multiple devices
simultaneously. If a conflict occurs, check which version is newer and keep it.

Syncthing does not silently discard data. The conflict file is always preserved
until you delete it. Run this periodically to find any unresolved conflicts:

```bash
find ~/sync ~/config/walter-os/overlay -name "*.sync-conflict-*" 2>/dev/null
```

---

## Alternative sync mechanisms

Syncthing is the recommended default because it is open source, self-hosted,
and does not transmit your data to any third-party server. If Syncthing is
not suitable for your setup, these alternatives work:

| Mechanism | Trade-offs |
|---|---|
| **Resilio Sync** | Proprietary protocol, faster initial sync than Syncthing. No self-hosted server needed (P2P). Not open source. |
| **Nextcloud** | Full self-hosted cloud suite (file sync + calendar + contacts). Much heavier than Syncthing. Good if you already run Nextcloud for other reasons. |
| **rsync over SSH** | Manual, no auto-sync. Run `rsync -avz user@walter-vm:~/sync/agent-memory/ ~/sync/agent-memory/` when you need to pull. Simple and reliable; tedious if you need it constantly. |
| **iCloud Drive / Dropbox / Google Drive** | Work but expose your personal config to a third-party service. Do not use for `overlay/.env.local` (contains API tokens) or any file tagged PHI/medical. Acceptable for non-sensitive data (wiki pages that contain no personal information). |

The iCloud/Dropbox/Google Drive warning applies specifically to `overlay/.env.local`
and any files under `contexts/personal/` or `agent-memory/` that may contain
sensitive context. If in doubt, assume a file is sensitive and keep it on
Syncthing.

---

## Recommended topology

```
                    Walter-VM (Syncthing hub — always on)
                   /           |            \
            Mac home    Mac work      Laptop (travel)
```

Walter-VM is the Syncthing hub because it is the always-on device. All
client machines connect to Walter-VM. Client machines do not connect to each
other directly.

This means:
- If Walter-VM is down, syncing pauses. Files are still accessible locally.
- Client machines behind NAT (home routers) work fine — they initiate the
  connection outbound to Walter-VM.
- Adding a third device is the same process: install Syncthing, add Device
  ID to Walter-VM, accept the share, done.

**Tailscale + Syncthing**: if Walter-VM is on your Tailscale mesh, you can
force Syncthing traffic to stay on the Tailscale network (encrypted, private).
In Syncthing settings on each device, add the Tailscale IP of Walter-VM as
a pinned address. This prevents Syncthing from trying to use a public DERP
relay for local transfers.

---

## Adding a second operator device — checklist

```
[ ] Install Syncthing on the new device
[ ] Start the Syncthing daemon
[ ] Open http://localhost:8384, get Device ID
[ ] Add Device ID to Walter-VM's Syncthing (+ Add Remote Device)
[ ] Accept the connection on the new device
[ ] Share folders from Walter-VM to the new device (Sharing tab per folder)
[ ] Accept folders on the new device, set local paths
[ ] Wait for initial sync to complete
[ ] Run: find ~/sync ~/.config/walter-os/overlay -name "*.sync-conflict-*"
    (should be empty after first sync)
[ ] Run: walter-os doctor  (checks local environment health)
```
