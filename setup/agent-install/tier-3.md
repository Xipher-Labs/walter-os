# Walter-OS — Tier III install via agent

> **For**: operators who already ran Tier II and want the self-hosted
> service stack (25+ services on a single VM, behind Cloudflare
> Access).
>
> **Time**: ~1–2 hours, plus ~15 min waiting on DNS propagation.
>
> **Costs money**: ~€25–50/month for a Hetzner CPX31–CPX41 VM, plus a
> domain (one-time ~$10/yr). Cloudflare's Tunnel + Access free tier
> covers up to 50 users.
>
> **Prereqs**:
> - Tier I + Tier II installed and verified.
> - A Hetzner Cloud account with a project + API token (read-only
>   first; write token minted later just for provisioning).
> - A Cloudflare account with the domain you want to use, plus an API
>   token scoped to that zone.
> - The domain's nameservers already pointing to Cloudflare.
> - A working email at a domain you control (for CF Access OTP).
>
> **How to use**: paste the entire fenced block below. The agent walks
> you through provisioning and asks for tokens when needed.
>
> **STOP RULE**: Tier III spends money. The agent must show the bill
> in human-readable form before any state-changing Hetzner call, and
> the operator must confirm "yes" each time. See AGENTS.md
> "Money-spending MCPs" rules.

---

