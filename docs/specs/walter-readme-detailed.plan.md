# Implementation Plan: walter-readme-detailed

**Spec**: `docs/specs/walter-readme-detailed.md`
**Branch**: `feature/walter-readme-detailed`
**Estimated total time**: ~3 hours (4 tasks, sequential)

---

## Task 1: Build README.md — top half (sections 1–12) [AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8]

**Time estimate**: ~75 minutes

**File**: `README.md` (full rewrite — create new file at repo root, replacing
current content)

**Sections to produce in this task** (in order per spec):

1. Logo placeholder + tagline (`<!-- TODO: replace with logo asset -->` comment +
   "Walter-OS — A self-hostable AI-agent operations framework by Xipher Labs")
2. Badges row: `[![License: AGPL-3.0](...)][license]`, build status (GitHub
   Actions badge pointing to main CI workflow), contributors, stars, last-commit,
   alpha version shield.
3. One-paragraph value prop. Must include the IS NOT list (not a zero-config
   starter, not a stable API, not a generic agent framework). Three to four
   sentences maximum.
4. Quick demo: Mermaid diagram showing the three stack layers (Agent Contract →
   Skills + Agents + Commands + Hooks → Walter-VM + Council) OR an ASCII `tree`
   of the Homepage tiles. Choose Mermaid: renders on GitHub, degrades gracefully.
5. TL;DR install block: three commands only (`git clone`, `personal-overlay-init.sh`,
   `docker compose up -d`).
6. Table of contents (manual Markdown links to all 22 section anchors; use GitHub
   anchor conventions: lowercase, spaces as hyphens).
7. Personas section. Four persona cards:
   - **Builder** (solo engineer, shipping product fast)
   - **Founder** (pre-PMF, needs GTM tooling without a DevOps hire)
   - **Operator** (homelab enthusiast, life-OS)
   - **Hackathon participant** (brief mention, links to `contexts/hackathons/`)
   Each card: one-line summary, "this is for you if..." (2–3 bullets), "this is
   NOT for you if..." (2–3 bullets), link to relevant `contexts/<ctx>/`.
8. Stack at a glance. Full Markdown table with columns:
   `Service | What it does | Hostname | Profile | RAM budget | Docs`
   Services to include (derived from onboarding-checklist + existing README):
   - Plane, Forgejo, Infisical, LiteLLM (Walter-Bridge), n8n, Grafana,
     Uptime Kuma, WireGuard (wg-easy), Headscale, Headscale UI, Syncthing,
     Penpot, Drawio, RocketChat, Synapse, Element, Metabase, Postiz, PostHog,
     SeaweedFS (placeholder; note "planned" if not yet shipped), Homepage,
     Control Tower, OpenClaw, claude-code-router, gemini-cli-sub, codex-sub.
   Profile values: `core` (always-on) vs named profiles (`comms`, `design`,
   `analytics`, `marketing`, `monitoring`). Use the actual profile names from
   `setup/vm/services/` compose files; if unknown, use the most logical grouping
   and leave a `<!-- TODO: verify profile name -->` comment.
   RAM budget: use per-service SUGGESTIONS.md numbers where available; otherwise
   use known values (Metabase ~1GB, PostHog full hobby ~6GB, ClickHouse ~2GB,
   Grafana ~256MB, Plane ~512MB, Forgejo ~256MB, LiteLLM ~256MB, n8n ~512MB,
   Syncthing ~128MB, Penpot ~512MB, Synapse ~256MB, etc.). Add a footnote that
   values are typical RSS, not limits.
   Docs column: relative link to `setup/vm/services/<svc>/SUGGESTIONS.md` if it
   exists; otherwise `setup/vm/services/<svc>/` directory link.
9. Networking and access. Mermaid `graph TD` showing:
   - Internet → Cloudflare Tunnel → cloudflared on VM → Caddy reverse proxy →
     individual service containers
   - Tailscale overlay (Headscale): Control Tower restricted to Tailscale network
   - DNS pattern: `*.yourdomain.com` → Cloudflare → tunnel → Caddy
   - CF Access sits between Cloudflare and the tunnel (SSO gate)
   Short prose under the diagram: zero public ports, all TLS terminated by Caddy
   via Let's Encrypt, CF Access provides Google IdP SSO, Control Tower is
   additionally Tailscale-restricted.
