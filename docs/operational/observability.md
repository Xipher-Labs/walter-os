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
| **promtail** | `/var/log` (ro), `/var/lib/docker/containers` (ro), `/var/run/docker.sock` (ro) | none | no | Tails every host log + every container log via Docker socket (read-only) for shipping to Loki. The Docker socket is the broadest grant — promtail can enumerate all containers and read their stdout/stderr streams. |
| **node-exporter** | `/proc` (ro), `/sys` (ro), `/` as `/rootfs` (ro), `/var/lib/walter-council` (ro) | none | no, but `pid: host` | Exports host CPU / memory / disk / network metrics. Sees the host process table via `pid: host`. The full `/` mount is needed for filesystem-usage collectors; explicit `--collector.filesystem.mount-points-exclude` keeps `/sys`, `/proc`, etc. out of the metrics. |
| **cadvisor** | `/`, `/sys`, `/var/run`, `/var/lib/docker`, `/dev/disk` (all ro), `/dev/kmsg` (rw via `devices:`) | none | **yes (`privileged: true`)** | Per-container resource metrics. cadvisor upstream requires privileged mode to read kernel ring buffer (`kmsg`) and cgroup data — without it, container detection misses recent kernel versions. The broadest grant in the stack. |
| **grafana** | service network only | own volume | no | UI + dashboards. No host access. |

### What this means in practice

- **Promtail reads every log on the host.** If you put secrets in container stdout, they end up in Loki. Filter at the application layer or accept that Loki may contain sensitive log lines (and lock down Loki access accordingly — Grafana auth + admin_auth_gate Caddy snippet).
- **node-exporter + cadvisor can read your entire filesystem.** Read-only, but anything readable to `root` on the host is readable inside the container. Don't co-host secrets the host's `root` shouldn't see with the observability profile.
- **cadvisor is `privileged: true`.** A container escape from cadvisor would be a host compromise. This is an accepted risk in exchange for accurate container metrics — but it's the strongest argument for keeping the observability stack on a dedicated host or carefully-isolated VM.
- **Promtail mounts the Docker socket read-only.** Docker socket access (even read-only) lets a container enumerate every other container's config, env vars, and labels. Treat the promtail container as if it were a sibling-aware admin tool.

### Hardening levers

- Pin every image by digest (`@sha256:...`), not tag, per `daily-supply-chain-audit`.
- Keep the observability stack on its own host or VM if you handle PHI / regulated data — the broad-read grants make multi-tenancy uncomfortable.
- Run `walter-os audit` daily; the audit checks for digest pins on all observability images.
- Review this doc + the compose every quarter (`skills/quarterly-upgrade-cadence`).

### What this profile does **not** grant

- No write access to the host outside its own volumes.
- No network access to the rest of the operator's tailnet by default — the observability containers sit on `obs_net` and only Grafana exposes a Caddy-mediated public surface (`grafana.${WALTER_DOMAIN}`, guarded by `admin_auth_gate`).
- No ability to start / stop other containers despite holding the Docker socket — promtail only uses the socket to list containers for log discovery (it doesn't invoke `docker run`, `exec`, etc.).

## Related

- `setup/walter-host/services/observability/compose.yml` — source of truth.
- `skills/daily-supply-chain-audit` — digest-pin enforcement, drift detection.
- `setup/caddy/Caddyfile.template` — `admin_auth_gate` snippet on `grafana.${WALTER_DOMAIN}`.
- Issue #123 / F10 — review feedback that triggered this doc.
