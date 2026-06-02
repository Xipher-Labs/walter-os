# Customization patterns

Walter-OS is designed to be forked. All personal configuration lives in
`~/.config/walter-os/overlay/` (never in the repo). Four customization
layers cover the common cases.

## Layer 1 — Per-service customization

Each service has an environment template in
[`setup/walter-host/services/<svc>/`](../../setup/walter-host/services/).
Edit the relevant variables in `.env.local` (on the VM) or `personal.env`
(for cross-device non-secret config). The compose `env_file` directive
reads `.env.local` — never commit this file.

Common per-service tweaks:

- **Change service hostnames** — update `CADDY_<SVC>_HOST` variables in
  `.env.local`.
- **Change Postgres database names** — edit the `POSTGRES_DB_*`
  variables per service.
- **Disable a service** — comment out its service block in the root
  compose override.

## Layer 2 — Profiles

Optional service groups are activated with the `--profile` flag:

```bash
docker compose --profile comms up -d       # RocketChat + Synapse/Element
docker compose --profile design up -d     # Penpot + Drawio
docker compose --profile analytics up -d  # Metabase + PostHog + SeaweedFS
docker compose --profile marketing up -d  # Postiz
docker compose --profile monitoring up -d # extended Grafana dashboards
docker compose --profile tier4 up -d      # Control Tower + Council
```

Core services (Forgejo, Plane, Infisical, LiteLLM, n8n, Homepage, Uptime
Kuma, Headscale, Syncthing, Postgres, Restic, OpenClaw) always start
regardless of profile flags.

### Adding a new service as a profile

1. Create `setup/walter-host/services/<svc>/compose.yml` with `profiles:
   [<name>]` on the service definition.
2. Add a tile to `setup/walter-host/services/homepage/config/services.yaml`.
3. Add a Caddy route block to `setup/walter-host/services/caddy/Caddyfile`.
4. Document the RAM budget in [`stack-overview.md`](stack-overview.md) and
   in the service's directory README.
5. Run `tests/compose/` bats to catch obvious mistakes (env-template
   keys, healthcheck presence, profile tag).

## Layer 3 — Per-skill customization

Add operator-private skills (not suitable for the public repo) in:

```
~/.config/walter-os/overlay/skills/<skill-name>/SKILL.md
```

`install.sh` discovers skills in BOTH the repo `skills/` directory and the
overlay `skills/` directory, and symlinks them all into `~/.claude/skills/`.
The overlay version **takes precedence** if there is a name collision.

Skills follow the `SKILL.md` format — see any skill in
[`skills/`](../../skills/) for the template structure. The
`anthropic-skills:skill-creator` plugin skill walks you through authoring a new
one when the Anthropic skills plugin is installed.

## Layer 4 — Per-context customization

The four context templates in [`contexts/`](../../contexts/) define what
rules and skills apply when the agent's working directory matches a
specific path pattern.

| Context | Auto-load trigger |
|---|---|
| `work/` | `cwd` matches `~/work/*` |
| `projects-personal/` | `cwd` matches `~/Projects-Personal/*` |
| `personal/` | `cwd` matches `~/personal/*` |
| `hackathons/` | `WALTER_CONTEXT=hackathons` in the env |

Override any context template without modifying the repo:

```
~/.config/walter-os/overlay/contexts/<ctx>/AGENTS.md
```

The overlay `AGENTS.md` is loaded **instead of** the repo's template. Use
this for company-specific context (your stack, your Linear ticket format,
your staging URLs) that should not appear in the public repo.

## Related

- [`operator-contexts.md`](operator-contexts.md) — full cascade diagram +
  standards table
- [`universal-vs-personal-config.md`](universal-vs-personal-config.md) —
  what belongs in the repo vs the overlay
- [`contexts/_examples/`](../../contexts/_examples/) — real-world
  reference examples (labeled, not loaded by default)