10. Secrets flow. Mermaid `graph LR` or inline ASCII showing:
    ```
    Infisical (master vault)
        → .env.local (per-machine, gitignored)
            → docker compose env_file → containers
        → ~/.config/walter-os/overlay/personal.env (cross-machine)
    ```
    Prose: explain the three tiers (service secrets in Infisical, operator
    cross-device secrets in Bitwarden secure note, personal overlay env for
    context configuration). Reference `docs/operational/universal-vs-personal-config.md`
    for deeper detail. Include the bootstrap commands:
    `./setup/personal-overlay-init.sh` then `./scripts/bootstrap.sh`.
11. Multi-device strategy. Three-row Markdown table:
    | Approach | When to use | How |
    - Syncthing only (simple, no git, most common for non-technical users)
    - Private git repo overlay (want history + audit trail, recommended for engineers)
    - Separate workstation Ansible / dotfiles repo (existing dotfiles setup,
      treat overlay dir as a managed dotfiles module)
    Prose note: "most common for engineers: private git overlay. Syncthing is the
    simpler alternative for personal use." Reference `docs/operational/multi-device-sync.md`.
12. Resource budget + minimum specs. Four-row table:
    | Tier | Use case | Hetzner SKU | RAM | Approx cost |
    - Floor: core only, no PostHog/Postiz — CX42, 16GB, ~€11/mo (estimate)
    - **Recommended**: full stack, single operator — **CX53**, 32GB, **~€25/mo**
      (verify in Hetzner console; leave `<!-- TODO: verify current price -->`)
    - Production: dedicated CPU, multi-user — CCX33, 32GB dedicated, ~€53/mo
    - Heavy: PostHog full retention + replay storage — CCX43, 64GB, ~€102/mo
    Below the table: itemized RAM budget by service (reuse the numbers from step 8),
    formatted as a second table: `Service | Typical RSS | Notes`.
    Add a note: "Before provisioning, run `./setup/vm/preflight-check.sh` to
    verify minimum requirements."

**Content guard-rails for this task**:
- Do NOT reference any operator-specific domain, username, or email address.
  Use `yourdomain.com`, `you@example.com`, `youremail@example.com` as
  placeholders throughout.
