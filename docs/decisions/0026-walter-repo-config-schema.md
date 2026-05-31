# ADR-0026: `walter-repo-config.yaml` — unified per-repo policy file

**Status**: Proposed
**Date**: 2026-05-24
**Deciders**: Operator (f0x1777)
**Part of**: `docs/specs/autonomous-delivery-roadmap.md` (AD-5)
**Supersedes**: the standalone `.walter-os/auto-merge-authorized` touchfile
(`docs/specs/per-repo-auto-merge-touchfile.md`)

## Context

Per-repo autonomy policy was accreting into scattered markers: a
`.walter-os/auto-merge-authorized` touchfile (drafted this cycle), an
implicit hackathon context (`WALTER_CONTEXT=hackathons`), and the handoff
proposal's separate `.walter/autonomy.yaml`. Three files, three mechanisms,
for one concept: "what is this repo allowed to do autonomously?"

The operator's steer: ONE committed per-repo file declaring every flag + what
it does, with the ability to "be softer when explicitly enabled" (e.g.
`profile: hackathon`) — without ever relaxing the safety floor.

## Decision

Introduce **`walter-repo-config.yaml`** at the repo root — the single source of
per-repo policy. Committed (travels with the repo). Schema:

```yaml
# walter-repo-config.yaml
autonomy_mode: guided          # lite | guided | full   (default: guided)
profile: balanced              # balanced | hackathon | production
capability_tier_ceiling: 2     # 0..3 — max tier the agent can reach here (ADR-0023)

auto_merge:
  enabled: false               # replaces the auto-merge touchfile
  allowed_branches: ["walter/*", "demo"]
  forbidden_branches: ["main", "production"]
  require_green_ci: true
  min_walter_score: 90         # ADR/AD-11 Walter Score
  max_risk: low

verification: risk_based       # prototype | risk_based | production (ADR-0024)
preview_deploy: false          # AD-10

human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
```

Invariants:

1. **Hard limits are non-overridable.** No value in this file — not
   `autonomy_mode: full`, not `profile: hackathon`, not `auto_merge.enabled:
   true` — can authorize an `approval-gate.sh` "blocked for ALL tiers" action
   (push to main/staging, merge of protected branches, force-push, destructive
   shell/SQL, money-spending, auth/crypto/PHI/env writes, prod DB migrations,
   edits to hooks/AGENTS.md/install.sh). The file widens the *discretionary*
   surface only.

2. **Absence = safest defaults.** A repo with no `walter-repo-config.yaml`
   behaves as `autonomy_mode: guided`, `auto_merge.enabled: false`,
   `verification: risk_based`, `capability_tier_ceiling: 1`. Opting into more
   autonomy is always an explicit, committed act.

3. **First authorization is always manual.** A PR that ADDS or loosens
   `walter-repo-config.yaml` cannot benefit from the loosened policy — the
   policy is read from the default branch's HEAD as it was BEFORE the PR. So
   `auto_merge.enabled: true` added in a PR cannot self-merge that PR.

4. **Schema-validated.** `walter-os doctor` validates the file against this
   schema; unknown keys warn, malformed values fail-closed (treated as the
   safest default).

## Consequences

- **Positive**: one file, one mental model. The operator reads one place to
  know what a repo allows. Supersedes the touchfile + the scattered approach.
- **Positive**: the "softer when explicitly enabled" requirement is met without
  weakening safety — `profile: hackathon` relaxes verification depth + merge
  eligibility, never the floor (DEC-2 of the roadmap).
- **Negative / cost**: a new file format to document, validate, and version. It
  becomes part of the v1.0 stability contract surface (frozen schema +
  deprecation policy at v1.0).
- **Migration**: `docs/specs/per-repo-auto-merge-touchfile.md` is folded into
  the `auto_merge` block (roadmap AD-9). Repos using the touchfile during the
  interim get a deprecation warning from `walter-os doctor` pointing to the
  config file.