```
================================================================================
WALTER-OS TIER III INSTALL — self-hosted stack on Hetzner

You are provisioning a Hetzner Cloud VM and bringing up the
Walter-Host service stack (25+ services) behind Cloudflare Access.

What gets deployed (`--profile core`):
  - cloudflared tunnel (no inbound ports needed)
  - Infisical (secrets manager)
  - LiteLLM (LLM gateway with virtual keys per agent)
  - Plane (issues + sprints + docs)
  - Forgejo (self-hosted Git)
  - Grafana + Prometheus + Loki (dashboards + metrics + logs)
  - n8n (workflow automation)
  - Uptime Kuma (status page)
  - WireGuard (wg-easy VPN)
  - Headscale (Tailscale control plane)
  - Syncthing (file sync)
  - Postgres (per-service or shared)
  - Caddy / nginx (reverse proxy)
  - Homepage (dashboard)

Optional profiles (operator picks any combination):
  - comms     → RocketChat, Synapse + Element (Matrix), email
  - design    → Penpot, Drawio
  - devrel    → Metabase, Postiz, PostHog
  - assistant → Hermes Agent, OpenClaw

What this Tier explicitly does NOT bring up:
  - control-tower (gated behind --profile tier4; comes in Tier IV)
  - Walter Council agents (Tier IV)
  - n8n workflows pre-loaded (Tier IV)
  - Plane workspace/projects/labels (Tier IV)

GROUND RULES — money + destructive
- Before ANY hcloud-cli call that creates/resizes/destroys, print the
  expected monthly cost delta in human-readable form and wait for
  explicit "yes" in chat.
- One Hetzner action per confirmation. "Spin up the VM" is NOT
  consent to also create 3 networks + a load balancer.
- Use a read-only HCLOUD_TOKEN first. Mint a write-scoped token only
  at the moment of provisioning. Revoke when done.
- Never `terraform destroy` or `hcloud server delete` without explicit
  confirmation for THAT specific resource.
- Daily audit (Tier II hook) runs FIRST. If any CVE ≥ 7 blocks, STOP.

================================================================================
PRECHECK

  walter-os doctor --tier 2                  # all ✓ from Tier I+II
  walter-os audit                            # audit.sh; no `run` or
                                             # `--quick` subcommand
                                             # exists today — the
                                             # wrapper execs the full
                                             # audit and ignores args

If either fails → STOP. Fix before continuing.

================================================================================
STEP 1 — DOMAIN + CLOUDFLARE

Ask:
  1.1  What domain will Walter-Host live on? (e.g. example.com)
       → WALTER_DOMAIN

  1.2  Are the DNS nameservers already pointing to Cloudflare?
       Required. If no, the operator must do this in their registrar
       first — link them to the CF dashboard.

  1.3  What email domain do you want allowed for CF Access logins?
       (Often the same as WALTER_DOMAIN; can be different —
        e.g. service on mycorp.dev, login as @mycorp.com.)
       → WALTER_AUTH_DOMAIN

  1.4  Login methods:
       a) OTP-to-email only (default, simplest, no GCP setup needed)
       b) OTP + Google one-click (requires OAuth client in GCP)
       → IDP_MODE

  1.5  Cloudflare API token scoped to WALTER_DOMAIN zone with:
         Zone: DNS Edit
         Account: Access: Apps and Policies Edit
         Account: Cloudflare Tunnel Edit
       Tell the operator how to mint it (link to CF docs), then ask
       them to paste it in chat.
       → CF_API_TOKEN
       Also need: CF_ACCOUNT (account ID, shown in the CF dashboard URL)

Write all to ~/.config/walter-os/overlay/personal.env (chmod 600).

================================================================================
STEP 2 — HETZNER VM PROVISIONING

  2.1  Hetzner Cloud read-only API token (project-scoped).
       Walter-OS validates the token + dry-runs provisioning. NO money
       spent yet.
       → HCLOUD_TOKEN_READONLY

  2.2  Server type. Show the operator this comparison from
       setup/walter-host/README.md:
         CPX31 — 4 vCPU AMD, 8 GB RAM, 160 GB NVMe   — €15/mo
                 OK for: core profile only
         CPX41 — 8 vCPU AMD, 16 GB RAM, 240 GB NVMe  — €25/mo
                 Recommended: core + 2 optional profiles
         CPX51 — 16 vCPU AMD, 32 GB RAM, 360 GB NVMe — €50/mo
                 All profiles + headroom for Council agents (Tier IV)
       → SERVER_TYPE  (default: CPX41)

  2.3  Datacenter (default: nbg1 — Nuremberg).
       Options: nbg1 / fsn1 / hel1 (EU); ash / hil (US).
       → SERVER_LOCATION

  2.4  Profiles to enable (multi-select):
       [ ] core           ← mandatory
       [ ] comms          ← RocketChat + Matrix
       [ ] design         ← Penpot + Drawio
       [ ] devrel         ← Metabase + Postiz + PostHog
       [ ] assistant      ← Hermes + OpenClaw
       Tier IV's `tier4` profile (control-tower) intentionally OMITTED
       here — Tier IV adds it later.
       → COMPOSE_PROFILES

Compute the expected cost:
  €<server-price>/mo + €0.60/mo per public IPv4 + storage egress
  (usually €0). Print as: "Provisioning <type> in <location> will
  cost ~€<N>/mo total." Wait for explicit "yes" before any state-
  changing hcloud call.

When confirmed:
  - Ask the operator to mint a WRITE-scoped Hetzner token now and
    paste it. Used only for this step; revoked at the end.
    → HCLOUD_TOKEN_WRITE
  - Run the hcloud-cli skill: provision the VM with a cloud-init
    script that:
      * installs docker + compose
      * adds the operator's SSH public key (ask for ~/.ssh/id_*.pub)
      * sets hostname to walter-<random-4-char>.<WALTER_DOMAIN>
      * disables root password login
  - Wait for the VM to be "running" + reachable via SSH.

================================================================================
STEP 3 — DNS WIRING

For each service that needs a public hostname (~24 subdomains), create
an A or CNAME record pointing to the cloudflared tunnel (NOT to the
VM IP — keeps the VM IP private and gives DDoS protection):

Tunnel hostname pattern: `<sub>.${WALTER_DOMAIN}` → CNAME
`<tunnel-id>.cfargotunnel.com`.

Run:
  ./setup/walter-host/cloudflare/01-create-tunnel.sh "$WALTER_DOMAIN"
  ./setup/walter-host/cloudflare/02-create-dns-records.sh "$WALTER_DOMAIN"

Verify (DNS propagation ~1–5 min):
  for sub in home plane git grafana llm; do
    dig +short "$sub.$WALTER_DOMAIN" CNAME
  done
  # expect: each returns *.cfargotunnel.com

================================================================================
STEP 4 — CLOUDFLARE ACCESS POLICIES

Walter-Host puts every service behind CF Access. No service is
publicly reachable; all require a successful OTP/Google login from an
allowed email domain.

Run:
  ./setup/walter-host/cloudflare/04-create-access.sh \
    "$WALTER_DOMAIN" "$WALTER_AUTH_DOMAIN" "$IDP_MODE"

This creates ~24 Access apps + policies. Idempotent — safe to re-run.

Verify:
  for sub in home plane git grafana llm; do
    code=$(curl -sf -o /dev/null -m 5 -w '%{http_code}' \
           "https://$sub.$WALTER_DOMAIN")
    echo "$sub: $code"
  done
  # expect: all 302 (login redirect, NOT 200 — 200 would mean the
  # service is publicly reachable, RED FLAG)

================================================================================
STEP 5 — VM-SIDE BOOTSTRAP

SSH to the VM:
  ssh root@<vm-ip>
  cd /opt
  git clone https://github.com/Xipher-Labs/walter-os.git
  cd walter-os
  cp .env.example .env.local
  vi .env.local   # fill: WALTER_DOMAIN, CF_API_TOKEN, postgres
                  # passwords, LITELLM_MASTER_KEY, etc.

Generate strong passwords for the placeholders. Walter-OS does not
ship a password generator subcommand (the legacy `walter-os
secrets-bootstrap` was a Bitwarden template helper and is now
deprecated). Use the standard tools:

  # one-off, copy each into the matching .env.local line
  openssl rand -hex 32     # for POSTGRES_PASSWORD, LITELLM_MASTER_KEY, etc.
  openssl rand -base64 24  # for tokens that need URL-safe chars

For the actual runtime secrets flow (Infisical machine identity + OS
keychain), Walter-OS uses:
  walter-os secrets-identity-init   # one-time bootstrap
                                    # (sets up Infisical client_id +
                                    #  client_secret in OS credential store)

That subcommand is what gets called after Infisical is up (Step 7).

Confirm .env.local looks right before bringing services up.

================================================================================
STEP 6 — START THE STACK

On the VM, explicitly list the profiles the operator selected in 2.4:
  docker compose --profile core up -d
  # add any of: --profile design --profile devrel --profile comms
  # --profile assistant — based on operator's selection above.

DO NOT pass --profile tier4 here. That brings up control-tower, which
is Tier IV territory.

Wait for all services to be healthy:
  while docker compose ps --format json \
        | jq -r '.[].Health' \
        | grep -qE 'starting|unhealthy'; do
    sleep 10
    echo "still warming up..."
  done

Expected wait: 3–8 minutes depending on profiles.

Verify control-tower is NOT running (it's gated behind --profile tier4):
  docker compose ps control-tower
  # expect: no service listed (warning is fine)

================================================================================
STEP 7 — POST-DEPLOY: INFISICAL BOOTSTRAP

Once Infisical is up at https://secrets.${WALTER_DOMAIN}:

  7.1  Tell the operator to create their admin user via the UI (first
       login bootstrap; can't be automated for security).
  7.2  Have them create a workspace `walter-vm-internal` and a project
       per service group.
  7.3  Have them create a Machine Identity `walter-vm-prod` with
       Viewer access to walter-vm-internal + walter-shared, then paste
       the client_id + client_secret back into chat.
  7.4  Write the identity to /etc/walter-os/infisical-identity on the
       VM (chmod 600 root:root). This is what the Infisical sidecars
       use to fetch secrets per service at boot.

After 7.4, recreate the stack to switch all services from .env.local
sourcing to Infisical-sidecar sourcing:
  docker compose down
  docker compose --profile core up -d
  # plus any optional profiles from step 6

================================================================================
STEP 8 — VERIFY END-TO-END

From the operator's machine:
  for sub in home plane git grafana llm secrets n8n; do
    code=$(curl -sf -o /dev/null -m 5 -w '%{http_code}' \
           "https://$sub.$WALTER_DOMAIN")
    echo "$sub: $code"
  done
  # expect: all 302

Open https://home.${WALTER_DOMAIN} in a browser → CF Access login →
after auth, see the homepage dashboard with all service links.

If any service is unhealthy:
  ssh root@<vm-ip> 'cd /opt/walter-os && \
    docker compose ps | grep -v healthy'

Then run the local doctor with the tier filter:
  walter-os doctor --tier 3

(This validates WALTER_DOMAIN and HCLOUD_TOKEN are set locally — the
service health is verified by the curl above.)

================================================================================
STEP 9 — REVOKE WRITE TOKEN

Tell the operator:
  - Revoke the WRITE-scoped HCLOUD_TOKEN_WRITE in the Hetzner console.
  - Keep the READ-only HCLOUD_TOKEN_READONLY for monitoring + alerts.
  - Push HCLOUD_TOKEN_READONLY to Infisical at:
    walter-vm-internal/prod/hcloud/HCLOUD_TOKEN

================================================================================
STEP 10 — REPORT

Print to the operator:

  ✓ Walter-OS Tier III installed.
  ✓ VM: <type> in <location> (~€<N>/mo)
  ✓ Stack: <N> services healthy on https://*.${WALTER_DOMAIN}
  ✓ All services behind CF Access (@${WALTER_AUTH_DOMAIN} login required)
  ✓ Infisical machine identity wired
  ✓ control-tower NOT running (correct — gated behind --profile tier4)
  ✓ Hetzner write token revoked

  Next steps:
    - Create first-run admin users in each service via the UI:
        Plane (workspace + project), Forgejo (admin user), Grafana
        (admin pw reset), n8n (admin signup).
    - Configure Cloudflare Access login UI branding (optional).
    - Optional: add Tier IV for Council agents + n8n workflows + Plane
      workspace structure + Control Tower (2–3 hours).
      → setup/agent-install/tier-4.md

  Operator action items:
    [list any service that failed to come up or needs manual config]

================================================================================
END
```

