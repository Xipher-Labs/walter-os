# Control Tower Runbook

**Stack**: Next.js 16 App Router, Server-Sent Events, LiteLLM + Plane APIs
**Access**: Tailscale-only (`tower.${WALTER_DOMAIN}` → Cloudflare Tunnel → `walter-vm:3000`)
**Container**: `walter-control-tower:latest` on walter-vm

---

## Starting / stopping

```bash
# On walter-vm:
cd ~/services/control-tower
docker compose up -d            # start
docker compose stop             # stop (keeps container)
docker compose down             # stop + remove container (data volumes preserved)
docker compose restart          # full restart
```

Check status:
```bash
docker compose ps
docker compose logs -f control-tower   # tail logs
```

---

## Updating the container

After pushing new commits and CI builds a new image:

```bash
# Pull latest image (or build locally for dev)
docker compose pull             # pulls latest from registry
# OR for local build from repo root:
docker build -f apps/control-tower/Dockerfile -t walter-control-tower:latest .

# Rolling restart with zero downtime (docker compose handles it)
docker compose up -d --no-deps control-tower
```

---

## SSE disconnect / reconnect

The Agent Status Board uses SSE (`/api/sse`) with a 2-second poll interval.
If it shows "disconnected" (red indicator):

1. Check the container is running: `docker compose ps`
2. Check the SSE route logs: `docker compose logs control-tower | grep api/sse`
3. The client auto-reconnects after 5 seconds — a brief network hiccup resolves itself.
4. If persistently disconnected, check `/var/lib/walter-council/metrics.prom` is readable:
   ```bash
   docker compose exec control-tower cat /var/lib/walter-council/metrics.prom
   ```
   If permission denied, verify the volume mount in `compose.yml` is correct and
   the file is world-readable (`chmod 644 /var/lib/walter-council/metrics.prom`).

---

## Recovering from a panic lock

When `alert_emit panic` fires, the approval gate locks and all agent operations
are blocked. Control Tower shows a red "PANIC" entry in the Alert Feed.

Recovery steps:

1. Investigate the cause via Decision Timeline or directly:
   ```bash
   tail -20 /var/log/walter-council/events.log
   ```
2. Once confirmed non-critical (or triaged), unlock:
   ```bash
   walter-os agents unlock --reason "CVE-2026-XXXX triaged — not exploitable in our setup"
   ```
3. Verify the lock is cleared:
   ```bash
   ls ~/.config/walter-os/gate.lock  # should not exist
   ```
4. The Control Tower Alert Feed will refresh within 30 seconds.
5. If the Council was paused, resume:
   ```bash
   walter-os agents resume --all
   ```

---

## Toggling consensus mode

Via Control Tower UI:
- The **Mode Indicator** component on the dashboard shows ON/OFF.
- Click **Turn on** / **Turn off** to toggle. The toggle calls `walter-os mode consensus on|off` via server-side exec.
- The indicator updates immediately on click, and re-reads from `mode.json` every 60s.

Via CLI (on walter-vm or via Tailscale):
```bash
walter-os mode consensus on     # activate
walter-os mode consensus off    # deactivate
walter-os mode consensus status # show current state
```

When returning after consensus mode was active:
```bash
walter-os mode consensus off
walter-os agents summary --since 2026-05-11  # review what the Council auto-approved
```

---

## Interpreting the 3-phase Council Chat output

**Round 1 — Parallel groupthink**
Each agent responds independently (≤300 tokens). Click "Round 1 ▾" on each
agent card to expand. These are uncontaminated first perspectives — good for
seeing genuine diversity of opinion.

**Round 2 — Sequential deliberation**
Agents respond in trust-tier order (Reviewer first, Liaison last). Each reads
all R1 responses and cites/refutes others by name. This phase surfaces real
disagreements and forces trade-off articulation. Look for: which R1 positions
changed, which held firm, and why.

**Synthesis (Liaison)**
The synthesis card shows:
- **Convergences**: points where the Council aligned
- **Open Disagreements**: genuine unresolved differences (important to read carefully)
- **Recommended Path**: the Liaison's proposed direction
- **Next Steps**: concrete actions

The synthesis drives the "Spin as spec + plan" button. If the next steps look
right, click it — a Plane issue is created in `lane:code` and the architect
agent picks it up on the next poll cycle.

---

## Accessing Grafana from the Tower

The Metrics section embeds the Grafana "Walter Council" dashboard as an iframe.
If it shows blank:
1. Verify `GRAFANA_SA_TOKEN` is set in the container env: `docker compose exec control-tower env | grep GRAFANA`
2. Verify Grafana embed is enabled: Grafana → Configuration → Settings → Security → Allow embedding
3. If CORS error in browser console: verify Grafana `allow_embedding` is true in `grafana.ini`
4. Direct access: `https://grafana.${WALTER_DOMAIN}/d/walter-council/walter-council`

---

## Environment variables reference

All required vars are documented in:
- `apps/control-tower/.env.example` (source of truth)
- `setup/walter-host/services/control-tower/.env.example` (docker service)

At runtime, vars are injected from Infisical. To verify:
```bash
docker compose exec control-tower env | grep -E "LITELLM|PLANE|GRAFANA|CONTROL_TOWER"
```

---

## First-run setup (U-prereq-5)

The first time you access `tower.${WALTER_DOMAIN}` from a new device, you'll see
a first-run profile setup (display preferences only — not authentication).
This is stored in browser localStorage per device. No server-side setup needed.
