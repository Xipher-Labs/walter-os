---
name: hcloud-cli
description: Provision, resize, and manage Hetzner Cloud VMs, networks, volumes, load balancers, firewalls, snapshots, and DNS via the official `hcloud` CLI. Use this skill whenever the user asks to "provision a VM", "resize Hetzner server", "create snapshot", "list VMs", "rotate Hetzner token", "set Hetzner firewall rule", or any Hetzner Cloud infrastructure task. Replaces low-trust community Hetzner MCP. SPENDS MONEY — confirmation required before any state-changing action.
---

# Hetzner Cloud CLI (`hcloud`)

Official CLI from Hetzner. Mature, well-documented, full feature parity
with the Hetzner Cloud Console + API. Replaces the abandoned community MCP
(1 GitHub star, 1 fork) which had a non-trivial security surface.

## Setup

```bash
# Already in setup/Brewfile:
brew install hcloud   # also: brew tap hetznercloud/hcloud (legacy)

# Verify
hcloud version
```

### Configure context (one-time)

```bash
# Generate API token at: https://console.hetzner.com/projects/<id>/security/tokens
# Scope: read-only by default; write only when actively provisioning

hcloud context create walter-vm
# ↳ pastes token interactively

# Switch contexts (if multiple Hetzner projects)
hcloud context list
hcloud context use walter-vm
```

`HCLOUD_TOKEN` env var also works. Walter-OS keeps it in
`~/.config/walter-os/secrets.env`. **For day-to-day reads, use a read-only
token. Only switch to write-scoped token when actively provisioning, then
revoke.**

## Core operations

### Servers (VMs)

```bash
hcloud server list                    # all VMs in current context
hcloud server describe walter-vm      # full details of one VM

# Create
hcloud server create \
  --name walter-vm \
  --type cpx41 \
  --image ubuntu-24.04 \
  --location fsn1 \
  --ssh-key ${WALTER_SSH_KEY_NAME} \
  --start-after-create

# Resize (briefly stops the VM)
hcloud server change-type walter-vm cpx51

# Power
hcloud server poweroff walter-vm
hcloud server poweron walter-vm
hcloud server reboot walter-vm

# DELETE (destructive — operator confirms)
hcloud server delete walter-vm
```

### Networks (private cloud networking)

```bash
hcloud network list
hcloud network create --name walter-net --ip-range 10.0.0.0/16
hcloud network add-subnet walter-net --type cloud --ip-range 10.0.1.0/24 --network-zone eu-central
hcloud server attach-to-network walter-vm --network walter-net --ip 10.0.1.10
```

### Volumes

```bash
hcloud volume list
hcloud volume create --name walter-data --size 100 --location fsn1
hcloud volume attach walter-data --server walter-vm --automount

# Resize (only growable, never shrink)
hcloud volume resize walter-data --size 200

# Detach + delete
hcloud volume detach walter-data
hcloud volume delete walter-data
```

### Snapshots

```bash
hcloud server create-image walter-vm --type snapshot --description "before-upgrade-$(date +%F)"
hcloud image list --type snapshot

# Restore = create new server from snapshot
hcloud server create --name walter-vm-restored --type cpx41 \
  --image <snapshot-id> --location fsn1 --ssh-key ${WALTER_SSH_KEY_NAME}
```

Snapshots cost ~20% of disk size monthly. Worth setting a retention
policy (e.g., keep 7 daily + 4 weekly + 12 monthly).

### Firewalls

```bash
hcloud firewall list
hcloud firewall create --name walter-vm-fw

# Add rules
hcloud firewall add-rule walter-vm-fw \
  --direction in --protocol tcp --port 22 --source-ips 0.0.0.0/0 --description "ssh (close after CF Access setup)"
hcloud firewall add-rule walter-vm-fw \
  --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --description "http"
hcloud firewall add-rule walter-vm-fw \
  --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --description "https"

# Apply to server
hcloud firewall apply-to-resource walter-vm-fw --type server --server walter-vm

# CLOSE port 22 publicly after CF Access SSH is verified working:
hcloud firewall delete-rule walter-vm-fw \
  --direction in --protocol tcp --port 22 --source-ips 0.0.0.0/0
```

### Floating IPs

```bash
hcloud floating-ip list
hcloud floating-ip create --type ipv4 --home-location fsn1 --description "walter-vm primary"
hcloud floating-ip assign <id> walter-vm
```

### Load Balancers

```bash
hcloud load-balancer list
hcloud load-balancer create --name walter-lb --type lb11 --location fsn1
hcloud load-balancer add-target walter-lb --type server --server walter-vm
hcloud load-balancer add-service walter-lb --protocol http --listen-port 80 --destination-port 80
```

