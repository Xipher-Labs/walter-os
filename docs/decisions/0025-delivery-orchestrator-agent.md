# ADR-0025: Delivery Orchestrator agent

**Status**: Proposed
**Date**: 2026-05-24
**Deciders**: Operator
**Part of**: `docs/specs/autonomous-delivery-roadmap.md` (AD-1)
**Relates to**: `docs/specs/walter-council-v2.md`, ADR-0009/0023

## Context

The Walter Council today is six agents in lanes (triage / researcher / coder /
reviewer / janitor / liaison) dispatched manually via `walter-os agents
run-once <agent> --issue <id>`. There is no coordinator that drives a feature
through the full delivery pipeline (idea → spec → tasks → code → tests → PR →
preview → merge → deploy → observe). The `/full-cycle` command (AD-3) needs
something to drive.

The handoff proposal called this a "CEO Agent." That name is imprecise and
gimmicky — it implies hierarchy/authority rather than coordination, and invites
the "agents working unsupervised" framing the roadmap explicitly rejects.

## Decision

Introduce the **Delivery Orchestrator** — a coordination agent, not a
super-agent.

1. **Role: coordinate, don't execute.** The Orchestrator receives an idea /
   ticket / `/full-cycle` command and: classifies the request, determines the
   operating mode (from `walter-repo-config.yaml`), assesses risk, creates/
   updates the feature-state ledger (AD-2), assigns work to specialized agents,
   enforces stage transitions + semantic gates (AD-4), requests human approval
   when policy requires it, and produces reports. It does NOT write code,
   review its own diffs, or merge.

2. **Specialist role model.** The pipeline's specialist roles map onto the
   existing Council agents (no new agent runtime needed initially):
   - Product (clarify intent, ACs) → orchestrator + architect subagent
   - Architect (approach, tradeoffs, risk) → `agents/architect.md`
   - Builder (minimal scoped impl) → `coder` lane
   - Tester (tests, edge cases) → `coder` lane (TDD) + DoD validator
   - Security (egress/secrets/auth/supply-chain) → `security-auditor` subagent
   - Reviewer (diff vs spec) → `reviewer` (tier high, read-only)
   - Release (changelog/version/rollback) → `liaison` + release tooling
   The roadmap's AD-1 spec decides which roles need dedicated agent definitions
   vs which are orchestrator-invoked subagents.

3. **The Orchestrator is bound by the same gates as everyone.** It runs under
   the PreToolUse safety chain, respects capability tiers (ADR-0023), and
   cannot perform the hard-limit "blocked for ALL tiers" actions. It requests
   human approval for intent / architecture / merge / production deploy per the
   repo's autonomy mode.

4. **Name.** "Delivery Orchestrator." Explicitly NOT "CEO Agent," "Manager
   Agent," or "Boss Agent."

## Consequences

- **Positive**: a single coordinator makes `/full-cycle` tractable + gives the
  feature-state ledger a clear owner; the specialist split is legible.
- **Positive**: reusing the existing agents/subagents avoids a parallel agent
  runtime; the Orchestrator is mostly control flow + state + gate enforcement.
- **Negative / cost**: the Orchestrator becomes a critical path — if it
  mis-classifies mode or skips a gate, the blast radius is the whole pipeline.
  AD-1 must make gate enforcement fail-closed (a missing/ambiguous gate result
  blocks progression + escalates to human), mirroring the PreToolUse hooks'
  fail-closed posture.
- **Relationship to Council v2**: the Orchestrator is the concrete realization
  of Council v2's autonomy improvements (Phases R/T); it does not replace the
  lane agents, it sequences them.
