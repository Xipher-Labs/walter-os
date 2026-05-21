# 0015. PR review severity gate — bounded auto-merge with per-repo opt-in marker

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/pr-review-severity-gate.md`
**Plan**: `docs/specs/pr-review-severity-gate.plan.md`

## Context

PR #111 (merged 2026-05-21) burned **4 review rounds, 24 Copilot findings, 10 fix commits** to close what was substantively documentation drift. Across all four rounds, **zero findings touched** `auth/`, `crypto/`, money flows, or PHI. The cycle continued because the Walter-OS review loop in `AGENTS.md` treats every finding identically:

> Round 1 — Copilot → address each finding → re-request review
> Round 2 — Codex cross-review → address each finding → re-request
> Round 3 — Collaborative if anything remains
> After Round 3 — escalate to operator

In practice this means a finding like "use `[[:space:]]` instead of `\s` in `grep -E`" extends the loop the same as a finding like "this commit leaks an API key". The operator's natural intent ("merge when only minor stuff remains, defer cleanup to follow-ups") has no expression in the current contract.

Two structural problems flow from this:

1. The "Never auto-merge a PR. The operator clicks merge." hard rule in `AGENTS.md` has no relief valve. For a 4-round-converged documentation PR, the operator either merges by feel (no traceability of what was deferred) or keeps looping cosmetic items.

2. There's no signal pipeline that distinguishes "safe to merge with N MINOR follow-ups" from "must not merge — there's a real bug". Both end up routed through the same human-eyes ritual.

The operator surfaced both problems during PR #111 review and proposed: classify findings by severity, after a bounded number of rounds with only MINOR/COSMETIC remaining, auto-merge with the deferred items spawning a follow-up issue. Grave findings spin off a new issue + a diagnostic PR comment, **but the PR is NOT auto-closed** — closure is the operator's decision (see Decision 4). Opt-in per repo via a marker file in repo root.

## Decision

**Introduce a severity-gate auto-merge mechanism with five locked decisions:**

### Decision 1 — Four-tier severity taxonomy

`BLOCKER | MAJOR | MINOR | COSMETIC`. Boundaries:

- BLOCKER touches an auto-escalation path. The list combines (a) the AGENTS.md "auto-escalate to major" + "Blocked for ALL tiers" union (auth/, crypto/, money, PHI, audit logs, prod migrations, hooks/, install.sh, mcp/servers.json, .env*) and (b) two explicit conservative additions made by this spec — `programs/**` (Solana on-chain code) and `**/secrets/**` (any nested directory literally named `secrets`). The conservative additions are labeled in §4.2 of the spec so the AGENTS.md union isn't mis-cited.
- MAJOR is a real logic bug, broken test, regression, leak, or violation of an `AGENTS.md` hard rule.
- MINOR is doc accuracy, comment drift, prose nit, portability quirk, test thoroughness improvement with no current false-negative.
- COSMETIC is formatting, indentation, spelling, naming preference.

### Decision 2 — Deterministic-rules-first classifier with LLM fallback

The classifier (`bin/walter-os pr-classify-finding`) evaluates in this order:

1. Path-based BLOCKER triggers
2. Keyword-based MAJOR triggers
3. Path/keyword-based COSMETIC bias for doc-only findings
4. Path-based MINOR bias for substantive doc feedback
5. Test-file MINOR bias for thoroughness improvements
6. UNCLASSIFIED → LLM fallback (LiteLLM virtual key `pr-review-severity`, hard cost cap $0.01 per call, fail-safe to MAJOR above cap)

All LLM decisions are logged with the prompt + response to `~/.config/walter-os/state/auto-merge-log.jsonl` for audit.

### Decision 3 — Per-repo opt-in via `auto-merge-enabled` marker file

Auto-merge is disabled by default. A repo opts in by committing an `auto-merge-enabled` file at its root. Empty file = accept all defaults. The file may declare per-repo overrides for: round threshold, LOC caps, additional BLOCKER paths, additional MAJOR keywords, follow-up-issue label/title, audit-log path.

Repos without the marker file → auto-merge gate refuses (returns `MERGE_BLOCKED:no-opt-in` — same `MERGE_BLOCKED:<reason-slug>` notation as spec AC7 / Decision 4), falling back to the current manual-merge behavior.

### Decision 4 — Nine-condition gate (all must hold)

`walter-os pr-auto-merge <pr-num>` checks:

| # | Condition |
|---|---|
| C1 | `auto-merge-enabled` marker present at repo root |
| C2 | ≥ N completed review rounds (default 3, per-repo configurable) |
| C3 | Zero BLOCKER findings on latest HEAD |
| C4 | Zero MAJOR findings on latest HEAD |
| C5 | All CI checks success on latest HEAD |
| C6 | PR LOC change ≤ operator-configured cap (default 1500 additions, 500 deletions) |
| C7 | PR does not touch any auto-escalation path |
| C8 | Single follow-up issue auto-created with the deferred MINOR/COSMETIC list before merge |
| C9 | All review conversation threads resolved (auto-resolved by the gate when finding is MINOR/COSMETIC) |

Any condition failing → `MERGE_BLOCKED:<reason>` (one of the AC7 slugs), PR remains open, operator gets a comment with remediation guidance. Note: even for BLOCKER findings, the gate posts the diagnostic + a recommendation to close — but does NOT auto-close the PR. The Consequences section's "explicitly close the PR" wording describes the operator's typical response to a BLOCKER, not an automatic gate action.

### Decision 5 — Mandatory follow-up issue for every deferred finding

Auto-merge never silently drops findings. The gate creates a single follow-up issue per PR (not per finding) with verbatim text + file:line + suggested fix shape + severity label. The follow-up issue is labelled `auto-merge-deferred` + `copilot-review` for trackability.

## Why this approach

**Distinguishes by signal, not by ritual.** The current 3-round loop is a ritual — every finding triggers a fix or a defer regardless of impact. The severity gate routes by impact: BLOCKER stops everything, MAJOR blocks the merge until resolved, MINOR/COSMETIC become tracked tech debt that ships with the PR.

**Preserves the operator's bypass authority.** `--admin` flag invocation requires the operator's `bypass_pull_request_allowances` configuration. The gate doesn't grant new privileges; it automates what the operator could already do manually.

**Per-repo opt-in matches the operator's existing pattern.** Walter-OS already uses marker files for per-context configuration (`.walter-os/` in personal overlays, `WALTER_BRANCH_FLOW` env). A root-level marker file is the simplest, most discoverable form — visible to every PR reviewer, tracked in git, no hidden state.

**Deterministic rules + LLM fallback gives both auditability and coverage.** Hard-coded rules catch the obvious cases (path globs, keyword matches) with no model spend. The LLM picks up the long tail where text is ambiguous — but it's bounded by cost cap + fail-safe-to-MAJOR + audit log. We don't trust the LLM with security-sensitive decisions; we trust it with "is this finding more docs accuracy or test thoroughness".

**Symmetric with the existing AGENTS.md task-rigor model.** Tiny/small/major already exists. Severity classification extends that thinking to PR review findings. The two systems align — a major-rigor PR with major-severity findings = hardest gate, a small-rigor PR with cosmetic-severity findings = easiest gate.

## Alternatives considered and rejected

### A) Always auto-merge after N rounds (no severity)

Simplest implementation: after 3 rounds of Copilot review, regardless of finding content, auto-merge.

**Rejected** because:
- A 3-round-converged PR with one BLOCKER finding (operator accidentally committed a leaked key) would auto-merge that finding into main. Catastrophic for `auth/crypto/money/PHI` paths.
- Treats all findings as equivalent, which is the exact problem this whole spec exists to solve.
- Adds no signal for the operator — they go from "must click" to "no choice at all".

### B) Stay fully manual (status quo, no auto-merge)

Keep the existing `AGENTS.md` hard rule. Operator clicks merge for every PR.

**Rejected** because:
- The PR #111 evidence shows this produces multi-round loops on what is substantively safe work (docs drift).
- Operator time is the constrained resource. Mandatory clicks on every PR scale poorly.
- This is the do-nothing alternative — it's what we have today, and the operator is asking for an alternative.

### C) Per-PR label-based auto-merge (`auto-merge-eligible` label on the PR)

Each PR earns its auto-merge eligibility via an operator-applied GitHub label.

**Rejected** because:
- Reintroduces the manual click — operator applies the label per PR, which is the friction we're trying to remove.
- Label state can drift (added then forgotten when scope grows). The repo-marker file's location in the working tree makes the policy visible per commit.
- Per-repo marker is operator's once-per-repo intent declaration; per-PR label is a per-PR repeated action.

### D) Time-based auto-merge (auto-merge if PR is open for >N days with no failing checks)

Time is the gate, not severity. After 7 days of green CI + no new commits, auto-merge.

**Rejected** because:
- Conflates "time" with "safety". A leaked key sitting in a stale PR for 7 days is still a leaked key. The time gate alone doesn't catch it.
- Doesn't solve the actual operator pain — the pain was the 4-round loop on a single PR, not stale PRs.
- Could pair with severity gate as a separate mechanism (auto-close stale PRs), but conflating them muddies both.

### E) Single boolean classifier ("safe to merge" / "needs human")

Skip the four-tier taxonomy, just produce one bit.

**Rejected** because:
- Loses the follow-up-issue value. The four tiers carry information that the issue body uses to describe what was deferred and why.
- The taxonomy mirrors how operators actually think about review findings (your own chat discussion proposed exactly the four tiers). Compressing to one bit reduces fidelity for no implementation simplification (still need the same rule engine, just collapsing its output).

## Consequences

**Positive:**

- 3-round-converged docs-drift PRs (the #111 case) merge automatically with a single follow-up issue listing every deferred MINOR.
- Operator's review-merge time scales with the number of MAJOR-and-above findings, not with the number of total findings.
- Per-repo opt-in keeps the blast radius contained — adopters opt in on safe repos first.
- BLOCKER findings (the actual safety case) get more attention, not less: the gate posts a diagnostic comment + creates a high-priority follow-up issue, while explicitly NOT auto-closing the PR (closure remains an operator decision per Decision 4). They rise above the 4-round noise floor through the dedicated comment + issue, not by being silently dropped.
- Severity classification becomes a first-class concept — usable in dashboards, weekly digests, trend analysis.

**Negative:**

- Adds ~600 LOC of new code (classifier, gate, hook, marker parser) + 1 LLM virtual key + audit log file.
- The classifier is a new failure surface; misclassification produces wrong merges. Mitigated by triple gate + cost cap + audit log + per-repo opt-in.
- Repos that opt in inherit the responsibility to keep their `auto-merge-enabled` configuration current as their structure changes. Forgetting to update the BLOCKER paths after adding a new sensitive directory = silent risk.
- The "Never auto-merge" hard rule in `AGENTS.md` needs amendment. Some adopters who relied on its absoluteness may dislike the relaxation.

**Reversible:**

- Yes. Removing the `auto-merge-enabled` marker file from a repo immediately reverts that repo to manual-merge behavior. Deleting the `hooks/pr-auto-merge-gate.sh` hook + the new walter-os subcommands reverts globally. The audit log + follow-up issues remain as historical artifacts.

## Migration

1. Implementation lands as a separate PR (the spec/plan/ADR PR doesn't add the runtime). PR is reviewed under the OLD `AGENTS.md` "Never auto-merge" rule (cannot eat its own dogfood on first land).
2. After merge, the walter-os repo itself commits an `auto-merge-enabled` file with the operator's chosen thresholds. This is the operator's deliberate opt-in.
3. From that point, walter-os internal PRs that satisfy the gate auto-merge. Other repos adopt by copying the marker file.
4. Weekly digest (out-of-scope follow-up F1) provides visibility into the gate's hit rate.

## Open questions (non-blocking)

- **Q1**: should COSMETIC findings skip the round threshold entirely? **Currently locked: NO** — Decision 4 makes C2 (≥ N rounds) an unconditional gate requirement, and §4.1 of the spec aligns COSMETIC with MINOR on the round threshold. The question is preserved as a future lever the operator may choose to unlock — doing so would require explicitly relaxing C2's "unconditional" semantics here and amending §4.1 of the spec.
- **Q2**: how do we handle a PR where the operator wants to defer something the classifier called MAJOR? Proposed: operator manually merges (existing path), OR adjusts the keyword list in `auto-merge-enabled` so the future PR's classifier won't flag the same pattern as MAJOR. We don't allow per-PR severity override — keeps the gate auditable.
- **Q3**: should we gate auto-merge on time-since-last-Copilot-review (e.g. wait 1 hour after the last review to ensure no follow-up findings)? Proposed: no — adds latency without safety value; the round-count check already implies the reviews are stable. Time-based gates can be a follow-up if proven necessary.

## References

- Closed PR #103, merged PR #111 — the case study that produced the proposal
- Follow-up issue #112 — scaffolds this work
- AGENTS.md "Things agents must NEVER do" → "Auto-merge a PR" (will be amended)
- AGENTS.md "Review loop (standard pattern)" — the review loop this gate sits on top of
- ADR 0009 (agent trust tiers) — same pattern: per-agent configuration with override semantics
- ADR 0013 (solo-operator merge policy) — precedent for operator-configurable framework knobs
- ADR 0014 (CLI symlink path) — same review-loop case study
- Operator chat discussion 2026-05-21 (proposed severity gate + per-repo `auto-merge-enabled` marker file)
