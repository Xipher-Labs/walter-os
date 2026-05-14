---
name: infisical-agent
description: How to consume Infisical secrets from every Walter-OS surface — operator shells, walter-host Docker services, Vercel deploys, Railway services, GitHub Actions, n8n workflows, Cursor, Claude Code. The unifying principle: NEVER paste secrets into config files; always pull from Infisical at runtime via CLI / SDK / native integration. Use this skill when the user asks "how do I use this secret in <X>", "Infisical setup for Vercel", "secrets in GitHub Actions", "n8n credentials".
---

# Infisical agent — secrets across the stack

Infisical (`secrets.${WALTER_DOMAIN}`) is the single source of truth. The
mechanism to *consume* differs per platform but the principle is one:
**plaintext secrets never live in your repos, dotfiles, or compose files**.

## The big picture

```
                ┌──────────────────────────────────┐
                │  Infisical (Walter-VM)           │
                │  workspaces:                      │
                │    walter-os                      │
                │    walter-vm-internal             │
                │    [company]                         │
                │    [project-a]                        │
                │    [project-b]                       │
                │    hackaton                       │
                └──────────────┬───────────────────┘
                               │
   ┌───────────┬──────────┬────┴────┬─────────┬───────────┐
   │           │          │         │         │           │
Operator  Walter-VM    Vercel   Railway   GitHub      n8n
shells    (Docker      (native) (native)   Actions    (built-in
          agent w/                         (action)    node)
          auto-renew)
```

Five distinct integration surfaces, one source of truth.

## 1. Operator shell — CLI + OS credential store

See full detail in `skills/secrets-yubikey-unlock/`, the legacy-named
credential-store bootstrap guide.

Quick version:

```bash
# Install
brew install infisical/get-cli/infisical

# Store the Infisical Machine Identity locally (macOS Keychain,
# Linux Secret Service, or pass+GPG).
walter-os secrets-identity-init --domain https://secrets.${WALTER_DOMAIN}

# Load secrets into the current shell.
walter_secrets_load
```

