# Walter-host Port Policy

Walter-host runs many services on one VM. Use this policy before adding a
published host port, a Cloudflare Tunnel exception, or a local debugging URL.

## Principles

- Prefer container-DNS routing through Caddy over publishing service ports.
- Publish on `127.0.0.1` unless a service must accept public device traffic.
- Keep public host ports exceptional and documented.
- Use `ports.tsv` as the machine-readable source of truth.
- Standalone service compose files may reuse common ports because they are not
  expected to run all at once. Remap those ports before running conflicting
  standalone profiles together.

## Ranges

| Range | Use |
|---|---|
| `80`, `443` | Caddy public HTTP/HTTPS listeners |
| `1450-1499` | Local AI subscription routers |
| `3000-3099` | Local web UIs |
| `3450-3499` | LLM proxy adapters |
| `4000-4099` | LLM gateway APIs |
| `5000-5999` | Workflow and publishing tools |
| `8000-8199` | App proxies and web backends |
| `8200-8899` | Storage, sync, and secrets UIs |
| `9000-9199` | Observability, metrics, and dashboards |
| `18000-19999` | Large optional service internals |
| `22000` | Syncthing transfer traffic |
| `51820-51821` | WireGuard public endpoint and admin UI |

## Machine Map

The canonical machine-readable map lives at:

```text
setup/walter-host/ports.tsv
```

Columns:

```text
service	role	host_port	container_port	protocol	exposure	deploy_group	notes
```

`deploy_group=all-in-one` rows must not duplicate a `host_port/protocol` pair.
Standalone groups can duplicate ports across different profiles, but the notes
must make the conflict obvious when it matters.

## Cloudflare Tunnel

Most tunnel ingress entries point to central Caddy on `127.0.0.1:80`; Caddy then
routes by hostname to the right container on the Docker network. PostHog is the
current exception because its bundled proxy expects the request host to look like
`localhost:8000`.

`setup/walter-host/cloudflare/02-create-tunnel.sh` reads the PostHog tunnel
override from `ports.tsv`:

```text
posthog	tunnel	8100	8000	tcp	localhost	all-in-one
```

If another service needs a direct tunnel exception, add a new `all-in-one` row to
`ports.tsv`, document why it cannot go through central Caddy, then update the
tunnel tests.
