# Universal vs personal config split

> **Audience**: new operator forking Walter-OS, or anyone wondering why a
> specific file lives in the repo vs their personal overlay.
>
> **TL;DR**: the Walter-OS repo is a framework you fork and run. Your
> personal details — your domain, your API tokens, your company context —
> live in a separate overlay directory that never touches the public repo.
> This doc explains exactly where each kind of config lives and why.

See also: `docs/decisions/0011-depersonalization-strategy.md` for the
architectural reasoning behind this split.

---

## The two layers

### Layer 1 — OSS core (the repo you forked)

Everything in `github.com/your-handle/walter-os` (or the upstream). This
is the framework: scripts, hooks, skills, service definitions, templates,
and documentation. It has no personal information in it. It can be public.

**What this layer contains**:
- All shell scripts, hooks, and CLIs (`bin/walter`, `bin/walter-os`, `hooks/`)
- All agent skills (`skills/`)
- Agent definitions and specs (`AGENTS.md`, `docs/specs/`)
- Docker Compose service definitions (`compose.yml`, `setup/walter-host/services/`)
- Configuration templates (`.env.example`, `templates/`, `contexts/_examples/`)
- Install wizard (`install.sh`)
- Test suites (`tests/`)
- CI workflows (`.github/`)
- Wiki schema contract (`wiki/SCHEMA.md`)
- Operational runbooks (`docs/operational/`)
- ADRs (`docs/decisions/`)

**What this layer does NOT contain**:
- Your domain name, email, or timezone
- Any API token or secret
- Your company name or project names in any active config file
- Your personal agent approval rules

---

### Layer 2 — Personal overlay (`~/.config/walter-os/overlay/`)

Your personal overlay lives outside the repo entirely. It is never committed
to the Walter-OS repo. It can be in a private git repo, on Syncthing, or
backed up via restic — your choice.

**What this layer contains**:
- `.env.local` — your actual values for `WALTER_DOMAIN`, `WALTER_ADMIN_EMAIL`,
  `WALTER_TIMEZONE`, and all API tokens
- `contexts/work/AGENTS.md` — your company's stack, workflow rules, and
  project-specific agent context
- `contexts/projects-personal/AGENTS.md` — your personal projects, their
  tech stacks, and any regulatory context relevant to your jurisdiction
- `contexts/personal/AGENTS.md` — your life-admin context: finance, health,
  and journaling rules specific to where you live
- `agent-approvals.yml` — your standing approval rules for the agent
  trust tier system
- `keys/` — SSH keys and similar credentials (encrypted at rest)

**Overlay precedence**: when an AGENTS.md cascade runs, the overlay version
of a file takes precedence over the repo template. If
`~/.config/walter-os/overlay/contexts/work/AGENTS.md` exists, it loads
instead of `<repo>/contexts/work/AGENTS.md`. If the overlay file doesn't
exist, the repo's generic template loads as a fallback.

---

## Creating your overlay

Run once on each machine:

```bash
./setup/personal-overlay-init.sh
```

This creates `~/.config/walter-os/overlay/` with the skeleton directory
structure and copies the generic templates from `contexts/_examples/` as
starting points. It will not overwrite files that already exist (idempotent).

After running, fill in:
1. `~/.config/walter-os/overlay/.env.local` — your domain and email at minimum
2. The context files — as much or as little as you want. The generics work
   immediately; you're adding specificity over time.

---

## Decision table

For each config item: what it is, which layer it belongs to, and where it
lives on disk.

