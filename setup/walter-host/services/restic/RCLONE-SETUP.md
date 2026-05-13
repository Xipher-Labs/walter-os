# rclone:gdrive setup for Walter-VM restic

The Walter-VM is headless — you can't run `rclone config` interactively
because it needs a browser to OAuth Google Drive. Workaround: do the OAuth
**on your Mac**, paste the resulting token to the VM.

## Steps (one-time)

### 1. On your Mac

```bash
# Install if missing
brew install rclone

# Run the headless authorize flow — opens browser, you approve, get token
rclone authorize "drive"
# ↳ Browser opens to https://accounts.google.com/...
# ↳ Approve "rclone wants to access your Google Drive"
# ↳ Terminal prints a JSON token like:
#       Paste the following into your remote machine ---->
#       {"access_token":"ya29...","token_type":"Bearer","refresh_token":"1//...","expiry":"..."}
#       <---- End paste

# Copy the JSON to your clipboard.
```

### 2. On the VM

```bash
ssh walter-vm
sudo -u walter rclone config

# Walk through:
n)         New remote
name>      gdrive
type>      drive
client_id> (blank — uses rclone shared OAuth client, fine for personal)
client_secret> (blank)
scope>     1   (full access)
service_account_file> (blank — we use OAuth)
Edit advanced config? n
Use auto config? n            ← important, headless
config_token> [paste the JSON from step 1]
Configure as Shared Drive? n  (personal Drive)
Yes, OK?    y
q)         Quit
```

### 3. Verify

```bash
sudo -u walter rclone lsd gdrive:
# ↳ should list your Drive's top-level folders

# Create the backup folder
sudo -u walter rclone mkdir gdrive:walter-vm-backup

# Test write
echo "ping" | sudo -u walter rclone rcat gdrive:walter-vm-backup/ping.txt
sudo -u walter rclone cat gdrive:walter-vm-backup/ping.txt
sudo -u walter rclone delete gdrive:walter-vm-backup/ping.txt
```

If those four lines work → ready for `setup.sh`.

## Quota considerations

Google Drive personal storage:
- **Free**: 15 GB shared with Gmail + Photos. **Not enough.**
- **Google One Basic**: 100 GB / $1.99/mo. Enough for early Walter-VM.
- **Google One Standard**: 200 GB / $2.99/mo. Comfortable.
- **Google One Premium**: 2 TB / $9.99/mo. Future-proof.

Backups are **encrypted by restic before upload** (Drive sees only opaque
blobs), so privacy is fine even on personal Drive. The volume cap is the
only constraint.

Walter-VM expected backup size:
- Initial full snapshot: ~5–10 GB (Plane DB + service state + configs)
- Daily incrementals: 50–200 MB typically
- Forever pruned to: 7 daily + 4 weekly + 12 monthly = ~25 snapshots
- Rough steady-state: 8–15 GB

100 GB Google One plan covers this comfortably with room for other
backups (Obsidian vault, personal photos, etc.).

## Service Account (alternative, more robust)

For long-term automation, prefer a Google Service Account over user OAuth:

1. Google Cloud Console → IAM → Service Accounts → Create
2. Name: `walter-vm-restic-backup`
3. Grant role: only "Owner of `walter-vm-backup` folder"
4. Create JSON key, download → save to `/etc/walter-vm/gdrive-sa.json` (mode 600)
5. In Drive UI: share `walter-vm-backup` folder with the service account email
6. In rclone config:
   - `service_account_file: /etc/walter-vm/gdrive-sa.json`

Service account benefits:
- No token rotation pain
- Doesn't break if you log out of your personal Google account
- Per-folder ACL via Drive sharing (cleaner)

Trade-off: separate Google billing line if you create the SA in a billed
project. For personal use it's fine in a free project.

## Backup target alternatives (if you decide later)

| Target | Cost (1TB) | Notes |
|---|---|---|
| Google Drive (current plan) | $9.99/mo (2TB) | Easiest, you already pay it |
| Cloudflare R2 | $15/mo + $0 egress | Fastest restore via Cloudflare ASN |
| Backblaze B2 | $6/mo + $10/TB egress (gratis hasta 3×) | Cheapest storage |
| Hetzner Storage Box | €3.20/mo | Same provider as VM = NOT real off-site |
| AWS S3 + Glacier IR | $4/mo cold | Cheap but slow restore |

Switching is just a `restic` repo migration: `restic copy --from-repo
old-repo new-repo` while old still online. Plan once, migrate later if
needed.
