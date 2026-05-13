# Implementation Plan: walter-infisical-sidecar-rollout

Refs: `docs/specs/walter-infisical-sidecar-rollout.md`

**Branch**: `feature/sidecar-retro-docs-openclaw-completion`
**Base**: `main` at v0.2.1
**Estimated total**: ~90 minutes across 12 tasks

The public repo currently has the OpenClaw trust-model specs, versioned gitleaks hook,
setup wiring, and static OpenClaw service tests. The Infisical sidecar blocks and full
OpenClaw container hardening are target-state work, not something this PR should claim is
already present in `main`.

---

## Task 1: Implement all 9 sidecar compose blocks to canonical pattern [AC-1]

**Time**: ~5 min
**Files**:
- `setup/walter-host/services/openclaw/compose.yml`
- `setup/walter-host/services/litellm/compose.yml`
- `setup/walter-host/services/n8n/compose.yml`
- `setup/walter-host/services/plane/compose.yml`
- `setup/walter-host/services/penpot/compose.yml`
- `setup/walter-host/services/synapse/compose.yml`
- `setup/walter-host/services/wireguard/compose.yml`
- `setup/walter-host/services/forgejo/compose.yml`
- `setup/walter-host/services/observability/compose.yml`

**Change**: Read each file. For every `<svc>-secrets` block, confirm:
1. `image: infisical/cli:0.43.84`
2. `restart: "no"`
3. `/etc/walter-os/infisical-identity:/etc/identity.env:ro` bind-mount
4. Named secrets volume in `volumes:` declaration
5. Non-empty check (`[ -s /secrets-out/<svc>.env.tmp ]`) before atomic rename
6. `chmod 644` on the tmp file before rename
7. `read_only: true` on the sidecar container
8. `cap_drop: [ALL]` on the sidecar container
9. `security_opt: [no-new-privileges:true]` on the sidecar container
10. Main service has `depends_on: <svc>-secrets: condition: service_completed_successfully`
11. Main service mounts `<svc>_secrets:/run/secrets:ro`
12. Main service entrypoint has `[ -s /run/secrets/<svc>.env ]` guard before sourcing

If a service still uses direct `.env` interpolation, migrate it in this task or split it
into a dedicated service-specific PR. Do not mark the task as verification-only until the
compose blocks actually exist in the repository.

**Verify**: `grep -r 'service_completed_successfully' setup/walter-host/services/` shows
9 services (or 10+ lines for services with multiple consumers like plane). All 9 service
names appear in the output.

---

## Task 2: Implement OpenClaw container hardening [AC-2]

**Time**: ~5 min
**Files**:
- `setup/walter-host/services/openclaw/compose.yml`

**Change**: Confirm the `openclaw` main service container (not the sidecar) has all of:
- `read_only: true`
- `cap_drop: [ALL]`
- `cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]`
- `security_opt: ["no-new-privileges:true"]`
- `image:` line is `node:24-slim@sha256:<64-char-hex-digest>` (not just tag)
- `OPENCLAW_VERSION:` env var is set to a version string (not `@latest`)
- `tmpfs:` mount for `/tmp` exists
- `openclaw_data:/workspace` is a writable named volume (not mounted read-only)

Resolve and record the current amd64 digest before changing the image line. Do not invent
or reuse a stale digest without a live pull on the target architecture.

**Verify**: after implementation, `grep -A1 'read_only' setup/walter-host/services/openclaw/compose.yml`
shows the expected `read_only: true` entries for the sidecar and main container.

---

## Task 3: Create `tests/services/openclaw.bats` [AC-8]

**Time**: ~15 min
**Files**:
- `tests/services/openclaw.bats` (update existing)

**Change**: Write a bats test file with at minimum 10 assertions against
`setup/walter-host/services/openclaw/compose.yml`. The file must not require Docker
or network access — all assertions are static analysis (grep/awk against the YAML file).

Assertions to include:
1. `openclaw-secrets` service block exists in compose.yml
2. `infisical/cli:0.43.84` image is referenced for the sidecar
3. `restart: "no"` is set on the sidecar
4. `/etc/walter-os/infisical-identity` bind-mount is present
5. `openclaw` main service has `read_only: true`
6. `openclaw` main service has `cap_drop` block containing `ALL`
7. `openclaw` main service has `no-new-privileges:true` in security_opt
8. `node:24-slim@sha256:` prefix is present (digest format, not just tag)
9. `OPENCLAW_VERSION` env var is present and does not equal `@latest`
10. `service_completed_successfully` appears in depends_on for openclaw
11. `/run/secrets:ro` mount is present on the `openclaw` main service
12. `[ -s /run/secrets/openclaw.env ]` guard appears in the entrypoint

