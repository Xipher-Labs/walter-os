# SPEC: Walter-VM ↔ standby homelab node active-replication + load-balanced failover

**Status:** Draft (2026-05-06).
**Archive note:** retained as a generic worked example for optional
cloud-to-homelab failover. The public core does not require a standby node.
**Related:**
- `docs/specs/archive/local-llm-node.md` (standby homelab node Phase L hardware + Proxmox layout)
- `docs/specs/homelab-topology.md` (4-node big picture, including LiteLLM as LLM-router — this spec is the SERVICE-level LB, different concern)
- previous (now-superseded) `docs/specs/walter-vm-ha.md` from PR #9 — restated here with updated decisions

---

## 1. The two "load balancer" questions, disambiguated

| Question | Answer | Spec |
|---|---|---|
| Route LLM requests across multiple model backends (subscription / GPU / CPU / API) | **LiteLLM** on walter-vm | `docs/specs/homelab-topology.md` §2 |
| Replicate stateful services (Plane / Forgejo / Infisical / etc.) on standby homelab node + route HTTP traffic between Hetzner and standby homelab node with health-aware failover | **THIS spec** — Postgres logical replication + Cloudflare Load Balancer | here |

These are independent. LiteLLM doesn't replicate Plane data; CF Load Balancer doesn't route token streams. Both ship.

---

## 2. Goals

