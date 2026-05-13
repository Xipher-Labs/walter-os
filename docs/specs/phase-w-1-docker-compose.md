# W-1: All-in-One Docker Compose

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

Walter-OS currently provisions services through ~20 independent `deploy.sh` scripts,
each in `setup/vm/services/<service>/`. Every script makes assumptions about path
layout, environment variables sourced from different `.env` files scattered across
subdirectories, and the order in which sibling services must already be running.
A new operator trying to adopt Walter-OS faces a non-trivial dependency graph they
must manually trace and a dozen manual steps before a single service responds.

The per-service model made sense during incremental build-out (add Plane, then
Forgejo, then observability, etc.). For OSS adoption, it is an obstacle. The barrier
to "does this thing even work on my machine?" is too high. Any framework that cannot
be stood up end-to-end in a single command will not be adopted.

There is also a practical maintenance problem: when a compose field changes (a
healthcheck URL, a network alias), it must be replicated across independent files.
The all-in-one compose is the single source of truth for the full service graph.

## Proposed solution

A single `compose.yml` at the repo root (or `setup/vm/compose.yml` — operator choice
at deploy time) that declares all Walter-OS services in one file with named networks
and a shared postgres instance. Five bootstrap environment variables (`WALTER_DOMAIN`,
`WALTER_ADMIN_EMAIL`, `WALTER_INITIAL_USER`, `WALTER_INITIAL_PASSWORD`,
`WALTER_TIMEZONE`) are the only required inputs for a first run. All service-level
config is derived from those or has sane defaults.

A `scripts/bootstrap.sh` script runs once (detected by a `.bootstrapped` sentinel
file) after `docker compose up`, calls each service's API to create the initial admin
user/workspace, and then marks itself done so re-runs are idempotent. Optional
services (Postiz, Metabase, OpenClaw, Penpot, Drawio) are gated behind Docker
Compose profiles (`--profile devrel`, `--profile design`, `--profile assistant`)
so they do not start by default.

## Acceptance Criteria

- [AC-1] `WALTER_DOMAIN=example.com WALTER_ADMIN_EMAIL=admin@example.com \
  WALTER_INITIAL_USER=admin WALTER_INITIAL_PASSWORD=changeme \
  WALTER_TIMEZONE=UTC docker compose up -d` brings all core services to
  `healthy` or `running` status within 3 minutes on a machine with 4 GB RAM
  available to Docker.
- [AC-2] `scripts/bootstrap.sh` runs after first `up` and creates: Plane
  workspace named "walter-os", Forgejo user matching `WALTER_INITIAL_USER`,
  Infisical workspace "walter-os" with Machine Identity "walter-agent",
  LiteLLM master key, and Grafana admin password — all without operator
  intervention beyond the five bootstrap vars.
- [AC-3] Re-running `docker compose up -d` and `scripts/bootstrap.sh` after
  a successful first run produces no changes and no errors (idempotent).
- [AC-4] Each core service has a Docker healthcheck. `docker compose ps`
  shows `(healthy)` for: postgres, plane-api, forgejo, infisical, litellm,
  grafana, prometheus, n8n, caddy.
- [AC-5] `--profile devrel` adds Postiz + Metabase. `--profile design` adds
  Penpot + Drawio. `--profile assistant` adds OpenClaw. Each profile is
  independently composable (e.g., `--profile devrel --profile design` works).
- [AC-6] Uptime Kuma, once started, auto-imports a monitor list covering
  every service declared in the compose (via Uptime Kuma API or config file
  import at bootstrap time).
- [AC-7] Bats integration test `tests/compose/smoke.bats` spins up the
  compose (or a test subset), curls each service's health endpoint, and
  asserts HTTP 200 or the service-appropriate health response. Test must pass
  in CI (GitHub Actions, Linux runner, Docker available).
- [AC-8] No `xipherlabs.xyz` or any operator-specific domain appears in
  `compose.yml`, service env files sourced by compose, or `scripts/bootstrap.sh`.
  All references use `${WALTER_DOMAIN}`.

## Non-goals

- Kubernetes / Helm manifests: out of scope for v0.2.0.
- Multi-node / HA: single-host only. Load balancing deferred.
- Automated TLS inside compose: Caddy handles TLS via ACME. The compose
  assumes Caddy is the only publicly-facing service; all others are on
  internal Docker networks.
