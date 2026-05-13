# [FEAT] -SECRETS- Infisical Sidecar Rollout + OpenClaw Hardening + Gitleaks Hook

**Status**: Draft
**Owner**: operator
**Created**: 2026-05-12
**Linear/Plane**: #77

---

## Problem

All nine docker services running on Walter-VM (openclaw, litellm, n8n, plane, penpot,
synapse, wireguard, forgejo, observability) previously consumed secrets via plain `.env`
files on the VM filesystem. Plain env files carry three material risks:

1. **Commit risk.** A developer mistake or a stale ignore rule can push live credentials
   into the repo. The CI gitleaks scan (PR #55) guards against this only at commit time;
   it cannot retroactively protect secrets that have already been in a file on disk.

2. **Disk leak risk.** Any process with read access to the VM's filesystem can read those
   files. Backups (restic, snapshot) include them verbatim. A misfire in file permissions
   during an upgrade can silently expose the full credential set.

3. **Rotation friction.** Changing a credential requires SSHing into the VM, editing the
   file in place, and restarting the container. There is no audit trail, no approval gate,
   and no diff that can be reviewed. Accidental overwrite is silent and unrecoverable.

Separately, the OpenClaw compose block still needs more defense-in-depth at the container boundary:
no root-filesystem read-only mode, no capability drop, no privilege escalation prevention.
A supply-chain compromise of the openclaw npm package or its transitive dependencies would
have unrestricted write access to the container filesystem. This rollout is the target plan
for closing that gap in a dedicated implementation pass.

Finally, gitleaks is installed in CI (PR #55) and available locally. The repo now also has
a versioned `.githooks/pre-commit`, `scripts/setup-githooks.sh`, and `install.sh` wiring.
This spec records the contract those artifacts are meant to satisfy and keeps future
sidecar work aligned with the same fail-loud posture.

---

## Proposed solution

**Block 1 — Sidecar pattern (target state):** Each migrated service gets a companion
`<svc>-secrets` container that runs the `infisical/cli` image, authenticates to Infisical
using a Universal Auth machine identity stored at `/etc/walter-os/infisical-identity` on
the VM, exports secrets into a named Docker volume as a dotenv file, then exits. The main
service container depends on the sidecar completing successfully
(`service_completed_successfully`) and sources the dotenv file from the shared volume at
entrypoint. If the file is missing or empty, the service fails loud and immediately — no
silent degradation.

**Block 2 — OpenClaw container hardening (target state):** Beyond the sidecar, OpenClaw
should get `read_only: true` on its root filesystem, `cap_drop: [ALL]` with a minimal
`cap_add` whitelist, `security_opt: ["no-new-privileges:true"]`, and a pinned base image
digest with a pinned npm package version. The current public compose already fails loud on
`OPENCLAW_GATEWAY_TOKEN` and pins the OpenClaw npm package version; the remaining container
hardening is tracked here as follow-up work.

**Block 3 — Versioned gitleaks pre-commit hook (present):** `.githooks/pre-commit`,
`scripts/setup-githooks.sh`, and `install.sh` wiring are present in the repo. The allowlist
policy in `.gitleaks.toml` should remain path-specific for known test fixtures only; no
blanket `docs/specs/` or `*.md` escape hatches.

**Block 4 — secrets-runtime-architecture.md extensions (present):** The existing document
now covers per-service LiteLLM keys, the gitleaks hook, and related secret-runtime
guidance. A full service-sidecar walkthrough remains future work until the compose files
actually adopt the pattern.

**Block 5 — openclaw.md + openclaw-phase2-matrix-bridges.md (present):** The OpenClaw
gateway specs exist and cover the current deployment, trust model, and future
Matrix/Beeper bridge integration with operator-agnostic placeholders.

---

## Target Acceptance Criteria

These criteria describe the follow-up sidecar/hardening implementation. PR #93 records the
plan and adds the OpenClaw deploy helper; it does not claim the sidecar compose migration is
already present in `main`.

- [AC-1] All 9 services have `<svc>-secrets` sidecar blocks in their
  `setup/walter-host/services/<svc>/compose.yml`. The blocks follow the canonical pattern:
  `infisical/cli:0.43.84` image, `restart: "no"`, identity bind-mount, named secrets
  volume, non-empty validation before publish, `read_only: true`, `cap_drop: [ALL]`,
  `no-new-privileges:true`.

- [AC-2] `setup/walter-host/services/openclaw/compose.yml` for the `openclaw` service
  container has: `read_only: true`, `cap_drop: [ALL]`, `cap_add: [CHOWN, DAC_OVERRIDE,
  SETGID, SETUID]`, `security_opt: ["no-new-privileges:true"]`, base image pinned to
  `node:24-slim@sha256:<digest>` (not just the tag), and `OPENCLAW_VERSION: "2026.5.7"`
  (not `@latest`).

- [AC-3] `.githooks/pre-commit` exists, is executable (mode 755), and when run against a
  staged file containing a fake AWS access key, exits non-zero and emits a gitleaks
  finding to stderr.

- [AC-4] `scripts/setup-githooks.sh` exists, is executable, and is idempotent: running it
  twice on the same clone produces the same result with no error, and after running it
  `git config core.hooksPath` returns `.githooks`.

- [AC-5] `install.sh` calls `scripts/setup-githooks.sh` during the step-1 (deps) or
  step-0 (preflight) phase, conditional on gitleaks being installed (skips with a warning
  if not).

- [AC-6] `docs/specs/secrets-runtime-architecture.md` has at least four new sections
  appended after the existing content: "Service-level sidecar pattern", "9-service
  migration status", "Workspace policy", "Operator runbook — adding a new service". The
  existing sections (0 through 11.6) are preserved byte-for-byte.

- [AC-7] `docs/specs/openclaw.md` exists and contains no operator-specific literals:
  no hardcoded domain (use `${WALTER_DOMAIN}`), no bot handle (use
  `${WALTER_OPENCLAW_BOT_HANDLE}`), no personal user identifiers.
  `docs/specs/openclaw-phase2-matrix-bridges.md` exists under the same constraints.

- [AC-8] `tests/services/openclaw.bats` exists with at least 10 assertions covering:
  sidecar block presence, `read_only` flag, `cap_drop` block, `no-new-privileges`
  security_opt, image digest format, openclaw version env var present and not `@latest`,
  `depends_on` with `service_completed_successfully`, secrets volume mount on the main
  container, and entrypoint secret-check guard.

- [AC-9] `tests/hooks/gitleaks-precommit.bats` exists with at least 5 assertions: detects
  a fake AWS key in staged content (exits non-zero), allows a clean commit (exits zero),
  `setup-githooks.sh` idempotency (second run produces same `core.hooksPath`), pre-commit
  hook is executable, and `gitleaks protect --staged` is invoked by the hook (grep of hook
  body).

- [AC-10] `tests/oss/depersonalization.bats` passes green against all new and modified
  files. Specifically: no operator usernames, private project codenames, personal
  hardware identifiers, hardcoded domains, or social handles appear in any new file outside
  the exempt paths (`docs/specs/`, `contexts/_examples/`, `tests/oss/`). Existing compose
  depersonalization tests continue to pass.

---

## Non-goals

- **Migrating Infisical itself to the sidecar pattern.** Infisical cannot read its own
  DB password from Infisical (bootstrap circularity). It remains on plain `.env` with
  restic encryption at rest.

- **In-memory hot-reload of secrets.** Rotation requires a sidecar + service restart.
  That is sufficient for operator-driven rotation cadence; zero-downtime secret rotation
  is deferred.

- **IP allowlisting on the `walter-vm-prod` machine identity.** Infisical's self-hosted
  Community tier does not expose per-identity IP ACLs (Enterprise gate). Mitigations
  already in place: client-secret stored root-600, 30d TTL. Re-evaluate when/if a Pro
  license is justified.

- **Mac-side machine identity (`walter-mac-prod`).** The operator's Mac still uses
  interactive Infisical session. Per-device identity is recommended but not in scope here.

- **Vercel/CI Infisical integration** for hosted projects. Deferred to
  Q3 2026 per operator decision 2026-05-12.

- **Replacing `scripts/install-pre-commit.sh`.** The existing script writes to
  `.git/hooks/`. The new `scripts/setup-githooks.sh` uses `core.hooksPath`. Both coexist;
  the existing script is not removed.

- **Full supply-chain pinning of openclaw's transitive npm dependencies.** The compose
  file pins the top-level package version (`OPENCLAW_VERSION: "2026.5.7"`) and uses
  `--ignore-scripts --omit=optional`. A fully pinned npm lockfile baked into a custom
  Docker image layer is future work (noted in the openclaw spec as §10).

---

## Open questions

1. **node:24-slim digest pin.** The existing `openclaw/compose.yml` still uses
   `node:24-slim` without a digest. The implementer should `docker pull node:24-slim` on
   the VM and record the current amd64 digest before changing compose. **Decision needed
   from operator**: pin in the sidecar/hardening PR or defer to the next advisory cycle?

2. **openclaw version target.** `openclaw@2026.5.7` is pinned in compose. No action needed
   unless the operator wants to advance the pin. Implementer should confirm no patch
   releases have shipped since 2026-05-07.

3. **`tests/hooks/gitleaks-precommit.bats` scope vs existing `tests/hooks/gitleaks.bats`.**
   The existing file tests `.githooks/pre-commit` presence and the gitleaks config. The
   new file should test `scripts/setup-githooks.sh` behavior specifically. Implementer to
   verify the two files do not duplicate assertions (DRY principle); merge into existing
   file if overlap is >50%.

4. **observability compose — two-source sidecar.** The observability sidecar fetches from
   both `walter-vm-internal/prod/observability` and `walter-shared/prod` (for Telegram
   alerting vars). The Telegram vars are not yet populated in Infisical (`WALTER_TELEGRAM_BOT_TOKEN`,
   `WALTER_TELEGRAM_CHAT_ID`). The sidecar handles this gracefully (WARN, not fail). Should
   `tests/services/openclaw.bats` or a companion `tests/services/observability.bats` assert
   the two-source pattern specifically? Deferred to implementer judgment.

---

## References

- `docs/specs/secrets-runtime-architecture.md` — canonical secrets spec (extends this)
- `setup/walter-host/services/openclaw/compose.yml` — OpenClaw compose (implemented)
- `setup/walter-host/services/litellm/compose.yml` — two-source sidecar reference
- `tests/hooks/gitleaks.bats` — existing gitleaks hook tests
- `tests/oss/depersonalization.bats` — OSS depersonalization regression suite
- `scripts/install-pre-commit.sh` — existing hook installer (not replaced)
- `.gitleaks.toml` — gitleaks config with existing allowlist
- Closed PR #53 branch `origin/claude/zen-antonelli-f8aaf1` — reference implementation
  (do not cherry-pick; re-author clean)
- [Docker Hub node:24-slim](https://hub.docker.com/layers/library/node/24-slim/images/sha256-466ca909ab97ec41a9d186ac579f48e878610c1b31b0cd313da41e34f09ef942)
- [openclaw npm](https://www.npmjs.com/package/openclaw)

---

## Migration status (as of 2026-05-12 — informational)

This table reflects the public repository state at the time of PR #93. It intentionally
separates artifacts already present from target-state sidecar work that still needs a
dedicated implementation PR:

| Artifact | Status |
|---|---|
| 9 service compose.yml files with sidecar | Target state — follow-up implementation |
| OpenClaw hardening (`read_only`, caps, digest) | Target state — follow-up implementation |
| `docs/specs/openclaw.md` | Present in `main` |
| `docs/specs/openclaw-phase2-matrix-bridges.md` | Present in `main` |
| `docs/specs/secrets-runtime-architecture.md` extensions | Present in `main` |
| `.githooks/pre-commit` | Present in `main` |
| `scripts/setup-githooks.sh` | Present in `main` |
| `install.sh` integration for setup-githooks | Present in `main` |
| `tests/services/openclaw.bats` | Present in `main` |
| `tests/hooks/gitleaks.bats` | Present in `main`; covers the versioned hook |
| Depersonalization clean on all new files | Must be verified by PR gate |