### Pricing (always check before provisioning)

```bash
hcloud server-type list                # all server types + monthly cost
hcloud datacenter list                 # locations
hcloud pricing                         # global pricing table
```

## Provisioning a new VM (full flow)

```bash
# 1. Read SSH key from Hetzner (must already be uploaded)
hcloud ssh-key list
# If missing:
hcloud ssh-key create --name ${WALTER_SSH_KEY_NAME} --public-key-from-file ~/.ssh/id_ed25519.pub

# 2. Pick server type + check price
hcloud server-type describe cpx41   # 8 vCPU / 16GB / 240GB SSD / €25.20/mo

# 3. Create server
hcloud server create \
  --name walter-vm-2 \
  --type cpx41 \
  --image ubuntu-24.04 \
  --location fsn1 \
  --ssh-key "${WALTER_SSH_KEY_NAME:-<your-ssh-key-name>}" \
  --start-after-create \
  --user-data-from-file "${WALTER_OS_HOME:-<path-to-walter-os-repo>}/setup/walter-host/cloud-init.yaml"

# 4. Wait for boot
hcloud server list --output columns=name,status,ipv4
# Should show "running"

# 5. Apply firewall (start permissive, lock down after Walter-VM bootstrap)
hcloud firewall apply-to-resource walter-vm-fw --type server --server walter-vm-2
```

## Hard rules (non-negotiable)

- **Confirm before any state change.** The agent prints a one-liner cost
  delta + asks "proceed?" before `server create`, `server delete`,
  `server change-type`, `volume delete`, etc.
  - Example: "I will provision a CPX41 in Falkenstein (€25.20/mo).
    Confirm? Y/N"
- **Read before write.** Default to `list`, `describe`, `pricing`. Mutate
  only on explicit instruction.
- **Never delete without snapshot.** For VMs with data, take a snapshot
  before delete. (If VM is fresh and empty, skip the snapshot — but say
  so explicitly.)
- **Never schedule destruction.** No "delete this VM at 3am tomorrow."
  Destruction is always interactive.
- **Token rotation cadence**: at minimum every 90 days. Use read-only
  scope when possible.
- **Cost guardrails**: monthly Hetzner spend > €100 → require operator
  approval for any new resources beyond that.

## Cost-aware patterns

```bash
# Show current monthly bill estimate
hcloud server list --output columns=name,type | tail -n +2 | while read name type; do
  price=$(hcloud server-type describe "$type" -o json | jq -r '.prices[0].price_monthly.gross')
  printf "%-25s %s   €%s/mo\n" "$name" "$type" "$price"
done

# Total
hcloud server list --output noheader | awk '{print $4}' | while read t; do
  hcloud server-type describe "$t" -o json | jq '.prices[0].price_monthly.gross|tonumber'
done | paste -sd+ | bc
```

## DNS (Hetzner DNS, separate from Cloud)

Hetzner has a separate DNS service. The same `hcloud` CLI does NOT cover
it. Use:

```bash
# Hetzner DNS official CLI (separate)
brew install hetznercloud/dns/hetzner-dns-cli

# Or use the API directly with curl + HCLOUD_DNS_TOKEN
```

For Walter-OS we use Cloudflare DNS instead (better global routing,
Tunnel integration), so Hetzner DNS isn't really used. Skip unless
you specifically need Hetzner DNS for some isolation reason.

## Output formatting

```bash
hcloud server list -o noheader
hcloud server list -o json | jq '.[] | {name, type, ipv4: .public_net.ipv4.ip}'
hcloud server list -o columns=name,type,ipv4,status
```

JSON output is the most reliable for scripting. The default columnar
output has stable column names but variable widths.

## Why CLI instead of MCP

- Official, maintained directly by Hetzner.
- Full feature parity with the API + Console.
- Token scoping is granular at Hetzner side (read-only / write).
- Community MCP we audited: 1 star, 1 fork, single recent commit. Not
  worth handing it your cloud credentials.
- Bash is the right interface for infra ops anyway — agent invokes via
  the Bash tool, parses JSON output.

## What this skill does NOT cover

- Hetzner Robot (dedicated bare-metal servers — different API entirely).
  Use the web Robot interface.
- Hetzner DNS — separate CLI as noted.
- Hetzner Storage Box (cold storage) — uses sftp/borg, not hcloud CLI.

## References

- https://github.com/hetznercloud/cli
- https://docs.hetzner.cloud/
- https://github.com/hetznercloud/hcloud-python (alt: scripts in Python)