- Replacing `setup/vm/services/<service>/compose.yml` files: they remain
  for operators who prefer incremental deployment. The all-in-one is an
  alternative, not a forced replacement.

## Open questions

- Caddy vs Nginx as the reverse proxy in the all-in-one: spec chooses Caddy
  (automatic HTTPS, simpler config, already used in some services). Flag if
  the reviewer sees a conflict.
- Shared postgres vs per-service postgres: spec chooses one shared Postgres
  instance with separate databases per service, matching the current
  `setup/vm/services/postgres/` pattern. This is a trade-off: simpler ops,
  single point of failure. Noted in ADR 0011 is not the place for this;
  an inline note in the compose spec suffices.

## Implementation plan

### Task 1: Inventory all service dependencies [AC-1, AC-4]
- File: `setup/vm/services/*/compose.yml` (read-only audit)
- Change: Produce a dependency graph (service → networks, volumes, env vars
  required). Output: comment block at top of `compose.yml` documenting
  startup order.
- Verify: Manual review confirms all 20+ services are accounted for.

### Task 2: Write `compose.yml` — core services [AC-1, AC-4, AC-8]
- File: `compose.yml` (new, repo root)
- Change: Declare services: postgres (shared), caddy, plane (all containers),
  forgejo, infisical, litellm, grafana, prometheus, loki, promtail,
  node-exporter, n8n, wireguard, headscale, syncthing, uptime-kuma.
  All service URLs reference `${WALTER_DOMAIN}`. Named network `walter_net`.
  Named volumes for persistence. Healthchecks per service.
- Verify: `docker compose config` exits 0. `docker compose up -d` brings
  core services to healthy.

### Task 3: Write `compose.yml` — optional profiles [AC-5]
- File: `compose.yml` (modify)
- Change: Add `profiles: [devrel]` to Postiz + Metabase; `profiles: [design]`
  to Penpot + Drawio; `profiles: [assistant]` to OpenClaw. Add Telegram bot
  integration service (profile: none — always on if `WALTER_TELEGRAM_BOT_TOKEN`
  set, otherwise no-op).
- Verify: `docker compose --profile devrel up -d` adds Postiz + Metabase only.

### Task 4: Write `scripts/bootstrap.sh` [AC-2, AC-3]
- File: `scripts/bootstrap.sh` (new)
- Change: Idempotent shell script. Checks `.bootstrapped` sentinel. Creates
  Plane workspace via API, Forgejo user via API, Infisical workspace via API,
  LiteLLM master key via API, Grafana admin password via API. Writes sentinel
  on success.
- Verify: First run creates all resources. Second run exits 0 with no changes.

### Task 5: Write Caddy config template [AC-1, AC-8]
- File: `setup/caddy/Caddyfile.template` (new)
- Change: Caddyfile that reverse-proxies all services under `${WALTER_DOMAIN}`
  subdomains. Uses `envsubst`-compatible `${VAR}` syntax. Bootstrap script
  runs `envsubst < Caddyfile.template > Caddyfile` before compose up.
- Verify: `curl -I https://plane.${WALTER_DOMAIN}` returns expected response
  after compose up.

### Task 6: Write `tests/compose/smoke.bats` [AC-7]
- File: `tests/compose/smoke.bats` (new)
- Change: Bats test. Starts compose (or subset) with test env vars. Curls
  health endpoint for each core service. Tears down after. Tags: `@slow`.
- Verify: `bats tests/compose/smoke.bats` passes on GitHub Actions Linux runner.

### Task 7: Write `templates/env.all.template` [AC-8]
- File: `templates/env.all.template` (new)
- Change: Single env template for the all-in-one compose. Contains the 5
  bootstrap vars plus optional vars with comments. Replaces the scatter of
  per-service `.env.example` files as the entry point for new operators.
- Verify: File exists. Contains exactly the 5 required vars plus clearly
  marked optional sections.

## References

- `setup/vm/services/*/compose.yml` — existing per-service composes
- `setup/vm/services/postgres/compose.yml` — shared postgres pattern
- `setup/vm/services/observability/compose.yml` — observability network model
- `docs/decisions/0010-oss-license.md`
