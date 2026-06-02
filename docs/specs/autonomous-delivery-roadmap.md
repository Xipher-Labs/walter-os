# Autonomous Delivery Roadmap — human-governed full-cycle delivery

**Status**: ready for `/write-plan` per-item
**Issue**: #TBD (epic — filed alongside this spec)
**Target releases**: v0.6.0 → v1.0
**Depends on**: OSS Trust roadmap (#122, layers A–C) · Walter Council v2
(`docs/specs/walter-council-v2.md`) · PR Review Severity Gate
(`docs/specs/pr-review-severity-gate.md` + ADR-0015)

## Problem

Walter-OS today is an excellent **agent safety + workflow framework**: the
`AGENTS.md` cascade, default-deny egress (shipped), the PreToolUse safety
chain, branch-flow discipline, SDD/TDD, the review loop, and the Walter
Council. What it is NOT yet is an **end-to-end delivery system** — the steps
from idea → spec → tasks → code → tests → PR → preview → merge → deploy →
observe exist as disconnected prompts + manual lane-dispatch, not as one
governed pipeline with persistent state, semantic gates, and a per-repo
policy that decides how much autonomy is allowed.

The next evolution moves Walter-OS toward a **human-governed autonomous
software delivery system**: agents can carry a feature from idea to deployed
preview automatically, while humans retain control over intent, architecture,
risk, merge, and production deploy. Crucially, autonomy is granted by
**policy + sandboxing + objective evidence**, never by disabling safety.

Positioning: *idea-to-PR-to-preview automation, with safety, observability,
and human governance built in.*

## Non-goals

- **Not** "zero-touch by default." The default stays human-in-the-loop
  (Guided Autonomy). Full autonomy is opt-in per repo.
- **Not** removing or weakening the shipped safety floor. The hard limits
  (auth / money / PHI / secrets / destructive ops) remain non-overridable.
- **Not** a re-spec of the OSS Trust primitives. Sandboxing, capability
  tokens, read-only mounts, audit chain, telemetry, and SLSA already have
  specs under #122 — this roadmap **consumes** them, it does not redefine
  them.
- **Not** a replacement for the operator's judgment on intent, architecture,
  merge, and production deploy. Those approvals stay human.

## What already exists (≈80% of the building blocks)

This roadmap is mostly an **orchestration layer + a unified per-repo policy
file** on top of primitives that are already specced. Do NOT re-implement
these — reference them:

| Primitive this roadmap consumes | Where it's specced | Status |
|---|---|---|
| Per-task process sandbox | `process-isolation-sandbox.md` (#122 A-3) | spec |
| Capability tokens | `capability-tokens.md` (#122) | spec |
| Read-only / invisible mounts | `read-only-mounts.md` (#122 A-5) | spec |
| Default-deny network egress | `network-egress-allowlist.md` + `hooks/network-gate.sh` | **shipped (PR #202)** |
| Audit chain + signed receipts | `audit-chain-merkle-and-receipts.md` (#122 B-1/B-2) | spec |
| Telemetry → Grafana/Loki | `audit-telemetry-grafana-loki.md` (#122 B-3) | spec |
| Severity gate + auto-merge logic | `pr-review-severity-gate.md` + ADR-0015 | spec |
| Per-agent trust tiers | ADR-0009 + `hooks/approval-gate.sh` | implemented |
| Multi-agent autonomy primitives | `multi-agent-autonomy.md` | spec |
| Council orchestration (F/M/R/T/U) | `walter-council-v2.md` | spec |
| SLSA L3 + reproducible builds | `oss-trust-supply-chain.md` (#122 C-1/C-2) | spec |

> Numbering note: `network-egress-allowlist.md` labels egress "A-1" while
> recent work called it "A-2". `oss-trust-roadmap.md` is the authority
> (A-1 egress, A-2 capability-tokens, A-3 process-isolation, A-4 time-bounded,
> A-5 read-only-mounts). The AD-9 sub-item reconciles this drift.

## Roadmap (5 phases, 14 items)

### Phase 1 — Orchestration core (v0.6.0)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| AD-1 | **Delivery Orchestrator agent + role model** — pipeline coordinator above the existing Council agents; maps the 6 lanes to the Product/Architect/Builder/Tester/Security/Reviewer/Release role model | v0.6.0 | 3–5d | ADR-0025 |
| AD-2 | **Persistent feature-state ledger** — `.walter/features/<id>/state.yaml` (idea, brief, spec, ACs, tasks, decisions, risks, PRs, post-merge); unifies today's scattered state (heartbeat / Plane / pause-flag) | v0.6.0 | 2–3d | New primitive |
| AD-3 | **`/full-cycle <idea>` command** — orchestrator entry point; drives brief → spec → ACs → tasks → impl → tests → PR, with human gates per autonomy mode | v0.6.0 | 2–3d | Depends AD-1, AD-2 |
| AD-4 | **Semantic gates** — spec-completeness, AC-testability, architecture-review, test-relevance (beyond the syntactic PreToolUse hooks + DoD validator) | v0.6.0 | 3–4d | Composes with severity-gate |

### Phase 2 — Autonomy policy axis (v0.7.0)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| AD-5 | **`walter-repo-config.yaml`** — single committed per-repo policy file declaring every flag (autonomy_mode, profile, capability_tier_ceiling, auto_merge, verification, preview_deploy, human_approval_required_for) | v0.7.0 | 2–3d | ADR-0026; central primitive |
| AD-6 | **Autonomy modes (Lite / Guided / Full)** — formalize as a policy axis ORTHOGONAL to install tier; Guided is the default | v0.7.0 | 2–3d | Reads AD-5 |
| AD-7 | **Capability tiers (evidence-based)** — graduate agent capability on objective evidence, superseding subjective "trust" framing | v0.7.0 | 3–4d | ADR-0023; extends ADR-0009 |
| AD-8 | **Risk-based + prototype verification** — verification ∝ risk × blast-radius; explicit `prototype` tier for hackathons/MVPs | v0.7.0 | 2–3d | ADR-0024 |
| AD-9 | **Fold auto-merge touchfile into repo-config** — reconcile `per-repo-auto-merge-touchfile.md` + `pr-review-severity-gate.md §4.5` into the `auto_merge` block of AD-5; fix the A-numbering drift in `oss-trust-roadmap.md` | v0.7.0 | 1d | Cleanup |

### Phase 3 — Human-review surface (v0.8.0)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| AD-10 | **Preview environments** — ephemeral per-PR deploy + seed data + screenshots + report bundle | v0.8.0 | 4–6d | GAP today |
| AD-11 | **Walter Score** — per-PR automated readiness score (spec compliance, AC coverage, test relevance, security/migration/rollback risk, observability, docs, preview) driving block / human-review / policy-auto-merge | v0.8.0 | 3–4d | GAP today; reads severity-gate + AD-4 |

### Phase 4 — Delivery integrations (v0.9.0)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| AD-12 | **Plane ↔ Forgejo PR-state automation** — PR lands → move Plane issue to done; ticket → branch/PR linkage both directions | v0.9.0 | 2–3d | Uses Plane MCP + forgejo-cli skill |
| AD-13 | **Post-merge feedback loop** — observe → detect regression → open fix-PR / recommend rollback → update feature state | v0.9.0 | 4–6d | Reads AD-2, telemetry B-3 |

### Phase 5 — Hackathon profile (v0.9.x)

| # | Item | Release | Effort | Notes |
|---|---|---|---|---|
| AD-14 | **Hackathon full-autonomy profile** — `profile: hackathon` in AD-5; relaxes verification depth + auto-merge eligibility + review rounds; NEVER relaxes the hard limits | v0.9.x | 2d | Reads AD-5, AD-6, AD-8 |

### v1.0 — stabilization (not new work here)

At v1.0 the autonomy **contract surface** (`walter-repo-config.yaml` schema,
autonomy-mode semantics, capability-tier rules, `/full-cycle` contract) — once
battle-tested across v0.6–v0.9 — JOINS the
`walter-os-v1-0-stability-charter.md` frozen layers with a deprecation policy.
v1.0 is a stability milestone, not a feature splash.

## Cross-cutting decisions

### DEC-1 — Autonomy is a policy axis, not an install tier

Install tier (Lite/I/II/III/IV) is about *infrastructure*. Autonomy mode
(Lite/Guided/Full) is about *approval policy*. They are orthogonal: you can run
Tier II with Guided autonomy, or Tier IV with Lite autonomy. `walter-repo-
config.yaml` carries the autonomy axis; the install tier stays where it is.

### DEC-2 — Hard limits are non-overridable, always

`profile: hackathon` (or any softening flag) relaxes ONLY: verification depth,
auto-merge eligibility, and review-round count. It NEVER relaxes the
`approval-gate.sh` "blocked for ALL tiers" list (push to main/staging, merge,
force-push, destructive shell/SQL, money-spending, auth/crypto/PHI/env writes,
prod DB migrations, hook/AGENTS.md/install.sh edits). This invariant is the
load-bearing principle of the whole roadmap.

### DEC-3 — Capability is earned by evidence, not trust

A repo's `capability_tier_ceiling` + the agent's graduation are functions of
objective signals (CI reliability, test coverage, sandboxing present, rollback
strategy present, branch protections, historical PR quality), not a subjective
"this agent has been good." See ADR-0023.

### DEC-4 — One per-repo policy file, not scattered markers

All per-repo policy lives in `walter-repo-config.yaml` (committed, travels with
the repo). This supersedes the standalone `.walter-os/auto-merge-authorized`
touchfile and the proposal's separate `.walter/autonomy.yaml`. See ADR-0026.

## Acceptance criteria (umbrella)

This epic closes when all 14 items above have shipped or been explicitly
deferred, AND:

- `walter-repo-config.yaml` is the single source of per-repo policy, with the
  hard-limits-non-overridable invariant enforced + tested.
- `/full-cycle <idea>` drives an idea to an opened PR + preview under Guided
  Autonomy, with human gates at intent / architecture / merge.
- The Delivery Orchestrator coordinates the existing Council agents through the
  pipeline with persistent feature-state.
- Walter Score + preview environments give the operator a review surface that
  does NOT require reading every generated line.
- The autonomy contract surface is documented for the v1.0 stability charter.

## Threat model

| Attack | Mitigation | Item |
|---|---|---|
| Repo opts into full autonomy + a malicious PR self-merges | `auto_merge.enabled` requires the flag to exist at HEAD of the default branch BEFORE the PR; a PR that ADDS the flag can't self-authorize | AD-5, AD-9 |
| Hackathon profile used to bypass the safety floor | Hard limits non-overridable by ANY profile (DEC-2); tested | AD-14, DEC-2 |
| Agent escalates its own capability tier | Capability is computed from objective repo signals, not self-asserted; ceiling is operator-set per repo | AD-7, DEC-3 |
| Full-cycle run exfiltrates via an unsandboxed step | Consumes the #122 sandbox + egress + capability-token + read-only-mount primitives; full autonomy requires them present | AD-6 reads #122 |
| Preview environment leaks real secrets/data | Preview uses seed data + scoped short-lived creds; never production secrets | AD-10 |
| Post-merge loop opens a runaway storm of fix-PRs | Loop bounded by capability tier + a max-fix-attempts cap; escalates to human on repeat failure | AD-13 |

## Explicitly rejected (anti-positioning)

Per the handoff proposal §19 — Walter-OS will NOT position itself as:

- "zero-touch by default" / "full access total" / "approval gates disabled"
- "98–100% autonomous" / "agents that work while you sleep unsupervised"
- "trust the agent more over time and reduce safety automatically"

The honest framing is **progressive autonomy with explicit policy and bounded
blast radius** — more autonomy through better control, not fewer controls.

## Recommended order of per-item specs

1. v0.6.0 batch: AD-2 (feature-state) → AD-1 (orchestrator) → AD-4 (semantic
   gates) → AD-3 (`/full-cycle`).
2. v0.7.0 batch: AD-5 (repo-config) → AD-6 (modes) → AD-7 (capability tiers) →
   AD-8 (verification) → AD-9 (reconcile).
3. v0.8.0 batch: AD-11 (Walter Score) → AD-10 (preview envs).
4. v0.9.0 batch: AD-12 (Plane↔Forgejo) → AD-13 (post-merge loop).
5. v0.9.x: AD-14 (hackathon profile).

## Refs

- OSS Trust roadmap: `docs/specs/oss-trust-roadmap.md` (#122)
- Walter Council v2: `docs/specs/walter-council-v2.md`
- PR Review Severity Gate: `docs/specs/pr-review-severity-gate.md` + ADR-0015
- Multi-agent autonomy: `docs/specs/multi-agent-autonomy.md`
- v1.0 stability charter: `docs/specs/walter-os-v1-0-stability-charter.md`
- ADRs: 0023 (capability tiers), 0024 (risk-based verification), 0025
  (Delivery Orchestrator), 0026 (`walter-repo-config` schema)