| Config item | Universal? | Personal? | Lives where |
|---|---|---|---|
| `WALTER_DOMAIN` | ❌ | ✅ | `overlay/.env.local` |
| `WALTER_ADMIN_EMAIL` | ❌ | ✅ | `overlay/.env.local` |
| `WALTER_TIMEZONE` | ❌ | ✅ | `overlay/.env.local` |
| `WALTER_INITIAL_USER` | ❌ | ✅ | `overlay/.env.local` |
| `ANTHROPIC_API_KEY` | ❌ | ✅ | `overlay/.env.local` (or Infisical) |
| `FORGEJO_TOKEN` | ❌ | ✅ | `overlay/.env.local` (or Infisical) |
| All other API tokens | ❌ | ✅ | `overlay/.env.local` (or Infisical) |
| `compose.yml` (service orchestration) | ✅ | — | `<repo>/compose.yml` |
| n8n workflow JSON (your automations) | — | ✅ | `overlay/n8n-workflows/` or n8n export |
| n8n workflow JSON (example template) | ✅ (as template) | — | `<repo>/templates/n8n/` |
| `skills/*/SKILL.md` content | ✅ | — | `<repo>/skills/` |
| Custom skill you wrote for your context | — | ✅ | `overlay/skills/` |
| `contexts/work/AGENTS.md` (generic template) | ✅ | — | `<repo>/contexts/work/AGENTS.md` |
| `contexts/work/AGENTS.md` (your company) | — | ✅ | `overlay/contexts/work/AGENTS.md` |
| `contexts/projects-personal/AGENTS.md` (generic) | ✅ | — | `<repo>/contexts/projects-personal/AGENTS.md` |
| `contexts/projects-personal/AGENTS.md` (yours) | — | ✅ | `overlay/contexts/projects-personal/AGENTS.md` |
| `contexts/personal/AGENTS.md` (generic) | ✅ | — | `<repo>/contexts/personal/AGENTS.md` |
| `contexts/personal/AGENTS.md` (yours) | — | ✅ | `overlay/contexts/personal/AGENTS.md` |
| `agent-approvals.yml` | ❌ | ✅ | `overlay/agent-approvals.yml` |
| `wiki/SCHEMA.md` (wiki structure contract) | ✅ | — | `<repo>/wiki/SCHEMA.md` |
| Your wiki pages (`wiki/people/`, etc.) | — | ✅ | `~/sync/wiki/` (Syncthing-managed) |
| `hooks/` (branch flow guard, approval gate) | ✅ | — | `<repo>/hooks/` |
| `install.sh` | ✅ | — | `<repo>/install.sh` |
| `bin/walter` + `bin/walter-os` CLIs | ✅ | — | `<repo>/bin/` |
| `templates/` (starter configs) | ✅ | — | `<repo>/templates/` |
| `contexts/_examples/` (labeled examples) | ✅ | — | `<repo>/contexts/_examples/` |
| Plane workspace ID | ❌ | ✅ | `overlay/.env.local` |
| Infisical project ID | ❌ | ✅ | `overlay/.env.local` |
| `.github/` CI workflows | ✅ | — | `<repo>/.github/` |
| `docs/specs/`, `docs/decisions/` | ✅ | — | `<repo>/docs/` |
| `keys/` directory | ❌ | ✅ | `overlay/keys/` (encrypted) |

**Both/hybrid cases**:
- **n8n workflows**: the repo ships example/template workflows; your actual
  automations are personal. Keep your automations exported to `overlay/n8n-workflows/`
  and import them via the n8n UI on each new install.
- **Grafana dashboards**: community dashboard IDs (from `docs/operational/`)
  are universal. Your customized dashboard JSON is personal — export it and
  store in `overlay/grafana/`.

---

## What "personal" means for secrets

`.env.local` is the simplest personal config mechanism — a plain text file
that is always gitignored. For production setups, Walter-OS routes secrets
through Infisical (self-hosted) so that:

1. Secrets are never in plaintext on disk at rest (Infisical encrypts them).
2. Secrets are fetched at runtime (12-hour session, Yubikey-gated on macOS).
3. Rotating a secret in Infisical rotates it everywhere without editing files.

The overlay's `.env.local` still exists as a fallback for local dev (e.g.,
before Infisical is set up, or on a machine with no Yubikey). Infisical is
the production-grade path; `.env.local` is the bootstrap path.

See `docs/specs/secrets-runtime-architecture.md` for the full secrets flow.

---

## Upgrading Walter-OS without breaking your overlay

When you pull upstream changes into your fork:

```bash
git pull upstream main
./install.sh --upgrade
```

The `--upgrade` path:
1. Updates the OSS core files (scripts, hooks, compose templates).
2. Runs `walter doctor` to check if your overlay references any skills or
   hooks that have changed incompatibly.
3. Does **not** touch anything under `~/.config/walter-os/overlay/`.

If a new version of Walter-OS adds a new generic template that you haven't
personalized yet, the generic template activates automatically (it's in the
repo). If you later want to personalize it, create the overlay version.

If a new version changes a SKILL.md that you've extended in your overlay,
`walter doctor` will flag the divergence — it won't auto-resolve it.

---

## For an LLM bootstrapping a new instance

If you are an agent running `install.sh` for a new operator, the expected
flow is:

1. The operator clones the repo.
2. `./install.sh` runs the interactive wizard.
3. The wizard calls `setup/personal-overlay-init.sh` to create the overlay
   skeleton.
4. The wizard prompts for `WALTER_DOMAIN`, `WALTER_ADMIN_EMAIL`,
   `WALTER_TIMEZONE`, `WALTER_INITIAL_USER`, and writes them to
   `~/.config/walter-os/overlay/.env.local`.
5. The wizard runs `walter providers configure` to let the operator select
   which providers to use (see `docs/specs/phase-w-4-provider-choice.md`).
