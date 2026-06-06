# 0027 — Walter-VM AI-stack resilience: kill the "false green" failure mode

Status: Proposed (2026-06-06)
Context owner: operator
Supersedes/relates: ai-stack-watchdog.sh (PR #341), cloudflared setup (setup/walter-host/cloudflare/)

## Context

Between 2026-06-02 and 2026-06-06 the Walter-VM AI stack (LiteLLM gateway +
`litellm-db` + claude/gemini/codex sub-routers, fronted by Cloudflare Access +
Argo Tunnel, consumed by the Licitar Railway workers) suffered four outages:

1. **2026-06-02 (undetected 4 days)** — `litellm-db` exhausted Postgres
   connections ("too many clients already"); LiteLLM crash-looped; the
   container reported `Up` (no healthcheck) so nothing noticed.
2. **2026-06-06** — `codex-sub-think` → 502: the codex router's baked
   `MODEL_MAP` mapped `o4-mini → gpt-5.3-codex`, a slug the ChatGPT account
   rejects.
3. **2026-06-06** — `gemini-sub*` showed false "Timeout (>25s)": the router
   returns 200 in ~31–35 s; the admin probe aborted at 25 s.
4. **2026-06-06** — `cloudflared` 530 "origin unregistered from Argo Tunnel":
   the daemon was `active` but its edge connections were unregistered; recovery
   was impossible remotely (SSH rides the same tunnel; port 22 firewalled; no
   Tailscale client) and required the Hetzner web console.

A multi-agent root-cause analysis (4 investigators + synthesis + 2 adversarial
verifiers) was run on 2026-06-06.

## Decision (root cause)

**These are not four independent bugs. They are one architectural disease with
two faces:**

1. **"False green" health signals.** Every health/monitoring signal in the
   stack probes *process liveness*, never *function*. `pg_isready` passes while
   Postgres refuses connections; a container with no healthcheck reads `Up`
   while crash-looping; `systemctl is-active` reads active while the tunnel is
   unregistered; a config slug baked into an immutable image drifts from
   reality and only fails on the first real request. Detection lagged the
   actual outage by minutes to **days**.

2. **A single, unbounded, un-isolated VM with no auto-recovery and no
   break-glass path.** ~30 containers and ~10 Postgres instances share one host
   with no per-container resource limits (observed load ~5); every critical
   path (LiteLLM, its DB, the tunnel) is a single instance with no failover;
   and the one tunnel that serves the product also serves SSH, so its failure
   removes the recovery path too.

The fix is structural: **make health signals functional, bound and isolate
resources, and guarantee an out-of-band recovery path** — not four point
patches.

## Hypotheses still needing live-VM confirmation

The verifiers flagged these as plausible but unproven; confirm before relying
on them:

- **Connection-leak mechanism.** Likely Prisma/quaint pool fan-out
  (`~num_cpus*2+1` per worker × `--num_workers 2`) against default
  `max_connections=100`, amplified by reconnect storms across crash-loops.
  Confirm via `pg_stat_activity` grouping by application/state under load.
- **VM size.** Sources conflict (watchdog asserts 8 vCPU, Grafana rule 16,
  hosting doc differs). Confirm the actual Hetzner plan; if it is small,
  load ~5 is itself a primary trigger.
- **Image surface.** Confirm `litellm:v1.83.14-stable` actually serves
  `/health/liveliness` + `/health/readiness` and honors libpq-style
  `?connection_limit=&pool_timeout=&connect_timeout=` query params before
  shipping those changes.
- **Router config.** Do NOT assume `claude-code-router` is retired — it is a
  live service (`llm-proxies/compose.yml`). Verify which proxy actually serves
  `claude-sub*` before re-pointing any LiteLLM route.

## Permanent plan (prioritized; routed per repo)

### P0 — stops the bleeding / prevents the worst recurrence
- **[walter-os] Bound the LiteLLM DB pool + fail fast.** Append
  `?connection_limit=10&pool_timeout=10&connect_timeout=10` to `DATABASE_URL`
  (litellm `compose.yml`). Caps client demand at ~20 backends under
  `--num_workers 2`; turns silent hangs into fast, visible errors.
  *Verify the pinned image honors these params first.*
- **[walter-os] Real liveliness healthcheck on the `litellm` service**
  (GET `/health/liveliness`) + keep `restart: unless-stopped`. Kills the
  "Up 4 days while dead" gap. *Verify the path exists on the pinned image.*
- **[walter-os] Land + deploy + cron `ai-stack-watchdog.sh`** (PR #341) — the
  function-aware self-heal (litellm liveliness, DB saturation, per-model probe,
  cloudflared `/ready`-or-logs). Today it is not yet merged → effectively zero
  function-level self-heal is deployed.
- **[VM-action] One out-of-band recovery path** before the next outage:
  a Hetzner Cloud Firewall SSH allow-list for the operator IP, and/or activate
  the already-present `headscale`/Tailscale. The tunnel must never again be the
  only way in.

### P1 — structural correctness
- **[walter-os] Saturation-aware DB healthcheck** (`SELECT 1` / pg_stat_activity
  ratio) instead of `pg_isready`, on `litellm-db` and the other Postgres
  instances; raise `max_connections` with matching `shared_buffers` for
  headroom (the real fix is the pool cap).
- **[walter-os] Parametrize router `MODEL_MAP` via env + startup model-probe**
  that fails the deploy on an unsupported slug (all three routers). Makes a
  remap a `.env` edit, and converts a silent 502 into a deploy-time error
  naming the bad slug.
- **[walter-os] cloudflared `--ha-connections 4` + `--metrics 127.0.0.1:PORT` +
  `Restart=always`** + a `/ready` health-timer. *Note: `Restart=always` alone
  does NOT fix the alive-but-unregistered mode — the watchdog/health-timer
  does. Verify the deployed unit + config_src before editing.*
- **[licitar] Land the probe-timeout fix** (PR #703, 25s→45s) and align the
  infra-status `/health` ping (3000 ms) to documented router latency.
- **[VM-action] Reconcile the real vCPU count** and align watchdog + Grafana
  thresholds to it.

### P2 — defense in depth / bigger bets
- **[walter-os] Per-container resource limits as a mandatory stack standard**
  (shared `x-walter-limits` anchor: `mem_limit`/`mem_reservation`/`cpus`/
  `pids_limit`) across all ~30 services.
- **[walter-os] Per-router deploy smoke test** (mirror `syncthing/deploy.sh`)
  that POSTs a real completion per advertised model, including the LiteLLM
  alias hop.
- **[walter-os] Split the production-critical LLM path** (litellm + db +
  routers + ingress) onto a dedicated VM or managed Postgres, and/or a second
  cloudflared tunnel dedicated to ssh+llm.
- **[walter-os] Optional pgbouncer** (transaction mode) in front of
  `litellm-db` to decouple worker fan-out from real backends.

## Consequences

- Health checks become honest → outages surface in minutes, not days.
- Bounded pools + DB headroom → connection exhaustion structurally impossible.
- An out-of-band path → no outage is ever again unrecoverable remotely.
- Cost: modest config work (P0/P1) on walter-os + one VM-action; the P2 split
  is the larger investment, justified only if the single VM remains the host
  for the production LLM path.

## Method note

Produced by a multi-agent RCA workflow (`walter-vm-ai-rca`): 4 parallel domain
investigators → synthesis → 2 adversarial verifiers. Verifier corrections are
folded into "Hypotheses still needing live-VM confirmation" above; claims the
verifiers refuted (e.g. "claude-code-router retired", "zero monitoring",
"vCPU=4") were downgraded to hypotheses or dropped.
