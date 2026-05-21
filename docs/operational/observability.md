# Observability stack — operator host privileges

> Closes external-review F10 (issue #123). The Walter-OS observability
> stack (Prometheus, Loki, Promtail, node-exporter, cadvisor, Grafana)
> needs broad read-only access to the host to collect logs and metrics.
> This is normal for self-hosted observability — and it is **not** safe
> by default in the same sense that the rest of the Walter-OS compose
> stack is. This doc lists exactly what each observability container
> can see so adopters opt in deliberately.

**Source of truth**: `setup/walter-host/services/observability/compose.yml`.
This doc reflects the current state and is updated as part of the
quarterly upgrade cadence (`skills/quarterly-upgrade-cadence`).

## Host privileges granted to the observability profile

| Service | Read | Write | Privileged | Why |
|---|---|---|---|---|
| **prometheus** | service network only | own volume | no | Scrapes targets; no host filesystem access. |
| **loki** | service network only | own volume | no | Stores ingested logs; no host filesystem access. |
| **promtail** | `/var/log` (ro), `/var/lib/docker/containers` (ro), `/var/run/docker.sock` (mount flagged `:ro`) | **effective: read/write on the Docker API** (see below) | no | Tails every host log + every container log; uses the Docker socket to discover containers for log shipping to Loki. **Important caveat**: a `:ro` bind-mount on a Unix socket does not restrict the API surface — anything that connects to the socket can issue any Docker API call (start/stop/exec/destroy containers, mount host paths into new ones). Treat promtail's docker.sock access as full Docker daemon control + handle the container like an admin tool. |
| **node-exporter** | `/proc` (ro), `/sys` (ro), `/` as `/rootfs` (ro), `/var/lib/walter-council` (ro) | none | no, but `pid: host` | Exports host CPU / memory / disk / network metrics. Sees the host process table via `pid: host`. The full `/` mount is needed for filesystem-usage collectors; explicit `--collector.filesystem.mount-points-exclude` keeps `/sys`, `/proc`, etc. out of the metrics. |
| **cadvisor** | `/`, `/sys`, `/var/run`, `/var/lib/docker`, `/dev/disk` (all ro), `/dev/kmsg` (rw via `devices:`) | none | **yes (`privileged: true`)** | Per-container resource metrics. cadvisor upstream requires privileged mode to read kernel ring buffer (`kmsg`) and cgroup data — without it, container detection misses recent kernel versions. The broadest grant in the stack. |
| **grafana** | service network only | own volume | no | UI + dashboards. No host access. |

### What this means in practice

- **Promtail reads every log on the host.** If you put secrets in container stdout, they end up in Loki. Filter at the application layer or accept that Loki may contain sensitive log lines (and lock down Loki access accordingly — Grafana auth + admin_auth_gate Caddy snippet).
- **node-exporter + cadvisor can read your entire filesystem.** Read-only, but anything readable to `root` on the host is readable inside the container. Don't co-host secrets the host's `root` shouldn't see with the observability profile.
- **cadvisor is `privileged: true`.** A container escape from cadvisor would be a host compromise. This is an accepted risk in exchange for accurate container metrics — but it's the strongest argument for keeping the observability stack on a dedicated host or carefully-isolated VM.
- **Promtail's Docker socket access is effectively full daemon control.** The `:ro` flag on a Unix-socket bind-mount restricts the bind, not the API — any process inside the container that can `connect()` to `/var/run/docker.sock` can issue any Docker API call (including `containers/create`, `containers/exec`, host-path mounts on new containers, `system/prune`). A promtail compromise = a host compromise via the Docker daemon. Treat the promtail container as if it were a full admin tool.

### Hardening levers

- Pin every image by digest (`@sha256:...`), not tag, per `daily-supply-chain-audit`.
- Keep the observability stack on its own host or VM if you handle PHI / regulated data — the broad-read grants make multi-tenancy uncomfortable.
- Run `walter-os audit` daily. The current audit covers MCP servers,
  hooks, and external dependencies; **digest-pin enforcement for
  compose service images is a known gap** (tracked separately). Until
  that lands, the operator runs `git grep '@sha256:' compose.yml` or
  the manual quarterly review per `skills/quarterly-upgrade-cadence`.
- Review this doc + the compose every quarter (`skills/quarterly-upgrade-cadence`).

### What this profile does **not** grant

- No write access to the host outside its own volumes.
- No network access to the rest of the operator's tailnet by default — the observability containers sit on `obs_net` and only Grafana exposes a Caddy-mediated public surface (`grafana.${WALTER_DOMAIN}`, guarded by `admin_auth_gate`).
- Out of scope: any "what promtail CAN'T do" claims via the Docker socket. As noted above, a `:ro` bind on the socket does NOT restrict the Docker API — promtail's process is technically free to issue `docker run`, `exec`, `start`, `stop`, etc. We don't expect the *image* to do so (it's grafana/promtail upstream; container discovery is read-only by intent), but a compromise of the running promtail binary OR a malicious sidecar in the same container would have full daemon access. The hardening lever is "don't trust the container image" — pin by digest, monitor the daily audit. The mitigation lever — using a Docker socket proxy that exposes only read-only API endpoints — is tracked as a separate hardening task.

## Related

- `setup/walter-host/services/observability/compose.yml` — source of truth.
- `skills/daily-supply-chain-audit` — digest-pin enforcement, drift detection.
- `setup/caddy/Caddyfile.template` — `admin_auth_gate` snippet on `grafana.${WALTER_DOMAIN}`.
- Issue #123 / F10 — review feedback that triggered this doc.