- **RTO ≤ 5 min** for any single Walter-VM service when Hetzner is down. Today: hours (manual restore from snapshot or B2).
- **RPO ≤ 30 s** on Postgres data (Plane issues, Forgejo repos, Infisical secrets, Synapse rooms, LiteLLM keys). Today: 6 h via cold snapshot.
- **No request loss for read-mostly traffic** during planned maintenance on Walter-VM (apt upgrade, kernel reboot).
- **Failover is auto-triggered** by health checks; operator gets a Telegram from the `liaison` agent ("walter-vm primary unhealthy → traffic shifted to standby homelab node").
- **PHI / context:medical routes ONLY to standby homelab node** (it's local, on-LAN). Same enforcement as `homelab-topology.md`.

What we're NOT doing here:
- ❌ Multi-master writes. Plane does not tolerate concurrent primaries; nor does Forgejo. Stay primary/standby.
- ❌ Geo-replication for users in different regions. There's one operator. One region of latency-relevance.
- ❌ Fully replicating LLM inference across both nodes. That's `homelab-topology.md`'s LiteLLM + Z440 story.

---

## 3. Architecture

```
                                 Public DNS: *.${WALTER_DOMAIN}
                                          │
                                          ▼
                          ┌────────────────────────────┐
                          │  Cloudflare Load Balancer   │
                          │  (one per service domain)   │
                          │                             │
                          │  origins:                   │
                          │   1. walter-vm  (priority)  │
                          │   2. standby-node-tunnel (failover) │
                          │                             │
                          │  health checks every 30s    │
                          └──────┬────────────┬─────────┘
                                 │            │
                       (healthy) │            │ (when 1 fails)
                                 │            │
            ┌────────────────────▼─┐  ┌──────▼──────────────────────┐
            │  Walter-VM (Hetzner) │  │  standby homelab node (home)                 │
            │  PRIMARY             │  │  STANDBY                     │
            │                      │  │                              │
            │  ┌────────────────┐ │  │  ┌────────────────┐           │
            │  │ Plane / Forgejo│ │  │  │ Plane / Forgejo│           │
            │  │ Infisical / ...│ │  │  │ Infisical / ...│           │
            │  └────┬───────────┘ │  │  └────┬───────────┘           │
            │       │             │  │       │ (read-only standby   │
            │       │ writes      │  │       │  until promotion)    │
            │       ▼             │  │       ▼                      │
            │  ┌────────────────┐ │  │  ┌────────────────┐           │
            │  │ Postgres 16    │ │  │  │ Postgres 16    │           │
            │  │ PRIMARY        │═══════>│ STANDBY (replica)│         │
            │  │                │ │  │  │                │           │
            │  └────────────────┘ │  │  └────────────────┘           │
            │                      │  │                              │
            │  Tailscale →          │  │  ← Tailscale                  │
            └──────────┬───────────┘  └─────────────┬────────────────┘
                       └────── replication ─────────┘
                       (logical or physical, see §5)
```

Key choices:
- **Cloudflare Load Balancer** as the public-facing LB (~$5/mo plus per-DNS-query). Native to operator's existing CF stack. Health-checks origins, automated failover, weighted routing.
- **Origins**: each origin is a CF Tunnel pointing at the respective backend. Walter-VM has one tunnel (existing); standby homelab node needs a second tunnel.
- **Postgres**: each service runs its own Postgres (Plane has its own, Forgejo has its own, etc.). We replicate each one independently. **No shared Postgres** (couples failure domains).
- **Replication mode**: streaming physical replication (cold-warm) for simplicity. Alternative is logical replication (more flexible but more setup); covered in §5.
- **Active services on standby homelab node**: app containers run but stay in **read-only mode** until the standby is promoted. Promotion = run a small script that flips the Postgres role + lifts the read-only flag in each app's config.

---

## 4. Service tier classification — what to replicate, what to not

Not every service deserves HA work. Cost vs benefit:

### Tier-A (replicate — operator-critical, frequent writes)

| Service | Why HA matters | Replication mechanism |
|---|---|---|
| **Infisical** | Secret runtime depends on it (per `secrets-runtime-architecture.md`). Down = operator can't open new shells. | Postgres logical replication; app containers warm-standby on standby homelab node |
| **Plane** | Agent task queue. Down = Walter Council halts. | Postgres logical replication |
| **Forgejo** | Operator's private git. Down = no PR merges, no wiki commits. | Postgres + ZFS dataset rsync for `/data/git` |

### Tier-B (replicate when easy — operator-useful but tolerable downtime)

| Service | Why | How |
|---|---|---|
| **LiteLLM** | Routing layer. Down → no LLM calls. | Postgres replication. App container warm-standby. |
| **Synapse** | Matrix chat history. | Postgres replication + media folder rsync. |
| **OpenClaw** | Multi-channel assistant. State in JSON files. | Just rsync the openclaw_data volume nightly. |

### Tier-C (don't replicate — cheap to rebuild OR stateless)

| Service | Why skip |
|---|---|
| Drawio | Stateless. Files are in browser localStorage. |
| Penpot | Operator decision: not yet active enough to justify HA work. Restic+B2 covers it. |
| Headscale | Has its own HA story; one node is fine for personal mesh. Re-bootstrap from key in <10 min. |
| Uptime-Kuma | Self-monitoring. If both monitors are down, the world has bigger problems. |
| Homepage | Static dashboard. standby homelab node can run its own copy from the same compose file. |
| Grafana | Provisioned dashboards via files in repo. State is the prom data which lives on each node anyway. |
| n8n | Workflows are JSON exports; rsync `n8n_data` nightly. Restore = re-import. |
| Wireguard | Re-bootstrap from peer config in <5 min. |
| Syncthing | Already P2P — natural replication. standby homelab node becomes a 3rd peer. |

**Result**: only **5 services** need real HA work (Infisical, Plane, Forgejo, LiteLLM, Synapse). Manageable scope.

---

## 5. Postgres replication mechanism

### Option A — Streaming physical replication (recommended for v1)

```
┌──────────────────┐        WAL streaming           ┌──────────────────┐
│  PG primary      │ ─────────────────────────────> │  PG standby      │
│  walter-vm       │  (continuous, sub-second)      │  standby homelab node            │
│  port 5432       │                                │  port 5432       │
│                  │                                │  hot_standby = on│
│  archive_mode=on │                                │  recovery target │
└──────────────────┘                                └──────────────────┘
```

Pros:
- Bit-exact replica. Standby can be promoted with one command.
- Streaming + WAL archive = RPO ≤ 1 second.
- Standby serves read-only queries (useful for lint/audit agents).

Cons:
- Standby is byte-identical to primary, including version. Postgres major-version upgrades require downtime on both.
- Whole DB or nothing. Can't replicate just one DB.

For our scale (single operator, all dbs maintained together), this is fine.

### Option B — Logical replication

Pros: per-table or per-database selection; cross-version OK.
Cons: more complex setup; sequences need manual handling; doesn't replicate DDL.

**Recommendation**: physical for Tier-A. Revisit only if a service forces it (none of ours do).

### Implementation per Tier-A service

Each service compose gets a `pg-standby.yml` overlay:

```yaml
# setup/vm/services/plane/pg-standby.yml — overlay applied on standby homelab node only
services:
  plane-db:
    environment:
      POSTGRES_REPLICATION_MODE: standby
      POSTGRES_PRIMARY_HOST: walter-vm.tailnet.ts.net
      POSTGRES_PRIMARY_PORT: 5432
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: ${PG_REPLICATION_PASS}  # from Infisical
    command: >
      bash -c "
        if [ ! -s /var/lib/postgresql/data/postgresql.conf ]; then
          pg_basebackup -h $$POSTGRES_PRIMARY_HOST -D /var/lib/postgresql/data
                        -U replicator -X stream -P -R
        fi
        exec docker-entrypoint.sh postgres
      "
```

On walter-vm, `postgresql.conf` gets `wal_level = replica`, `max_wal_senders = 10`, `archive_mode = on`. Already standard for replication.

---

## 6. App-tier replication (the warm-standby part)

For each Tier-A service, standby homelab node runs the app containers but in **read-only / paused** mode:

| Service | Read-only mode mechanism |
|---|---|
| Plane | Plane respects `PLANE_READ_ONLY=true` env (added in v0.16); writes return 503 |
| Forgejo | `[server] LANDING_PAGE = read-only-banner.html` + `[security] DISABLE_GIT_HOOKS = true`; pushes refused with helpful message |
| Infisical | Standby web returns 503 on POST/PUT/PATCH/DELETE; GETs work for cache |
| LiteLLM | App is stateless; just route around when walter-vm is down |
| Synapse | Standby Matrix server with `worker_app: synapse.app.generic_worker` mode; federation reads OK, writes reject |

This way: when CF LB shifts traffic to standby homelab node, users get **degraded-functional** instead of **failed**. They can READ Plane issues; they can't CREATE new ones. They can browse Forgejo; they can't push.

Promotion to full read-write is a deliberate operator action (see §7).

---

## 7. Failover playbook

### Automatic (default)

1. CF Load Balancer health-check fails 2× in a row (60s window).
2. CF marks walter-vm origin as `unhealthy`. Routes ALL traffic to standby homelab node origin.
3. standby homelab node services receive traffic in read-only mode. Most reads work; writes return 503.
4. CF webhook → walter-vm liaison agent (or just `n8n` directly):
   - Posts Plane issue: `failover-detected-<timestamp>` with `lane:incident` label.
   - Sends Telegram via Walter Bot: "🚨 walter-vm origin unhealthy. CF LB shifted to standby homelab node (read-only mode). Promote to full read-write? Reply /promote".

### Operator promotion (manual, via Telegram or CLI)

Operator confirms "yes promote":

```bash
walter-os ha promote standby-node
```

Implementation steps the script runs (idempotent):

1. Verify walter-vm really is unreachable (avoid split-brain).
2. For each Tier-A service on standby homelab node:
   a. `pg_ctl promote -D /var/lib/postgresql/data` → standby becomes primary.
   b. Flip the app container's read-only env var → restart container.
3. Update CF Load Balancer config: drop walter-vm origin until further notice (prevents flap).
4. Post Plane comment + Telegram: "✓ standby homelab node promoted to read-write. RTO: <X>s."

### Recovery (when walter-vm comes back)

Once walter-vm is fixed, the operator has TWO paths:

**Failback** (standby homelab node → walter-vm, the "normal" choice):
1. walter-vm Postgres reinitialized as a NEW standby, replicating from standby homelab node (now-primary).
2. Drain any backlog (typically minutes).
3. Operator runs `walter-os ha failback walter-vm` → flips primary back, standby homelab node returns to standby.
4. CF LB re-adds walter-vm as priority origin.

**Stay on standby homelab node** (less common; only if walter-vm hardware died):
1. Treat standby homelab node as the new primary indefinitely. Walter-vm is decommissioned. Operator provisions a new Hetzner CX as the new standby.

---

## 8. Cloudflare Load Balancer config

For each Tier-A service domain, add a CF LB rule:

```
LB name:        walter-plane-lb
Pool name:      walter-vm-pool        →  origins: [walter-vm.cfargotunnel.com]
                walter-standby-node-pool      →  origins: [standby-node.cfargotunnel.com]
Health check:   GET https://plane.${WALTER_DOMAIN}/api/health
                expected: 200, timeout 5s, interval 30s
Failover steps: walter-vm-pool (priority) → walter-standby-node-pool (failover)
```

Cost: $5/mo per LB + per-DNS-query. For 5 services = $25/mo. Affordable for personal infra at this scale.

`setup/vm/cloudflare/05-create-load-balancer.sh` (NEW) provisions all of this via CF API. Idempotent.

---

## 9. Network + security considerations

### Replication traffic stays inside Headscale mesh

Postgres replication between walter-vm and standby homelab node NEVER traverses public internet. Both nodes on Headscale; replication uses tailnet hostnames:

```yaml
# walter-vm Postgres (each service):
listen_addresses = '0.0.0.0'
# pg_hba.conf:
host  replication  replicator  100.64.0.0/10  scram-sha-256
```

Where `100.64.0.0/10` is the Headscale CGNAT range. No exposure beyond the mesh.

### CF Tunnel for standby homelab node

standby homelab node needs its own `cloudflared` tunnel. Same domain (`*.${WALTER_DOMAIN}`) but different tunnel UUID. CF LB picks one or the other based on health checks.

```bash
# On standby homelab node (one-time):
cloudflared tunnel create standby-node-tunnel
cloudflared tunnel route dns standby-node-tunnel standby-node-origin.${WALTER_DOMAIN}   # internal DNS, not exposed publicly
```

Then ingress in `standby-node-tunnel` config maps the SAME service hostnames to standby homelab node's local containers (port 8090 for Plane, etc.).

### Replication credentials

`PG_REPLICATION_PASS` lives in Infisical. Each service's standby config reads it at runtime. Rotation procedure: generate new pass, update both nodes (small write window).

---

## 10. Phase plan

| Phase | What | Time | Scope |
|---|---|---|---|
| **R-1** Postgres primary prep | Walter-VM primaries get `wal_level=replica`, replication user, pg_hba entries | 30 min | Tier-A only |
| **R-2** standby homelab node standby init | For each Tier-A service: `pg_basebackup` from primary; configure recovery; verify replication lag | 2 h | Tier-A |
| **R-3** App warm-standby | Each Tier-A app container deployed on standby homelab node with read-only mode; verify it can SELECT from standby DB | 3 h | Tier-A |
| **R-4** standby homelab node cloudflared tunnel | Provision tunnel; map all service hostnames to internal standby homelab node container ports | 1 h | all routed services |
| **R-5** Cloudflare Load Balancer | Provision 5 LBs (Infisical, Plane, Forgejo, LiteLLM, Synapse). Health checks. Walter-vm primary, standby homelab node failover | 2 h | Tier-A |
| **R-6** Promotion + failback scripts | `walter-os ha promote <node>` and `walter-os ha failback <node>` with split-brain checks | 4 h | CLI + Plane integration |
| **R-7** Failover drill | Operator simulates walter-vm down: stop services, verify CF LB shifts, run promotion, run failback. Document timings. | 2 h | end-to-end test |
| **R-8** Tier-B as time allows | Synapse, OpenClaw, LiteLLM | 4 h | non-blocking |

Total active work: ~18 h spread over a weekend or two evenings/week.

Cost delta:
- CF Load Balancer: $25/mo for 5 services
- Electricity (standby homelab node already on for HA + Jarvis): $0 marginal
- Hetzner unchanged

---

## 11. Open questions for operator

1. **NVLink bridge for the Z440 GPUs**: operator confirmed they're buying it. Affects this spec only indirectly (faster vLLM throughput → standby homelab node inference fallback faster too). No change here.
2. **Should standby homelab node's standby Postgres serve READ traffic to agents** (e.g., janitor's nightly stale-PR sweep reads via standby to offload primary)? Recommend YES — easy win with logical replication; physical replication standbys also serve reads natively.
3. **Tier-B services priority**: Synapse first, OpenClaw second, LiteLLM third? Recommend Synapse last (Matrix HA is involved); LiteLLM first (it's nearly stateless).
4. **CF LB cost cap**: $25/mo is fine. Hard ceiling at $50/mo (would require simplification before then — Tier-B services share an LB with path routing instead of per-service LBs).
5. **DNS strategy during failover**: do we let CF handle it (LB pool + DNS-via-LB) OR maintain separate `*-standby-node.${WALTER_DOMAIN}` DNS as a fallback URL operator can point browsers at manually? Recommend CF auto, with the manual URL as documented escape hatch.

---

## 12. Acceptance criteria

- [ ] Postgres standby on standby homelab node for Plane, Forgejo, Infisical: replication lag ≤ 5s under normal load.
- [ ] Stop walter-vm Plane container. Within 90s: CF LB detects, shifts to standby homelab node. Operator gets Telegram. Plane URL still serves (read-only).
- [ ] `walter-os ha promote standby-node` executes within 30s. Plane web becomes fully read-write. Verified by creating a test issue.
- [ ] Restart walter-vm. `walter-os ha failback walter-vm` executes; replication catches up; CF LB returns walter-vm to primary. Total RTT for failback: ≤ 5 min.
- [ ] No split-brain: trying to promote both nodes simultaneously fails with a clear error.
- [ ] Replication credentials live ONLY in Infisical (not in compose env literals).
- [ ] CF LB cost ≤ $25/mo across all 5 services.
- [ ] Documented in `docs/operational/dr-runbook.md` (NEW): exact commands operator runs in each scenario.

---

## 13. What this is NOT

- ❌ Not multi-master (Postgres concurrent primaries). Operator decision: not needed; complexity isn't worth it.
- ❌ Not application-layer replication (no clustering of Plane/Forgejo themselves; just their databases).
- ❌ Not zero-downtime for writes during failover. Writes return 503 for the few seconds between detection and promotion. Acceptable.
- ❌ Not auto-promotion. Operator confirms via Telegram/CLI. Avoids accidental flap promotions.

---

## 14. Reference

- Postgres streaming replication: https://www.postgresql.org/docs/current/warm-standby.html
- Cloudflare Load Balancer: https://developers.cloudflare.com/load-balancing/
- Existing `setup/vm/services/*/compose.yml` — the services we're replicating
- `docs/specs/walter-vm-ha.md` was a prior draft of this idea; superseded by this concrete plan
