# walter-host extraction — depersonalization spec

**Status**: ready for `/write-plan` after operator approval of the migration approach (A vs B)
**Issue**: #44 (`[CHORE] -OPERATIONS- setup/walter-host contains operator-specific configs`)
**Target release**: v0.5.0 → v0.7.0 (multi-release migration; each service is its own small PR)
**Depends on**: nothing new in main — extends the existing overlay pattern.
**Parent**: `docs/specs/phase-w-5-depersonalization.md` (scope was scripts only; this is the same gap scaled up to ~31 services).
**ADR follow-up**: a new `docs/decisions/0014-walter-host-templating-strategy.md` will land alongside the first pilot migration PR.

## Problem

`setup/walter-host/` contains 31 self-hosted-service directories. Each one has at least:

- A `compose.yml` referencing one or more operator-specific tokens.
- A `deploy.sh` invoking `docker compose` from a hardcoded path or with hardcoded args.
- Per-service config / dashboards / workflows baked in.

Rough audit (`grep -rln` against the current `main`):

| Token / pattern | Files affected |
|---|---|
| `/mnt/walter*` host disk paths | 9 |
| `WALTER_DOMAIN` env var (already correct) | 54 — these are fine |
| `xipherlabs.xyz` literal | 0 — already migrated |
| `@solx.ar` SSO allow-list | 0 — already migrated |
| Operator personal home paths (`/home/nico`, etc.) | 0 — already clean |

The `/mnt/walter*` count is the real remaining gap. The 31 service stacks each assume that disk layout, which is operator-specific. A fresh adopter on EC2 / Hetzner / Linode with a different disk topology can't deploy any service that touches persistent state without rewriting paths first.

This is structurally the same gap that `syncthing-bootstrap.sh` had — but scaled to ~10× the files.

## Non-goals

- Refactoring all 31 services in one PR. Migration is per-service, ordered by risk.
- Replacing Docker Compose with Kubernetes / Nomad / etc.
- Building a service-mesh control plane. Out of scope; walter-host stays as a flat compose set.
- Auto-detecting the operator's disk layout. Operators declare it in overlay; we don't probe.

## Decisions (proposed)

### D-1 — Migration approach: **Option B (per-service overlay loader)**

The issue proposed two options:

- **Option A — Jinja-templated Ansible roles.** Move each service's `compose.yml` to `ansible/roles/walter-host/<service>/templates/`. Operator vars live in `group_vars/walter-vm.yml`.
- **Option B — Per-service `.example` files + overlay loader.** Each service ships `compose.yml.example` with placeholders. Operator overrides discovered via three-tier lookup.

**Choose Option B** for v0.5.0+ because:

1. **Stays in pure bash + Docker Compose.** No Ansible runtime dependency for the OSS adopter on day one.
2. **Mirrors the precedent that already shipped.** `bin/walter-os syncthing-bootstrap` already uses the three-tier overlay-discovery pattern (`${WALTER_OPERATOR_SCRIPTS_DIR}` → `~/.config/walter-os/overlay/scripts/` → `~/config-personal/scripts/`). Extending it is a known, reviewed approach.
3. **Lower migration friction.** No need for the operator to learn Ansible to customize a single service. Edit the overlay file, re-run `docker compose up -d`.
4. **Composes with operator's existing tooling.** If the operator later wants Ansible to manage Walter-OS deploys, they can wrap `walter-host bootstrap` in a playbook — but they're not forced into it on day one.

Option A remains viable for operators who DO use Ansible (it would be a future spec — operator authors their own playbook on top of the overlay-driven base). For walter-host's OSS surface, Option B is what gets us to "fresh-clone install" cleanly.

### D-2 — Overlay path convention

Mirror the existing scripts pattern, scoped to services:

```
~/.config/walter-os/overlay/walter-host/<service>/compose.yml      ← highest precedence
~/.config/walter-os/overlay/walter-host/<service>/deploy.sh
~/config-personal/walter-host/<service>/                            ← legacy path, deprecated but supported
<walter-os>/setup/walter-host/services/<service>/compose.yml.example ← OSS default with placeholders
```

`walter-os walter-host bootstrap <service>` resolves precedence and writes the active `compose.yml` to a runtime location (probably `${WALTER_RUNTIME_DIR}/walter-host/<service>/compose.yml`, defaulting to `/var/lib/walter-host/`).

### D-3 — Placeholder syntax

