# Knowledge Profile Options

Walter-OS supports two different knowledge-management patterns. They are not
interchangeable: one is for shared team knowledge, the other is for local-first
personal thinking.

## Recommendation

Use **Outline + Linkwarden** for the optional Walter-VM `knowledge` profile.
Keep **Obsidian** as a personal/local-first recommendation outside the server
profile.

This is the default recommendation for:

- personal operators who want a browser-accessible shared knowledge base;
- startup or small-team installs up to roughly 10 people;
- agent workflows that need API-accessible runbooks, notes, and source links.

Obsidian remains the better choice for private writing, journaling, offline
notes, graph exploration, and markdown-first workflows where the operator wants
files to stay local or Syncthing-managed.

## Comparison

| Tool | Best for | Strengths | Trade-offs | Walter-OS stance |
|---|---|---|---|---|
| Outline | Collaborative knowledge base | Web UI, team permissions, collections, API, OIDC path via Authentik | Requires web app, database, object storage or local storage, admin setup | Add as optional `knowledge` profile app |
| Linkwarden | Shared bookmarks and research archive | Saves sources, tags links, archives pages locally, useful for research agents | Needs storage planning and retention rules | Add alongside Outline in `knowledge` profile |
| Obsidian | Local-first markdown workspace | Offline, fast, extensible, file-owned by operator, works with Syncthing | Not a natural multi-user self-hosted web app; team permissions and APIs are indirect | Recommend externally, do not run as Walter-VM service |

## Why Outline + Linkwarden for teams

Small teams need clear ownership, onboarding docs, shared runbooks, and access
control. Outline fits that shape better than a synced markdown vault:

- each person can have an account;
- spaces/collections can map to projects or functions;
- Authentik can become the OIDC identity provider later;
- agents can publish generated runbooks or summaries through an API;
- browser access works on any device without local vault setup.

Linkwarden complements Outline rather than replacing it. Outline is for durable
knowledge. Linkwarden is for source capture: competitor pages, vendor docs,
research links, launch references, and articles that may disappear or change.

## Why not Obsidian as a Walter-VM app

Obsidian is excellent, but its best qualities come from being local-first. A
Walter-VM server profile would add the wrong abstraction:

- Obsidian itself is not a multi-user server application.
- Sync is already covered by Syncthing, private git, or Obsidian Sync.
- Team permissions are not native to a shared folder.
- Agent write access to a personal vault can easily mix private notes with
  operational docs.

For personal use, the recommended pattern is:

```text
Obsidian vault       -> raw notes, journaling, private thinking
~/sync/wiki/         -> LLM-maintained structured wiki
Outline              -> optional shared/team-facing knowledge
Linkwarden           -> optional shared source archive
```

## Profile boundary

The future `knowledge` profile should be opt-in and disabled by default. It
should not alter the existing wiki, Syncthing, or Obsidian patterns.

Expected service boundary:

- `outline` at `https://outline.${WALTER_DOMAIN}`
- `linkwarden` at `https://links.${WALTER_DOMAIN}`
- Cloudflare Access remains the perimeter gate.
- Authentik, when enabled, can provide app-level identity and OIDC.
- Secrets are loaded from the approved Walter-OS secrets flow, not hardcoded.

## Implementation Scope

The `knowledge` profile should define a concrete, disabled-by-default service
surface. The later implementation PR should add the service files, but this
decision pins what that PR must include.

### Compose

- Add `setup/walter-host/services/knowledge/compose.yml`.
- Use `profiles: [knowledge]` for every service in the profile.
- Add `outline`, `outline-redis` if required by the current Outline release,
  and `linkwarden`.
- Use pinned image tags, not `latest` or floating major tags.
- Use named volumes for uploaded files, Linkwarden archived pages, and any
  cache/state directory that is not disposable.
- Use the shared Postgres service through separate databases:
  `outline` and `linkwarden`.
- Do not expose public ports directly; route only through Caddy.

### Environment and Secrets

The profile should ship an `.env.template` documenting these values:

- `OUTLINE_URL=https://outline.${WALTER_DOMAIN}`
- `OUTLINE_SECRET_KEY`
- `OUTLINE_UTILS_SECRET`
- `OUTLINE_DATABASE_URL`
- `OUTLINE_REDIS_URL`
- `LINKWARDEN_URL=https://links.${WALTER_DOMAIN}`
- `LINKWARDEN_NEXTAUTH_SECRET`
- `LINKWARDEN_DATABASE_URL`
- optional OIDC client IDs/secrets for Authentik integration

Secrets must be loaded from the approved Walter-OS secrets flow. The template
must not contain working defaults for signing secrets, database passwords, or
OIDC client secrets.

### Caddy and Access

- Add `outline.${WALTER_DOMAIN}` and `links.${WALTER_DOMAIN}` Caddy routes.
- Keep Cloudflare Access as the perimeter gate.
- Keep application-level login enabled inside Outline and Linkwarden.
- When Authentik is enabled, use it as the OIDC provider for app-level identity;
  do not make Authentik a hard dependency of the `knowledge` profile.

### Backups

The backup/runbook scope must include:

- Postgres databases for `outline` and `linkwarden`.
- Outline uploaded attachments or local object-storage volume.
- Linkwarden archived page volume.
- Restore smoke test: bring up the profile, restore DB + volumes, log in, open
  one Outline page, and open one archived Linkwarden link.

### Verification

The implementation PR should include static tests for:

- all services are profile-gated by `knowledge`;
- no image tag is floating;
- no direct public port is exposed;
- required secrets use fail-loud or documented secret-loader behavior;
- Caddy routes exist for both subdomains;
- backup docs mention DBs and volumes for both apps.

Before adding the profile, verify current upstream deployment requirements:

- Outline image tag, Node/runtime requirements, Redis requirement, object
  storage/local storage configuration, and required secrets.
- Linkwarden image tag, browser automation dependencies for archiving, storage
  volume layout, and required secrets.
- Postgres database creation path for both services.
- Caddy route and Cloudflare Access interaction.
- Backup inclusion for uploaded files and archived pages.

## Decision

Track implementation as an optional app profile. Do not replace Obsidian docs
or local-first workflows. The two paths coexist:

- **team/shared knowledge**: Outline + Linkwarden;
- **personal/local knowledge**: Obsidian + Syncthing/private git + `~/sync/wiki`.