File header comment: attribution to AC-8 of this spec.
No operator-specific identifiers in comments or assertions.

**Verify**:
```
bats tests/services/openclaw.bats
```
All assertions pass after Tasks 1 and 2 land. If a PR only documents the target state,
keep these assertions scoped to the current compose and add the sidecar assertions in the
implementation PR.

---

## Task 4: Create `.githooks/pre-commit` [AC-3]

**Time**: ~10 min
**Files**:
- `.githooks/pre-commit` (new)
- `.gitignore` if `.githooks/` is currently excluded (verify — it should NOT be ignored)

**Change**: Write a POSIX sh script:

```sh
#!/usr/bin/env sh
# walter-os: gitleaks pre-commit
#
# Runs gitleaks protect --staged against the index before every commit.
# Blocks the commit if any secret is found. Skips gracefully if gitleaks is
# not installed (prints a warning; does NOT block the commit — installation
# is opt-in for contributors).
#
# To install locally:
#   bash scripts/setup-githooks.sh
#
# To bypass in exceptional cases (document the reason in the commit body):
#   git commit --no-verify -m "..."
set -e

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "WARNING: gitleaks not found — pre-commit secret scan skipped." >&2
  echo "  Install: brew install gitleaks  OR  asdf install gitleaks" >&2
  exit 0
fi

gitleaks protect --staged --no-banner --config "$(git rev-parse --show-toplevel)/.gitleaks.toml"
```

Set executable bit: `chmod 755 .githooks/pre-commit`.

Check that `.gitignore` does not exclude `.githooks/`. If it does, remove that exclusion
and add a comment explaining why `.githooks/` must be versioned.

**Verify**:
```bash
# In a temporary git repo with a staged fake secret:
printf '%s\n' '<insert a known fake secret fixture here>' > leaky.env
git add leaky.env
.githooks/pre-commit    # must exit non-zero
echo $?  # must be non-zero
```
And with no staged secret: `.githooks/pre-commit` exits 0.

---

## Task 5: Create `scripts/setup-githooks.sh` [AC-4]

**Time**: ~10 min
**Files**:
- `scripts/setup-githooks.sh` (new)

**Change**: Write a bash script:

```bash
#!/usr/bin/env bash
# scripts/setup-githooks.sh — configure git to use .githooks/ as hooksPath
#
# Usage:
#   bash scripts/setup-githooks.sh           # configure + verify
#   bash scripts/setup-githooks.sh --dry-run # preview only, no changes
#
# Idempotent: safe to run multiple times. Second run prints "already configured"
# and exits 0.
#
# Prerequisites: gitleaks must be installed. If not, the script exits 1 with
# install instructions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Verify gitleaks installed
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "ERROR: gitleaks is required for the pre-commit hook." >&2
  echo "  macOS:  brew install gitleaks" >&2
  echo "  asdf:   asdf plugin add gitleaks && asdf install gitleaks latest" >&2
  echo "  Linux:  https://github.com/gitleaks/gitleaks/releases" >&2
  exit 1
fi

CURRENT="$(git -C "$REPO_ROOT" config core.hooksPath 2>/dev/null || true)"
if [[ "$CURRENT" == ".githooks" ]]; then
  echo "setup-githooks: already configured (core.hooksPath=.githooks)"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Would run: git config core.hooksPath .githooks"
  exit 0
fi

git -C "$REPO_ROOT" config core.hooksPath .githooks
chmod 755 "$REPO_ROOT/.githooks/pre-commit"
echo "setup-githooks: configured core.hooksPath=.githooks"
echo "setup-githooks: gitleaks $(gitleaks version 2>/dev/null || echo 'installed')"
```

Set executable bit: `chmod 755 scripts/setup-githooks.sh`.

**Verify**:
```bash
# In the repo root:
bash scripts/setup-githooks.sh
git config core.hooksPath  # must print ".githooks"
bash scripts/setup-githooks.sh  # must print "already configured" and exit 0
```

---

## Task 6: Wire `setup-githooks.sh` into `install.sh` [AC-5]

**Time**: ~8 min
**Files**:
- `install.sh` (modify)

**Change**: In `install.sh`, find the step-1 (deps check) function. Add a call to
`scripts/setup-githooks.sh` with a warning-only failure mode — if gitleaks is not
installed, print a warning but do not abort the install. The call should be guarded:

```bash
# Wire gitleaks pre-commit hook (idempotent; skip warning if gitleaks absent)
if command -v gitleaks >/dev/null 2>&1; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "scripts/setup-githooks.sh"
  else
    run_args bash "$REPO_ROOT/scripts/setup-githooks.sh" \
      && ok "gitleaks pre-commit hook configured" \
      || warn "setup-githooks.sh failed — run manually after fixing gitleaks install"
  fi
else
  warn "gitleaks not installed — skipping pre-commit hook setup (install later: brew install gitleaks)"
fi
```

Place this block near the end of the step-1 function, after the existing missing-tools
check.

**Verify**:
```bash
./install.sh --dry-run
```
Output includes a line referencing `setup-githooks.sh` or `gitleaks pre-commit`.
```bash
./install.sh --step 1 --dry-run
```
Same.

---

## Task 7: Create `tests/hooks/gitleaks-precommit.bats` extensions [AC-9]

**Time**: ~10 min
**Files**:
- `tests/hooks/gitleaks-precommit.bats` (new file, or extend `tests/hooks/gitleaks.bats`)

**Decision**: Read `tests/hooks/gitleaks.bats`. If it already tests `.githooks/pre-commit`
presence AND `setup-githooks.sh` behavior, extend it in-place (add new tests at the bottom).
If the overlap is under 50%, create a new file. Document the decision in the commit body.

**Assertions to add** (5 minimum):
1. `.githooks/pre-commit` file exists in the repo root
2. `.githooks/pre-commit` is executable (mode check)
3. Content of `.githooks/pre-commit` contains `gitleaks protect --staged` invocation
4. `scripts/setup-githooks.sh` is executable
5. Running `setup-githooks.sh` twice in a temp repo sets `core.hooksPath=.githooks`
   on first run and prints "already configured" on second run (idempotency)
6. `setup-githooks.sh --dry-run` does not modify `core.hooksPath`
7. `setup-githooks.sh` exits non-zero when gitleaks is absent from PATH

**Verify**:
```bash
bats tests/hooks/gitleaks-precommit.bats   # or gitleaks.bats if merged
```
All new assertions pass.

---

## Task 8: Create `docs/specs/openclaw.md` [AC-7]

**Time**: ~10 min
**Files**:
- `docs/specs/openclaw.md` (new)

**Change**: Write the openclaw service spec. Content shape (derived from PR #53 reference,
re-authored clean):

```markdown
# [FEAT] -OPENCLAW- OpenClaw gateway service

**Status**: Implemented
**Owner**: operator
**Created**: 2026-05-12

## Overview
[What OpenClaw is — multi-channel personal AI gateway — and what it provides:
Telegram bot interface, Control UI, LiteLLM routing. No operator-specific bot
handles or domain names. Use ${WALTER_OPENCLAW_BOT_HANDLE} and ${WALTER_DOMAIN}.]

## Deployment
[setup/walter-host/services/openclaw/compose.yml. Listens 127.0.0.1:18789.
Cloudflared tunnel to claw.${WALTER_DOMAIN}. CF Access SHOULD be in front.]

## Trust model
[Gateway token (OPENCLAW_GATEWAY_TOKEN) gates all API requests. Cloudflare
Access is the outer gate. Without CF Access, the only barrier is the token.
Risk: token leakage = full gateway access. Mitigation: rotate the token on any suspected
exposure; after the sidecar lands, rotation should be driven from Infisical.]

## Secrets
[OPENCLAW_GATEWAY_TOKEN, OPENCLAW_TELEGRAM_BOT_TOKEN, OPENCLAW_OPERATOR_CHAT_ID,
LITELLM_OPENCLAW_KEY — current compose consumes these from `.env` or exported env vars.
The sidecar implementation should move runtime injection to Infisical.]

## Container hardening
[read_only, cap_drop, no-new-privileges, pinned image digest. npm installed with
--ignore-scripts --omit=optional. Tmpfs for /tmp. Writable workspace via named volume.]

## Onboarding (first boot)
[docker exec -it openclaw <npm-global-bin>/openclaw onboard. Service sleeps until
onboarded. Healthcheck reports unhealthy until onboarding clears it.]

## Rotation procedure
[Rotate in the configured secret store → update host env material → docker compose up -d --force-recreate openclaw]

## Phase 2 (deferred)
[openclaw_net bridge to Synapse intentionally absent. See openclaw-phase2-matrix-bridges.md.]

## Section 10 — Future work: locked npm dependency graph
[Current: top-level version pin only. Future: prebuild custom image with package-lock
+ integrity hashes for full supply-chain pinning.]
```