6. All subsequent agent behavior is driven by the OSS core; the overlay adds
   the operator's personal context on top.

The agent should never write personal config to the repo itself. If asked to
store a domain name, an API key, or any user-identifying information, the
target is `~/.config/walter-os/overlay/` — not any file under the repo root.

---

## Personal config via overlay

The overlay directory (`~/.config/walter-os/overlay/`) can contain a
`personal.env` file that declares operator-specific values. Unlike the
AGENTS.md context files (which configure agent behavior), `personal.env`
sets shell variables that scripts, hooks, and CLI tools read directly.

### Location

```
~/.config/walter-os/overlay/personal.env
```

### Variables

| Variable | Description |
|---|---|
| `WALTER_DOMAIN` | Base domain for all service URLs (tower, git, plane, llm, secrets, etc.) |
| `GITHUB_USER` | Your GitHub username (used in update-check URL construction) |
| `WALTER_OS_UPDATE_REPO` | `owner/repo` for update checks — override if you maintain a fork |
| `NEXT_PUBLIC_WALTER_REPO_URL` | Full GitHub URL used in Control Tower badge and changelog links |
| `WALTER_COPYRIGHT_HOLDER` | Copyright holder name (for forkers maintaining their own NOTICE) |
| `WALTER_COPYRIGHT_YEAR` | Copyright year |
| `WALTER_MATRIX_USER` | Matrix/Synapse default admin user printed in onboarding hints |
| `WALTER_OPERATOR_EMAIL` | Operator email for ACME/Let's Encrypt and GitHub Codeowners |

### Precedence order (most-specific wins)

1. Env vars exported in your shell session (immediate override)
2. `${PROJECT_ROOT}/.env.local` (in-repo, gitignored, this checkout only)
3. `~/.config/walter-os/overlay/personal.env` (out-of-repo, shared across checkouts)
4. `${PROJECT_ROOT}/.env.example` defaults (generic placeholders)

The load order in `install.sh` and `bin/walter-os` implements this: the overlay
is sourced first, then `.env.local` is sourced on top. Any variable set in
`.env.local` overrides the overlay value. Shell exports override both.

### Bootstrap

Run once on each machine after cloning:

```bash
./setup/personal-overlay-init.sh
```

This copies `contexts/_examples/personal.env.example` to
`~/.config/walter-os/overlay/personal.env` (idempotent — skips if the file
already exists). Then edit the file to fill in your actual values.

To preview what the script would do without writing anything:

```bash
./setup/personal-overlay-init.sh --dry-run
```

---

## Operator-private git repo (advanced)

For operators running Walter-OS across multiple machines, or who want history
and backup of their personal config, the overlay can live in a **private git
repository** (commonly named `walter-personal`).

This is **optional** — single-machine operators do fine with the plain overlay.
Alternative: Syncthing (see [multi-device-sync.md](multi-device-sync.md)) syncs
the overlay directory across devices without git.

### When to use this pattern

- **Multi-device**: same config on laptop + desktop + homelab
- **History**: rollback if you break a context file
- **Backup**: survives `rm -rf ~/.config/walter-os/`
- **Selective sharing**: share parts of your overlay (no secrets!) with team

### Initialize from skeleton (first machine)

```bash
# 1. Scaffold the skeleton structure as your overlay
./setup/personal-overlay-init.sh --from-skeleton

# 2. (Optional) move overlay to a more convenient location
mv ~/.config/walter-os/overlay ~/walter-personal
ln -s ~/walter-personal ~/.config/walter-os/overlay

# 3. Initialize as a git repo
cd ~/walter-personal
git init

# 4. Rename .template files and fill in real values
mv personal.env.template personal.env
# ... edit each file, fill in real WALTER_DOMAIN, GITHUB_USER, etc.

# 5. Commit and push to your private remote
git add .
git commit -m "Initial walter-personal config"
gh repo create <your-user>/walter-personal --private --source=. --push
```

### Clone on subsequent machines

```bash
./setup/personal-overlay-init.sh --git-clone git@github.com:<your-user>/walter-personal.git
```

The script aborts with a clear error if `~/.config/walter-os/overlay/` already
exists — remove or back it up first.

### Security guidance

- **NEVER commit raw secrets** to walter-personal. Use Infisical/Vaultwarden
  references (e.g., `INFISICAL_SECRET_REF=/walter/prod/DB_PASS`)
- Set the repo `private` at creation; never make it public
- Even private, treat the repo as if compromised — operators rotate secrets
  via the secrets manager, not by editing values in walter-personal
- The skeleton's `.gitignore` excludes `.env` (no `.template` suffix),
  `.env.local`, `secrets/`, `*.key`, `*.pem` to catch common mistakes