- All cross-links to docs must be relative paths.
- Use Mermaid code blocks (` ```mermaid `) for diagrams — they render on GitHub.

**Verify**: `wc -l README.md` returns a value in the range 750–1300 after this
task (the top half; Task 2 adds the bottom half). Grep confirms no
`operator-handle|operator-email|private-domain` matches.

---

## Task 2: Build README.md — bottom half (sections 13–22) [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

**Time estimate**: ~60 minutes

**File**: `README.md` (append to file produced in Task 1)

**Sections to produce in this task** (in order per spec):

13. Step-by-step installation. Numbered list, ≥10 steps, each step dense and
    complete (command + purpose):
    1. Provision VM (Hetzner CX53 recommended; Ubuntu 24.04 LTS; at least 32GB
       RAM, 240GB SSD). Hetzner console: create server, select SSH key, enable
       backups if desired.
    2. DNS: point `*.yourdomain.com` A record to VM public IP (or configure
       Cloudflare Tunnel — recommended; skip the wildcard DNS step if using
       tunnel with Cloudflare Tunnel hostname routing).
    3. SSH into VM and install dependencies:
       `apt-get update && apt-get install -y git docker.io docker-compose-plugin`
    4. Clone the repo:
       `git clone https://github.com/<org>/walter-os.git /opt/walter-os && cd /opt/walter-os`
    5. Bootstrap the personal overlay on your **local machine** (not the VM):
       `./setup/personal-overlay-init.sh`
       Then edit `~/.config/walter-os/overlay/personal.env` — set at minimum:
       `WALTER_DOMAIN`, `WALTER_ADMIN_EMAIL`, `WALTER_TIMEZONE`.
    6. Configure secrets: run `./scripts/bootstrap.sh` on the VM — generates
       `.env.local` with secure random passwords for every service.
    7. Set up Cloudflare Tunnel (recommended, four scripts in order):
       `./setup/vm/cloudflare/01-create-zone.sh`
       `./setup/vm/cloudflare/02-create-tunnel.sh`
       `./setup/vm/cloudflare/03-install-cloudflared.sh`
       `./setup/vm/cloudflare/04-create-access.sh`
       Prereqs: Cloudflare account with the target domain added; `CF_API_TOKEN`
       and `CF_ACCOUNT_ID` exported.
    8. Build Control Tower image (required before compose up):
       `docker build -f apps/control-tower/Dockerfile -t walter-control-tower:latest .`
       Note: this step is mandatory even if you do not plan to use Control Tower
       immediately; the compose file references the image.
    9. Start core stack:
       `docker compose up -d`
       To include optional profiles:
       `docker compose --profile comms --profile analytics up -d`
    10. Verify: open `https://home.yourdomain.com` (Homepage) and
        `https://status.yourdomain.com` (Uptime Kuma). Caddy issues Let's Encrypt
        certs on first request — allow 60 seconds for cert issuance before
        refreshing.
    11. Per-service first-run: each service requires an operator-driven first-login
        (create admin account, set password). Consult each service's
        `setup/vm/services/<svc>/SUGGESTIONS.md` for the exact steps.
        Priority order: Infisical → Plane → Forgejo → n8n.
    12. Install the `obra/superpowers` Claude Code plugin on your local machine:
        `/plugin marketplace add obra/superpowers-marketplace`
        `/plugin install superpowers@superpowers-marketplace`
        Then restart Claude Code.

14. Customization patterns. Four sub-sections:
    - Per-service: edit the service's `.env.template` (in `setup/vm/services/<svc>/`),
      copy to `.env` (gitignored), set values. The compose file reads it via
      `env_file`.
    - Profiles: `docker compose --profile <name> up -d` to add optional services.
      Available profiles: `comms` (RocketChat, Synapse/Element), `design` (Penpot,
      Drawio), `analytics` (Metabase, PostHog), `marketing` (Postiz), `monitoring`
      (extended Grafana dashboards). Core services always start regardless of profile.
    - Per-skill: add operator-private skills at
      `~/.config/walter-os/overlay/skills/<skill-name>/SKILL.md`. The overlay is
      loaded by the agent contract without modifying the repo.
    - Per-context: four `contexts/<ctx>/AGENTS.md` templates in the repo; override
      them at `~/.config/walter-os/overlay/contexts/<ctx>/AGENTS.md`. The overlay
      version takes precedence.

15. Walter-Bridge and CLI clients. Prose + command blocks:
    - Why a gateway: single LiteLLM endpoint abstracts 17+ providers, provides
      unified spend dashboard, enables model aliasing (write `model: fast` in your
      code, configure the actual model in one place), and produces a single audit
      trail for cost attribution across all tools.
    - Model aliases: ~37 aliases (fast, smart, vision, embed, cheap, haiku, sonnet,
      opus, gpt-4o, gpt-4o-mini, gemini-pro, gemini-flash, mistral, llama3,
      codestral, and more). Full list: `setup/vm/services/litellm/config.yaml`.
    - CLI client setup: three supported CLIs, each with a template in
      `setup/vm/services/litellm/clients/`:
      - `claude-code-router`: `walter bridge install claude-code-router`
      - `gemini-cli`: `walter bridge install gemini-cli`
      - `codex-cli`: `walter bridge install codex-cli`
      Each install command generates the provider config pointing to
      `http://litellm.yourdomain.com` (or `localhost:4000` if port-forwarded).
    - Cost attribution: LiteLLM tags each call with `agent_id`, `task_id`, and
      `context`. Metabase dashboard at `https://analytics.yourdomain.com` surfaces
      spend by agent, task, and model. CLI: `walter-os spend report --by-agent`.

16. Operator contexts at a glance. Table of the four contexts:
    | Context | Directory | Loaded when | Use case |
    - `work` → `contexts/work/` → cwd matches `~/work/*`
    - `projects-personal` → `contexts/projects-personal/` → cwd matches
      `~/Projects/*`
    - `personal` → `contexts/personal/` → cwd matches `~/personal/*`
    - `hackathons` → `contexts/hackathons/` → cwd matches `~/hackathons/*`
    Cascade explanation: global (`AGENTS.md`) → context → repo-level `AGENTS.md`.
    Most-specific wins. Conflicts are resolved per-key, not per-file.
    Per-context PROMPT.md: paste-into-LLM template operators use to tailor a new
    conversation's system prompt to their current context.
    Per-context SKILLS.md: declares which Walter-OS skills auto-trigger.
    Deeper reading: `docs/operational/operator-contexts.md`.

17. n8n workflows. Brief prose + table:
    Six curated workflow suggestions in `n8n/workflows/<workflow>/README.md`.
    Operators import the workflow JSON into the n8n UI (Integrations → Import)
    then customize credentials and triggers.
    | Workflow | What it does |
    - `content-publishing`: cross-posts approved content to Twitter/X, LinkedIn,
      Mastodon on a schedule
    - `ai-cost-tracking`: ingests LiteLLM spend logs, categorizes by project,
      posts weekly digest to Telegram
    - `github-triage`: labels new GitHub issues, assigns to Plane, pings
      relevant channel
    - `expense-categorization`: reads bank export CSVs, classifies transactions,
      writes to Metabase
    - `hackathon-team-formation`: matches available skills to project requirements,
      notifies team channel
    - `customer-interview-synthesis`: ingests interview transcripts, extracts
      themes, drafts summary doc
    Each workflow README documents required credentials, trigger configuration,
    and expected output.

18. Updating. Three sub-sections:
    - Routine update (monthly recommended):
      ```bash
      git pull origin main
      docker compose pull
      docker compose up -d
      ```
    - Major version bumps: check `CHANGELOG.md` before `docker compose pull`.
      Breaking changes are annotated with `BREAKING:` prefix. Service data
      migrations (if any) are documented in `setup/vm/services/<svc>/MIGRATIONS.md`.
    - Submodule pins: `external/marchetto-agent-skills` is pinned to a commit
      hash in `.gitmodules`. If a `git submodule update` fails, check `.gitmodules`
      comments for the recovery pin. Never pull submodules from a branch; always
      from a pinned hash.

19. Troubleshooting. Table with columns `Symptom | Cause | Fix`. At least 15
    entries (generate from known issues surfaced during PR-#47/48/49/50 cycle and
    the onboarding checklist). Required entries:
    1. "Postiz fails to start / exits immediately" → `POSTIZ_PG_PASS` unset or
       contains special characters → regenerate with `openssl rand -hex 16`,
       restart: `docker compose restart postiz`
    2. "PostHog OOM at container startup" → 32GB VM minimum required; ClickHouse
       needs `ulimit -n 262144` → run `ulimit -n 262144` before compose; add to
       `/etc/security/limits.conf` for persistence
    3. "Control Tower image not found / compose fails" → image not built yet →
       `docker build -f apps/control-tower/Dockerfile -t walter-control-tower:latest .`
    4. "Cloudflare Tunnel cert error / CERT_INVALID" → stale tunnel token →
       re-run `setup/vm/cloudflare/02-create-tunnel.sh`, update `CLOUDFLARE_TUNNEL_TOKEN`
       in `.env.local`, restart cloudflared
    5. "ClickHouse won't start / segfault at startup" → `nofile` ulimit too low
       (must be 262144) → see `docs/operational/marketing-core-stack.md` for the
       exact `/etc/security/limits.conf` entry
    6. "Submodule fetch fails on clone (`fatal: reference is not a tree`)" →
       upstream force-pushed the pinned commit → use recovery hash in
       `.gitmodules` comments; update pin after verifying integrity
    7. "Walter-Bridge (LiteLLM) returns 401 Unauthorized" → `LITELLM_MASTER_KEY`
       in `.env.local` does not match what the container was started with →
       `docker compose down litellm && docker compose up -d litellm` with
       corrected key
    8. "Element won't complete login to Synapse ('Homeserver not found')" →
       `element/config.json.template` was not rendered during deploy → re-run
       `setup/vm/services/synapse/deploy.sh` which renders the template
    9. "Plane API returns 403 on all agent calls" → Plane API token expired or
       never created → log into Plane UI → Profile → API Tokens → create new →
       update `PLANE_API_TOKEN` in `.env.local` and in Infisical
    10. "Grafana dashboards show 'No data'" → Node Exporter not scraping or
        Prometheus datasource misconfigured → check `curl localhost:9090/targets`
        on the VM; verify `prometheus.yml` scrape interval
    11. "Forgejo SSH clone returns 'Permission denied (publickey)'" → SSH key
        not added to Forgejo account → Forgejo UI → Settings → SSH Keys → paste
        `~/.ssh/id_ed25519.pub`
    12. "Headscale node enrollment fails ('invalid auth key')" → preauth key
        expired (default 1h TTL) → generate a fresh key:
        `docker exec headscale headscale preauthkeys create --user 1 --reusable`
    13. "n8n workflow import fails ('version mismatch')" → exported workflow JSON
        was created with a newer n8n version → upgrade n8n:
        `docker compose pull n8n && docker compose up -d n8n`
    14. "RocketChat admin wizard loops / won't complete" → cookie issue in browser
        after a failed first-run → clear site data for the RocketChat URL, then
        retry in a fresh browser session
    15. "Metabase 'Database connection failed' on first setup" → Postgres container
        not reachable by name from Metabase network → verify both services share
        the same Docker network (`analytics_net`); check `docker network inspect
        analytics_net`
    16. "Syncthing 'Out of sync' for agent-memory folder" → conflicting edits from
        two machines → Syncthing creates conflict files (`.sync-conflict-*`); keep
        the newer timestamp, delete conflict files, rescan
    17. "Infisical 'Organization not found' on first login" → Machine Identity
        not created → Infisical UI → Organization → Machine Identities → create
        identity, export token to `INFISICAL_TOKEN` in `.env.local`
    18. "docker compose up fails: 'network not found'" → compose networks were
        not created yet → `docker compose down --remove-orphans` then
        `docker compose up -d`
    19. "LiteLLM model alias returns 'LLM Provider NOT provided'" → model alias
        not configured in `config.yaml` → add the alias under `model_list` in
        `setup/vm/services/litellm/config.yaml` and restart litellm
    20. "Caddy certificate issuance fails / 'ACME error'" → port 80 is blocked
        by a firewall rule (Caddy needs port 80 for the ACME HTTP-01 challenge)
        → open port 80 on the VM firewall (can be closed again after initial
        cert issuance if using Cloudflare Tunnel mode)

20. Contribution. Brief section (3–4 sentences) linking to `CONTRIBUTING.md`.
    Note that Walter-OS follows the standard fork-clone-branch-PR flow. Bug
    reports and feature requests go to GitHub Issues. Link to CODE_OF_CONDUCT.md.

21. Security. Brief section (3–4 sentences) linking to SECURITY.md. Note
    responsible disclosure address. Link to supply-chain audit documentation
    at `skills/daily-supply-chain-audit/SKILL.md`.

22. License + brand. Two subsections:
    - License: AGPLv3 (AGPL-3.0-or-later). Link to LICENSE. Note that any
      public network service built on Walter-OS must open its modifications
      under the same terms (AGPL copyleft). Commercial license available for
      operators who need to keep modifications private — contact
      `licensing@xipherlabs.xyz` or see COMMERCIAL.md.
    - Brand: "Walter-OS by Xipher Labs". Forkers replace the Xipher Labs
      attribution with their own organization. The name "Walter-OS" may be
      retained with attribution per the NOTICE file.

**Verify**: `wc -l README.md` returns a value in the range 1500–2500.
Grep confirms no `operator-handle|operator-email|private-domain` matches.
Manually spot-check that section headings from Task 1 and Task 2 are all present.

---

## Task 3: Write tests/oss/readme-detailed.bats [AC-11]

**Time estimate**: ~30 minutes

**File**: `tests/oss/readme-detailed.bats` (new)

**Change**: Create a bats test suite that asserts:

1. `README.md` exists at repo root (line 1 check).
2. Line count is ≥ 1500 and ≤ 2500:
   ```bash
   lines=$(wc -l < README.md)
   [ "$lines" -ge 1500 ] && [ "$lines" -le 2500 ]
   ```
3. All 22 required section headings are present. Use `grep -qF "## <heading>"`.
   Required headings (exact strings — implementer adjusts if spec headings differ):
   - `## Personas`
   - `## Stack at a glance`
   - `## Networking and access`
   - `## Secrets flow`
   - `## Multi-device strategy`
   - `## Resource budget`
   - `## Step-by-step installation`
   - `## Customization patterns`
   - `## Walter-Bridge and CLI clients`
   - `## Operator contexts at a glance`
   - `## n8n workflows`
   - `## Updating`
   - `## Troubleshooting`
   - `## Contribution`
   - `## Security`
   - `## License`
4. Operator-specific string absence (one `grep -c` per string, assert 0):
   - `operator-handle`
   - `operator.email`
   - `operator@`
   - `private.example`
5. Relative cross-link resolution: extract all Markdown links matching
   `](docs/` or `](setup/` or `](CONTRIBUTING` or `](SECURITY` or
   `](LICENSE` or `](COMMERCIAL` using `grep -oP '\]\(([^)]+)\)'` or
   equivalent POSIX grep, then for each path assert the file exists with
   `[ -f "$path" ]`. Note: links to directories (no `.md` extension) should
   use `[ -d "$path" ]`.
6. Troubleshooting entry count: `grep -c "^| " README.md` minus table header
   rows should yield ≥ 15 in the Troubleshooting section (simplest approach:
   count lines matching the troubleshooting table pattern between the
   `## Troubleshooting` and next `##` heading).

The bats file should use `setup()` to `cd` to the repo root and `teardown()`
to restore cwd. Each assertion is its own `@test` block.

**Which AC it contributes to**: AC-11 (primary), AC-3, AC-4, AC-5, AC-9
(verifiable via the test suite).

**Verify**: `bats tests/oss/readme-detailed.bats` exits 0 with all tests
passing against the README produced in Tasks 1–2.

---

## Task 4: CI verification + markdown lint [AC-12]

**Time estimate**: ~20 minutes

**Files**:
- `.github/workflows/readme-lint.yml` (new, or append to existing OSS workflow
  if one exists at `.github/workflows/oss.yml`)

**Change**: Add a GitHub Actions job that:

1. Runs `bats tests/oss/readme-detailed.bats` against the repo root README.
2. Runs `markdownlint --config .markdownlint.json README.md` if
   `markdownlint-cli` is available (install via `npm install -g markdownlint-cli`
   in the CI step). The `.markdownlint.json` config should at minimum disable
   `MD013` (line-length, too strict for a dense README) and keep `MD001`
   (heading hierarchy) and `MD034` (bare URLs) enabled.
3. Runs the existing cross-link verifier if one exists at
   `scripts/check-links.sh`; otherwise add a lightweight inline shell step
   that greps relative markdown links and asserts each path exists (mirrors
   the bats check but runs in CI as a belt-and-suspenders check).

If a `.markdownlint.json` does not already exist at repo root, create one:

```json
{
  "MD013": false,
  "MD033": false,
  "MD041": false
}
```

(`MD033` = no inline HTML, disabled because we use HTML for the logo placeholder
div. `MD041`: first line must be H1, disabled because we use `<div>` for centering.)

**Verify**: Push the branch and confirm the new workflow passes on GitHub Actions.
Alternatively, run locally:
```bash
bats tests/oss/readme-detailed.bats
markdownlint README.md
```
Both should exit 0.

---

## Dependency and sequencing notes

- Task 2 MUST follow Task 1 (appends to the same file).
- Tasks 3 and 4 can be done in parallel after Task 2, but in practice Task 3
  (bats) should run before Task 4 (CI) so the CI job can invoke the bats suite.
- The implementer should run `wc -l README.md` after Task 2 to confirm the
  1500–2500 range before writing the bats assertions; if out of range, adjust
  content (expand troubleshooting entries or condense duplicate prose) before
  Task 3.

## Decisions made (not requiring ADR)

1. **Mermaid over ASCII diagrams**: renders natively on GitHub and degrades
   gracefully to readable text in plain-text environments. No separate tooling
   required.
2. **README length cap of 2500 lines**: operator said "MUY detallado". 1500 is
   the floor. 2500 avoids a runaway file that becomes unmaintainable. The 20
   troubleshooting entries + full services table + numbered install steps should
   comfortably hit 1800–2200 lines.
3. **CX53 cost placeholder**: use ~€25/mo with a `<!-- TODO: verify -->` comment.
   Implementer checks the Hetzner console during Task 1 and updates if the
   current price differs.
4. **No ADR required**: this is a documentation task. No framework is being
   chosen, no data model is changing, no auth approach is being picked. The only
   structural decision (Mermaid vs ASCII) is documented inline above.