Every section must use `${WALTER_DOMAIN}` and `${WALTER_OPENCLAW_BOT_HANDLE}` as
placeholders. No literal hostnames, no operator names.

**Verify**:
```bash
grep -iE '<forbidden-personal-or-project-literal>' docs/specs/openclaw.md
# must return no output
```

---

## Task 9: Create `docs/specs/openclaw-phase2-matrix-bridges.md` [AC-7]

**Time**: ~8 min
**Files**:
- `docs/specs/openclaw-phase2-matrix-bridges.md` (new)

**Change**: Write the Phase 2 spec covering Matrix/Beeper bridge integration. Content shape:

```markdown
# [FEAT] -OPENCLAW- OpenClaw Phase 2: Matrix/Beeper bridges

**Status**: Draft (deferred — no timeline)
**Owner**: operator
**Created**: 2026-05-12

## Problem
[Current: Telegram only. Phase 2: Matrix homeserver bridges (mautrix-whatsapp,
mautrix-telegram, mautrix-signal) join Synapse via openclaw_net. OpenClaw reads
events from Matrix rooms managed by the bridges.]

## Proposed solution
[Attach openclaw_net external network to OpenClaw and the relevant mautrix-* bridge
containers. OpenClaw reads Matrix room events via Synapse CS API. No changes to
Synapse homeserver config required.]

## Network topology
[diagram: operator device → Matrix client → Synapse (chat.${WALTER_DOMAIN}) →
mautrix-* bridge → WhatsApp/Telegram/Signal. OpenClaw reads from Matrix room events
via Synapse CS API or directly subscribes to Synapse event stream.]

## Prerequisites
[Phase 1 (Telegram bot) fully operational. Synapse deployed and healthy.
Bridge containers deployed with their own Infisical sidecar pattern.
openclaw_net bridge exists and is attached to both OpenClaw and the bridge containers.]

## Acceptance criteria
[List observable behaviors — e.g., "WhatsApp messages from ${WALTER_OPERATOR_USER}
route to OpenClaw and receive AI replies within 5 seconds on Walter-VM"]

## Non-goals
[E2E encryption bridging (Signal in particular). Multi-user access to bridges.
Public Matrix federation.]
```

Same depersonalization rules apply.

**Verify**:
```bash
grep -iE '<forbidden-personal-or-project-literal>' \
  docs/specs/openclaw-phase2-matrix-bridges.md
# must return no output
```

---

## Task 10: Append new sections to `docs/specs/secrets-runtime-architecture.md` [AC-6]

**Time**: ~10 min
**Files**:
- `docs/specs/secrets-runtime-architecture.md` (modify — append only)

**Change**: Append four new sections AFTER section 11.6 (the last existing section).
Do NOT modify any existing content above. The new sections are:

**§12. Service-level sidecar pattern**
- Architecture diagram (ASCII, matching the one already in §10.1 but at a higher
  abstraction level)
- Step-by-step walkthrough: identity auth → export → atomic rename → main container
  sources env file
- Sequence of Docker Compose lifecycle events: sidecar starts → sidecar exits 0 →
  main container starts → entrypoint sources `/run/secrets/<svc>.env`
- Failure modes: sidecar exits non-zero → main container never starts (depends_on
  condition); env file empty → main container fails loud at entrypoint guard

**§13. 9-service migration status (2026-05-12)**
- Table: service | workspace path | secrets count | status | notes
- Rows for all 9 services (openclaw, litellm, n8n, plane, penpot, synapse, wireguard,
  forgejo, observability) plus the infisical exclusion row
- LiteLLM and observability are two-source (internal + walter-shared); note this

**§14. Workspace policy**
- Table of Infisical workspaces: name | scope | contents | who can read
- Covers: walter-os, walter-vm-internal, walter-shared, plus project-specific
  workspaces represented only by placeholder names
- Cross-workspace policy decision (Option C chosen 2026-05-12 — dedicated
  walter-shared rather than cross-grant)