---

## What the operator sees

After Tier III, in addition to Tier I+II:

| Concern | Where it lives |
|---|---|
| Cloud VM | Hetzner Cloud project (visible at console.hetzner.cloud) |
| Tunnel | Cloudflare Zero Trust dashboard → Tunnels |
| Services | `https://<sub>.${WALTER_DOMAIN}` (~24 subdomains, all CF-Access-gated) |
| Secrets | `https://secrets.${WALTER_DOMAIN}` (Infisical) + machine identity file on VM |
| Compose | `/opt/walter-os/compose.yml` on VM |
| Service env | `/opt/walter-os/.env.local` on VM (gitignored) + per-service Infisical secrets |
| Logs | `https://grafana.${WALTER_DOMAIN}` (Loki backend) |
| Backups | Restic to Backblaze B2 if `RESTIC_REPOSITORY` configured |

## Cost-per-month reference (Europe pricing, May 2026)

| Item | Cost |
|---|---|
| Hetzner CPX31 (4 vCPU / 8 GB / 160 GB) | €15.06 |
| Hetzner CPX41 (8 vCPU / 16 GB / 240 GB) | €25.20 |
| Hetzner CPX51 (16 vCPU / 32 GB / 360 GB) | €50.40 |
| Public IPv4 | €0.60 |
| Backups (auto, +20% server price) | optional |
| Cloudflare (Tunnel + Access free tier) | €0 (up to 50 users) |
| Domain | varies (~€10/yr) |

## Re-running Tier III

Re-paste to:
- Add new profiles (e.g. didn't enable `design`, now want Penpot).
- Resize the VM (downtime ~2 min).
- Rotate the Infisical machine identity.

The agent reads existing config and only asks about new decisions.

## Next tier

→ [Tier IV — Council + automation](tier-4.md) wires the 6-agent
Council, n8n workflows, Plane workspace structure (per
`docs/specs/multi-agent-autonomy.md`), and Control Tower dashboard.
