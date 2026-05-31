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
| **prometheus** | `./prometheus/prometheus.yml` (ro config bind-mount), service network | own data volume | no | Scrapes targets; reads config from the repo at startup. No host-filesystem access beyond the mounted config. |
| **loki** | `./loki/loki.yml` (ro config), service network | own data volume | no | Stores ingested logs; reads config from the repo at startup. No host-filesystem access beyond the mounted config. |
| **promtail** | `/var/log` (ro), `/var/lib/docker/containers` (ro), `/var/run/docker.sock` (mount flagged `:ro`); optional `${WALTER_AUDIT_DIR:-/home/walter/.config/walter-os/audit}` as `/var/log/walter-audit` (ro) when `compose.audit.yml` is included | **effective: read/write on the Docker API** (see below) | no | Tails every host log + every container log; optionally tails Walter-OS audit-chain JSONL rows using `promtail.audit.yml`. Uses the Docker socket to discover containers for log shipping to Loki. **Important caveat**: a `:ro` bind-mount on a Unix socket does not restrict the API surface — anything that connects to the socket can issue any Docker API call (start/stop/exec/destroy containers, mount host paths into new ones). Treat promtail's docker.sock access as full Docker daemon control + handle the container like an admin tool. |
| **node-exporter** | `/proc` (ro), `/sys` (ro), `/` as `/rootfs` (ro), `/var/lib/walter-council` (ro) | none | no, but `pid: host` | Exports host CPU / memory / disk / network metrics. Sees the host process table via `pid: host`. The full `/` mount is needed for filesystem-usage collectors; explicit `--collector.filesystem.mount-points-exclude` keeps `/sys`, `/proc`, etc. out of the metrics. |
| **cadvisor** | `/`, `/sys`, `/var/run`, `/var/lib/docker`, `/dev/disk` (all ro) | `/dev/kmsg` via `devices:` (rw by default — kernel ring-buffer access) | **yes (`privileged: true`)** | Per-container resource metrics. cadvisor upstream requires privileged mode + `/dev/kmsg` to read kernel ring buffer + cgroup data; without them, container detection misses recent kernel versions. The broadest grant in the stack — `privileged: true` + `/dev/kmsg` write together = effective host kernel access. |
| **grafana** | `./grafana/provisioning/` (ro), service network | own data volume | no | UI + dashboards. Provisioning configs read from the repo at startup. No other host-filesystem access. |

### What this means in practice

- **Promtail reads every log on the host.** If you put secrets in container stdout, they end up in Loki. Filter at the application layer or accept that Loki may contain sensitive log lines (and lock down Loki access accordingly — Grafana login + the `admin_auth_gate` Caddy snippet which PR #130 adds to `grafana.${WALTER_DOMAIN}`; if that PR hasn't landed in your branch yet, the snippet protection isn't active and Grafana is reachable from any source the network permits).
- **Promtail can also read Walter-OS audit-chain rows.** Audit telemetry is opt-in so the default observability stack neither mounts nor scrapes `/var/log/walter-audit` on hosts where the audit-chain directory has not been created yet. To enable it, create the audit directory as the Walter operator and start with the override: `docker compose -f setup/walter-host/services/observability/compose.yml -f setup/walter-host/services/observability/compose.audit.yml up -d`. The override mounts `${WALTER_AUDIT_DIR:-/home/walter/.config/walter-os/audit}` read-only at `/var/log/walter-audit`, switches Promtail to `promtail.audit.yml`, and scrapes `/var/log/walter-audit/chain-*.jsonl` with static Loki labels `job=walter-audit-chain`, `app=walter-os`, `kind=audit-chain`, and `host=${WALTER_AUDIT_HOST:-walter-os}`. The bind uses `create_host_path: false`, so Docker fails loudly instead of silently creating a root-owned host path. Set `WALTER_AUDIT_DIR` before running this compose override when Walter uses a non-default config directory; it should point at the host audit directory itself, not its parent. Set `WALTER_AUDIT_HOST` when several Walter hosts ship into the same Loki. Promtail parses the JSON row's `ts` field as the Loki timestamp using `RFC3339Nano`, then forwards the JSONL line as-is; Grafana panels start from the static labels and use targeted LogQL parsing only for derived fields.
- **Grafana provisions the audit dashboard as `walter-audit`.** The dashboard uses the existing Loki datasource UID `loki` and starts from the low-cardinality selector `{app="walter-os", kind="audit-chain"}` for each panel. The distinct-session panel deliberately does not label `session_id`; it filters to matching lines and extracts only that field with the LogQL pattern parser instead of running `| json` over the full range.
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

- No DIRECT bind-mount write access to host filesystem paths (every host path mount is `:ro`). **Caveat**: promtail's read-write access to `/var/run/docker.sock` gives it indirect host-write capability via the Docker API (create container with `-v /:/host` etc.) — already documented above. The "no direct bind-mount write" claim applies only to the bind paths declared in compose.yml, not the daemon-level capabilities the socket grants.
- No network access to the rest of the operator's tailnet by default — the observability containers sit on `obs_net` and only Grafana exposes a Caddy-mediated public surface (`grafana.${WALTER_DOMAIN}`, guarded by `admin_auth_gate`).
- Out of scope: any "what promtail CAN'T do" claims via the Docker socket. As noted above, a `:ro` bind on the socket does NOT restrict the Docker API — promtail's process is technically free to issue `docker run`, `exec`, `start`, `stop`, etc. We don't expect the *image* to do so (it's grafana/promtail upstream; container discovery is read-only by intent), but a compromise of the running promtail binary OR a malicious sidecar in the same container would have full daemon access. The hardening lever is "don't trust the container image" — pin by digest, monitor the daily audit. The mitigation lever — using a Docker socket proxy that exposes only read-only API endpoints — is tracked as a separate hardening task.

## Related

- `setup/walter-host/services/observability/compose.yml` — source of truth.
- `skills/daily-supply-chain-audit` — digest-pin enforcement, drift detection.
- `setup/caddy/Caddyfile.template` — `admin_auth_gate` snippet is being added to `grafana.${WALTER_DOMAIN}` in PR #130 (until that lands, grafana is reverse-proxied without the gate; the snippet itself is already defined in the template head).
- Issue #123 / F10 — review feedback that triggered this doc.