Use shell `${VAR}` substitution in `.example` files, expanded via `envsubst` at bootstrap time. No Jinja syntax (operator doesn't need a Python runtime). Required placeholders documented in each service's README:

| Placeholder | Source | Example |
|---|---|---|
| `${WALTER_DOMAIN}` | `personal.env` | `walter.example` |
| `${WALTER_HOST_DATA_DIR}` | `personal.env` (new) | `/mnt/walter-vm-data` |
| `${WALTER_INITIAL_USER}` | `personal.env` | `walter-admin` |
| `${WALTER_TIMEZONE}` | `personal.env` | `UTC` |

Any service-specific placeholder (e.g. `${PLANE_WORKSPACE_NAME}`) is documented in the service's README and validated by `walter-host bootstrap` before the substitution runs.

### D-4 — Migration order (risk ascending)

| Wave | Services | Why this order |
|---|---|---|
| **Wave 1 — stateless** (v0.5.0) | homepage, drawio, uptime-kuma | No persistent state. Rollback = redeploy. Lowest risk for the pilot. |
| **Wave 2 — read-mostly** (v0.5.x) | metabase, grafana (observability), n8n (workflows), penpot, postiz | Has state but state is recoverable from external sources. |
| **Wave 3 — stateful core** (v0.6.0) | litellm, infisical, headscale, syncthing, restic | Critical state. Per-service migration with operator-supervised rollouts. |
| **Wave 4 — most stateful** (v0.7.0) | plane, forgejo, synapse, openclaw | Largest blast radius. Last to migrate. |

Each wave's PRs reference this spec.

### D-5 — Pilot service

**Wave 1, pilot = `homepage`.** Smallest stateless service; the operator dashboard. Migration proves the pattern. Sign-off on the pilot before Wave 1's other two services proceed.

### D-6 — Operator-visible CLI

```bash
walter-os walter-host bootstrap [<service>]       # render+stage overlay
walter-os walter-host status                       # show which services use overlay vs example
walter-os walter-host diff <service>               # diff example vs effective overlay
```

The `diff` subcommand is critical: it tells the operator "your overlay is X commits behind the upstream example", surfacing drift that would otherwise rot silently.

### D-7 — Audit + test integration

- `tests/oss/walter-host-no-operator-tokens.bats` (new): grep against the migrated services for the W-5 forbidden-token list (`/mnt/walter*` literal paths, hardcoded SSO domains, operator email addresses, etc.). Fails CI if any unmigrated service ships a forbidden literal.
- `daily-supply-chain-audit` extended `check_walter_host_drift()`: if the operator overlay is `> 30d` older than the upstream example for any service, emit `info` finding.

## Acceptance criteria

### AC-1 — Spec + ADR
- [x] This spec exists (`docs/specs/walter-host-extraction.md`)
- [ ] ADR at `docs/decisions/0014-walter-host-templating-strategy.md` recording the Option-B choice with rejected alternatives.

### AC-2 — Inventory + tracking
- [ ] `docs/operational/walter-host-migration-inventory.md` (new): per-service table with status (`upstream-example` / `migrated` / `operator-only`), token count, last-touch date.
- [ ] Inventory regenerated by `walter-os walter-host status --inventory`.

### AC-3 — Pilot: `homepage`
- [ ] `setup/walter-host/services/homepage/compose.yml.example` (renamed from `compose.yml`) with `${WALTER_DOMAIN}` + `${WALTER_HOST_DATA_DIR}` placeholders.
- [ ] `setup/walter-host/services/homepage/deploy.sh.example` (renamed) with the same.
- [ ] `bin/walter-os walter-host bootstrap homepage` reads overlay, substitutes placeholders, writes effective `compose.yml` to `${WALTER_RUNTIME_DIR}/walter-host/homepage/`.
- [ ] `bin/walter-os walter-host status homepage` reports overlay path, example path, last-modified delta.
- [ ] `bin/walter-os walter-host diff homepage` shows the diff between example and effective overlay.
- [ ] bats test `tests/walter/walter-host-bootstrap-homepage.bats` (new) covers: bootstrap with no overlay → uses example; with overlay → uses overlay; status reports correctly; diff produces expected output.

### AC-4 — Wave 1 completion
- [ ] `drawio` + `uptime-kuma` migrated to the same pattern (their own PRs).
- [ ] After Wave 1, `tests/oss/walter-host-no-operator-tokens.bats` passes for the migrated three.

### AC-5 — Audit hook + drift reminder
- [ ] `skills/daily-supply-chain-audit/scripts/audit.sh` adds `check_walter_host_drift()`.
- [ ] Operator-overridable `WALTER_HOST_DRIFT_REMINDER_DAYS` (default 30).
- [ ] Findings are `info`-level (drift is a hygiene reminder, not a security finding).

### AC-6 — Operator-facing docs
- [ ] `docs/operational/walter-host-overlay-guide.md` (new): how to author an overlay, common placeholders, the `diff` workflow, the three-tier precedence.
- [ ] CHANGELOG entry per wave (`Wave 1 — homepage / drawio / uptime-kuma extracted to overlay`).

### AC-7 — Tracking issue closure
- [ ] #44 stays open across waves. Each wave updates the issue with a checklist of migrated services.
- [ ] #44 closes when `tests/oss/walter-host-no-operator-tokens.bats` covers every directory in `setup/walter-host/services/`.

## Threat model

- **Overlay file owned by the operator** (lives under `~/.config/walter-os/overlay/`). Standard operator-file integrity (P1-09 env-allowlist parser doesn't apply to YAML files directly, but the overlay path is already protected by the standing-approvals path lockdown).
- **`envsubst` injection risk**: a malicious `personal.env` could set `WALTER_DOMAIN='$(rm -rf /)'` and inject shell at substitution time. Mitigation: `envsubst` does NOT execute substitutions — it does string replacement only. We document this explicitly and add a bats test asserting that `WALTER_DOMAIN='$(echo pwned)'` lands as a literal string in the rendered compose.
- **Operator drift**: an overlay that's 6 months behind the upstream example can silently miss security patches in the example. Mitigation: AC-5 drift reminder. Operator chooses when to reconcile.

## Out of scope

- **Ansible-based deployment** (Option A from the issue). Future spec; operator can build it on top of the overlay-driven base if they want.
- **Kubernetes / Nomad / Swarm orchestration.** Walter-host stays compose-native.
- **Auto-merging upstream example updates into operator overlays.** Operator-driven only; the `diff` subcommand surfaces drift, doesn't resolve it.
- **Multi-host walter-host** (services split across multiple VMs). Single-VM remains the v0.5.0–v0.7.0 baseline.

## Recommended PR ordering

1. AC-1 + AC-2 — Spec + ADR + Inventory doc (this PR is the spec; ADR + inventory are the next PRs).
2. AC-3 — Pilot migration: `homepage` (Wave 1 starts). Operator signs off on the pattern.
3. AC-4 — Wave 1 finishes: `drawio` + `uptime-kuma`. Each PR ≤200 LOC.
4. AC-5 — Daily-audit `check_walter_host_drift()` (small change).
5. AC-6 — Operator-facing docs.
6. Wave 2 → Wave 3 → Wave 4 — each service its own PR, ordered by the migration table above.

## Open questions for the operator

1. **`${WALTER_HOST_DATA_DIR}` default**: should the example use `/var/lib/walter-host` (FHS-conventional) or keep the operator's existing `/mnt/walter-vm-data` (familiar to anyone running on Hetzner with mounted block storage)? Proposal: `/var/lib/walter-host` for OSS clarity; operator's overlay sets the real path.
2. **Should `walter-host bootstrap` be idempotent re-running, or refuse to overwrite an existing effective compose file?** Proposal: idempotent (re-renders), but emits a WARN if the existing file's content differs from the rendering — operator-edited drift is preserved-but-flagged.
3. **`WALTER_RUNTIME_DIR` location**: `/var/lib/walter-host/runtime` (system-owned, sudo required) vs `$XDG_RUNTIME_DIR/walter-host` (user-owned, simpler)? Proposal: user-owned (`$XDG_RUNTIME_DIR/walter-host` on Linux, `$HOME/Library/Caches/walter-host` on macOS).

## Refs

- Issue #44
- `docs/specs/phase-w-5-depersonalization.md` (parent spec)
- `docs/specs/syncthing-script-extraction.md` (precedent — single-script extraction)
- `docs/decisions/0011-depersonalization-strategy.md` (overlay-first ADR)
- `tests/oss/depersonalization.bats` (existing regression suite — this spec extends it)
- `bin/walter-os syncthing-bootstrap` (existing three-tier overlay-lookup pattern)