The operator shell approach is **interactive**. For autonomous services, use a
service-scoped machine identity (path #2).

## 2. Walter-VM (Docker services) — Infisical Agent (sidecar)

The recommended approach for production services on Walter-VM is the
**Infisical Agent** — a daemon that authenticates once with a machine
identity and writes secrets to a tmpfs-backed file that the application
reads.

### Setup pattern

```yaml
# In a service's compose.yml
services:
  app:
    image: myapp:1.0
    env_file: /run/walter-secrets/app.env    # tmpfs file, written by agent
    depends_on:
      infisical-agent:
        condition: service_healthy

  infisical-agent:
    image: infisical/cli:latest
    command: agent --config /etc/infisical/agent-config.yaml
    volumes:
      - ./agent-config.yaml:/etc/infisical/agent-config.yaml:ro
      - /run/walter-secrets:/run/walter-secrets:rw   # tmpfs!
    environment:
      INFISICAL_UNIVERSAL_AUTH_CLIENT_ID: ${INFISICAL_UA_CLIENT_ID}
      INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET: ${INFISICAL_UA_CLIENT_SECRET}
    healthcheck:
      test: ["CMD", "test", "-f", "/run/walter-secrets/app.env"]
      interval: 10s

# /run/walter-secrets is tmpfs — declared in /etc/fstab on the VM:
#   tmpfs /run/walter-secrets tmpfs size=16M,mode=0700,uid=walter 0 0
```

`agent-config.yaml`:

```yaml
infisical:
  address: https://secrets.${WALTER_DOMAIN}
auth:
  type: universal-auth
  config:
    client-id: env://INFISICAL_UA_CLIENT_ID
    client-secret: env://INFISICAL_UA_CLIENT_SECRET
templates:
  - source-path: /etc/infisical/templates/app.env.tpl
    destination-path: /run/walter-secrets/app.env
    config:
      polling-interval: 60s
      execute:
        command: "echo 'app secrets refreshed'"
```

Template (`app.env.tpl`):
```
{{ with secret "/" "walter-vm-internal" "prod" "DB_PASSWORD" }}DB_PASSWORD={{.SecretValue}}{{ end }}
{{ with secret "/" "walter-vm-internal" "prod" "API_KEY" }}API_KEY={{.SecretValue}}{{ end }}
```

**Net effect**: the application restarts whenever a secret changes (if you
configure the `execute` block to bounce the container), zero plaintext on
disk except in tmpfs which evaporates on reboot.

### Bootstrapping the machine identity

One-time, in Infisical UI:

1. Settings → **Machine Identities** → Create
2. Name: `walter-vm-services`
3. Auth method: **Universal Auth**
4. Scope: workspace `walter-vm-internal`, env `prod`, permissions: `read`
5. Save the `client_id` + `client_secret` somewhere SAFE
6. On VM: `sudo mkdir -p /etc/walter-vm/infisical && sudo chmod 700 /etc/walter-vm/infisical`
7. Write to `/etc/walter-vm/infisical/agent.env`:

```
INFISICAL_UA_CLIENT_ID=<client_id>
INFISICAL_UA_CLIENT_SECRET=<client_secret>
```

8. `chmod 600` and `chown root:root` on that file.
9. Reference it from each service's compose: `env_file: /etc/walter-vm/infisical/agent.env`.

After this, **secrets in compose.yml are never plaintext** — the agent
container fetches and renders them at runtime.

## 3. Vercel — native Infisical integration

Infisical has a first-party Vercel integration that mirrors a workspace
to Vercel project env vars on a schedule (or on-push).

### Setup

1. Vercel project → Settings → Integrations → search "Infisical" → install.
2. OAuth from Vercel → Infisical (consents to read).
3. In Infisical UI → Integrations → Vercel → Configure:
   - Workspace: `[project-a]`
   - Source environment: `dev` / `staging` / `prod`
   - Target Vercel project: `[project-a]-web`
   - Target Vercel env: `Preview` / `Production`
   - Sync interval: 5min recommended (or `manual` for prod)
4. Click Sync → verify Vercel env vars match Infisical.

**Critical**: never edit Vercel env vars directly after syncing — they're
overwritten on next sync. Edit in Infisical.

## 4. Railway — native Infisical integration (via `railway` CLI)

Railway also has a first-party Infisical integration:

1. Infisical UI → Integrations → Railway → Configure
2. Auth via Railway Project Token (per-project, not account-wide)
3. Map: workspace + env → Railway service env
4. Sync.

For deploys without Railway's UI integration:

```bash
# In a script or CI
railway run -- infisical run --workspace-name=[project-a] --env=prod -- pnpm start
```

Two-layer: Railway's `railway run` injects RAILWAY_*; Infisical's
`infisical run` injects everything else.

## 5. GitHub Actions — official action

```yaml
# .github/workflows/deploy.yml
- name: Fetch secrets from Infisical
  uses: Infisical/secrets-action@v1
  with:
    method: universal
    client-id: ${{ secrets.INFISICAL_UA_CLIENT_ID }}
    client-secret: ${{ secrets.INFISICAL_UA_CLIENT_SECRET }}
    project-slug: [project-a]
    env-slug: prod
    domain: https://secrets.${WALTER_DOMAIN}

- name: Deploy
  run: pnpm deploy
  # secrets are now in env vars
```

**Bootstrap secrets** (only ones in GitHub Actions secrets):
- `INFISICAL_UA_CLIENT_ID`
- `INFISICAL_UA_CLIENT_SECRET`

These two are bootstrapping creds and rotated quarterly.

## 6. n8n workflows — built-in Infisical credential type

n8n has a first-party Infisical node:

1. n8n → Credentials → New → Search "Infisical"
2. Auth method: Universal Auth
3. Domain: `https://secrets.${WALTER_DOMAIN}`
4. Client ID / Secret from machine identity scoped to needed workspace
5. In a workflow, use the **Infisical** node:
   - Operation: Get Secret
   - Workspace: `walter-os`
   - Environment: `dev`
   - Secret name: `ANTHROPIC_API_KEY`
   - Output goes into the workflow's data flow

For "fetch all secrets at once", use the JavaScript node:
```js
const { InfisicalClient } = require('@infisical/sdk');
const client = new InfisicalClient({
  clientId: $credentials.clientId,
  clientSecret: $credentials.clientSecret,
  siteUrl: 'https://secrets.${WALTER_DOMAIN}'
});
const secrets = await client.listSecrets({
  projectId: 'walter-os',
  environment: 'dev'
});
return secrets.map(s => ({ json: s }));
```

## 7. Cursor / VS Code — extension or shell

Two options:

**A. Extension** — `Infisical.infisical-vscode` from marketplace. Fetches
secrets and exposes them in the editor's env when running tasks. Easiest.

**B. Shell-based** — start Cursor with `infisical run` wrapping it:
```bash
infisical run --workspace-name=walter-os --env=dev -- cursor .
```

This way every terminal in Cursor inherits the env. Simpler but loses
secrets when Cursor restarts.

## 8. Claude Code / Codex CLI — through the wrapper

Claude Code respects the calling shell's env. So either:

```bash
# Approach A: load secrets in your shell session, then run claude
infisical run --workspace-name=walter-os --env=dev -- bash -c 'claude'

# Approach B: use Walter-OS's modular zshrc auto-loading.
# See the legacy-named skills/secrets-yubikey-unlock/ guide.
```

## Hard rules

- **Never commit `.env` files.** Even `.env.example` should have NO real
  values, only placeholders.
- **Never paste secrets into compose.yml.** Always reference via env or
  agent-rendered files.
- **Per-service machine identity.** Don't reuse one machine identity for
  everything. If `n8n` is compromised, you don't want it to have access
  to `[company]-shared` secrets.
- **Read-only by default.** Machine identities should only have
  `secrets:read`. Write access requires a separate identity used by
  `migrate-env-to-infisical.sh` and rotated immediately.
- **Audit log.** Infisical logs every secret read/write — review monthly.
  Anomalous patterns (10× normal volume, off-hour reads) → investigate.

## Migration checklist (for a new service)

When deploying a new service to Walter-VM:

```
[ ] Create Infisical workspace OR reuse `walter-vm-internal`
[ ] Set up environments (dev/staging/prod or just prod)
[ ] Add the secrets via Infisical UI
[ ] Create machine identity scoped to this workspace
[ ] Save client_id / client_secret to /etc/walter-vm/<service>/infisical.env (mode 600)
[ ] Add infisical-agent sidecar to service's compose.yml
[ ] Add agent-config.yaml that templates env file
[ ] env_file: ... in service block, pointing to agent-rendered tmpfs file
[ ] Deploy + verify the rendered file has correct values
[ ] NEVER commit the original .env or the machine identity creds
```

## Where Walter-OS skills already wire this

| Surface | Skill / file |
|---|---|
| Operator shell | `skills/secrets-yubikey-unlock/SKILL.md` |
| Operator shell modular zshrc | `templates/zsh.d/80-secrets.zsh` (in config-personal repo) |
| Walter-VM service deploy | (TODO) `setup/walter-host/services/<svc>/deploy.sh` should include agent |
| Vercel | `skills/vercel-cli/` references this as the canonical pattern |
| GitHub Actions | (TODO) `.github/workflows/*.yml` examples |
| n8n | (TODO) workflow templates in `setup/walter-host/services/n8n/templates/` |

The Phase K4 tasks include retrofitting all existing services to use the
agent-sidecar pattern — currently Plane / Forgejo / Infisical / LiteLLM
still have plaintext passwords in compose.yml (legacy from the manual
deploys). Track this in Plane issue `WALTER-VM-SECRETS-RETRO`.

## References

- https://infisical.com/docs/cli/usage
- https://infisical.com/docs/integrations/platforms/vercel
- https://infisical.com/docs/integrations/cicd/githubactions
- https://infisical.com/docs/sdks/languages/node
- https://infisical.com/docs/cli/agent — daemon mode reference