**§15. Operator runbook — adding a new service to the sidecar pattern**
- Numbered steps:
  1. Create the Infisical folder `/prod/<svc>/` in `walter-vm-internal`
  2. Add secrets to the folder (Infisical UI or CLI)
  3. Verify `walter-vm-prod` identity has Viewer access (inherited from project Viewer
     role — no per-folder grant needed)
  4. Copy the sidecar template block from §10.2 into the service's compose.yml
  5. Substitute `foo` → `<svc>` in all occurrences
  6. Add `--path=/<svc>` to the infisical export call
  7. Add `<svc>_secrets:` to the volumes section
  8. Modify the main container: add depends_on, volume mount, entrypoint guard
  9. Test: `docker compose up -d <svc>-secrets` — verify exit code 0 and secret count
  10. Then: `docker compose up -d <svc>` — verify healthcheck passes
  11. Commit the compose change

**Verify**:
```bash
grep -c '## §' docs/specs/secrets-runtime-architecture.md
# must be 16 or more (existing 0-11.6 headings + 4 new ones)
grep 'Operator runbook' docs/specs/secrets-runtime-architecture.md
# must match at least 1 line
```
The first 330 lines of the file (existing content) must be byte-identical to the
pre-edit state. Verify with: `git diff docs/specs/secrets-runtime-architecture.md`
— the diff should be additions only (no `-` lines in the existing content).

---

## Task 11: Run depersonalization check and fix any leaks [AC-10]

**Time**: ~5 min
**Files**: any new/modified file from tasks 3–10

**Change**: Run the depersonalization scan against all new files created in tasks 3–10:

```bash
grep -riE '<forbidden-personal-or-project-literal>' \
  docs/specs/openclaw.md \
  docs/specs/openclaw-phase2-matrix-bridges.md \
  docs/specs/secrets-runtime-architecture.md \
  tests/services/openclaw.bats \
  tests/hooks/gitleaks-precommit.bats \
  scripts/setup-githooks.sh \
  .githooks/pre-commit
```

If any match is found, fix it:
- Hardcoded hostnames → `${WALTER_DOMAIN}`
- Bot handles → `${WALTER_OPENCLAW_BOT_HANDLE}`
- Operator user identifiers → `${WALTER_OPERATOR_USER}` or "the operator"
- Project-specific names → keep out of new files entirely

Then run the full depersonalization bats suite:
```bash
bats tests/oss/depersonalization.bats
```
All tests must pass green.

**Verify**: `bats tests/oss/depersonalization.bats` exits 0.

---

## Task 12: Final integration verification and commit [AC-1 through AC-10]

**Time**: ~5 min
**Files**: none new

**Change**: Run the full test matrix for this PR:

```bash
# Service compose tests
bats tests/services/openclaw.bats

# Hook tests
bats tests/hooks/gitleaks.bats
bats tests/hooks/gitleaks-precommit.bats   # or gitleaks.bats if merged

# Depersonalization suite
bats tests/oss/depersonalization.bats

# Install dry-run
./install.sh --dry-run 2>&1 | grep -i 'githook\|gitleaks'

# Spec files exist
[ -f docs/specs/openclaw.md ] && echo "ok openclaw.md"
[ -f docs/specs/openclaw-phase2-matrix-bridges.md ] && echo "ok phase2.md"
```

Commit all task artifacts together in one atomic commit per task (or squash per block),
following conventional commits:

- `feat(secrets): add .githooks/pre-commit + setup-githooks.sh` — tasks 4+5
- `feat(install): wire setup-githooks.sh into install.sh step-1` — task 6
- `docs(openclaw): add openclaw.md + phase2-matrix-bridges.md specs` — tasks 8+9
- `docs(secrets): append §12-15 to secrets-runtime-architecture.md` — task 10
- `test(services): add tests/services/openclaw.bats` — task 3
- `test(hooks): extend gitleaks hook tests with setup-githooks assertions` — task 7

Each commit body: `Refs: docs/specs/walter-infisical-sidecar-rollout.md`
Each commit body: `Closes #77`

**Verify**: `git log --oneline` shows the expected commits. `bats` passes all tests.
PR opens targeting `main` only for this retroactive documentation/deploy-helper cleanup.
The sidecar/hardening implementation should use the normal branch flow for behavior changes.

---

## AC coverage matrix

| AC | Covered by task(s) |
|---|---|
| AC-1 | Task 1 |
| AC-2 | Task 2 |
| AC-3 | Task 4 |
| AC-4 | Task 5 |
| AC-5 | Task 6 |
| AC-6 | Task 10 |
| AC-7 | Tasks 8, 9 |
| AC-8 | Task 3 |
| AC-9 | Task 7 |
| AC-10 | Task 11, verified in Task 12 |
