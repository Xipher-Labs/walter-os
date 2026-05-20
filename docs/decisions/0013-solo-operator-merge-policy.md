# 0013. Branch flow — operator-configurable, single-tier default

**Date**: 2026-05-20
**Status**: Accepted
**Supersedes the de-facto rule documented (but not implemented) before this ADR.**

## Context

The pre-existing `AGENTS.md` "Branch flow (non-negotiable)" rule read:

```
feature/<slug> → dev → staging → main
```

`hooks/branch-flow-guard.sh` enforced this at the Claude Code
PreToolUse layer by blocking `gh pr create --base main` from a
`feature/*` branch unless `--allow-branch-skip` was passed with a
justification.

In practice the rule did not match the project's reality:

1. **`dev` and `staging` branches do not exist** on `origin`. Every
   feature PR for the last release cycle (#35, #45, #47) used
   `--allow-branch-skip` to target `main` directly — the "hotfix"
   escape hatch was the default path.

2. **Walter-OS adopters span a wide range.** The framework is built
   to be forked. A solo operator does not need three integration
   tiers; a small team with a real staging environment genuinely
   does. Hard-coding either choice into the framework forces every
   adopter to either accept friction they do not need (solo) or
   bypass a hook the framework ships with (team).

3. **Three external contributors** opened PRs against `main` in two
   weeks (#32 codex bot, #36 `@MzzuMrz`, #48 Copilot bot). They all
   targeted `main` because that is what the README, the CONTRIBUTING
   flow, and the GitHub UI all point at. Sending them to a `dev`
   branch that does not exist would be a documentation / reality
   mismatch.

## Decision

**The branch flow is now an operator-configurable choice, with
single-tier as the default.**

Two modes are supported by `hooks/branch-flow-guard.sh`:

- **`single-tier`** (default) — `feature/<slug>` → `main`. PRs target
  `main` directly. Best for solo operators and small teams without a
  separate staging environment. This is what the framework defaults
  to when the operator has not set anything.

- **`three-stage`** — `feature/<slug>` → `dev` → `staging` → `main`.
  The hook enforces the next-level rule (feature → dev → staging →
  main); skipping requires `--allow-branch-skip` plus a
  justification in the PR body. Best for teams with a real `dev`
  integration branch and a `staging` environment whose deploy is
  gated on a separate branch.

Operators select the mode by exporting `WALTER_BRANCH_FLOW` in their
overlay (`~/.config/walter-os/overlay/personal.env`):

```bash
# Default — equivalent to not setting the variable at all
export WALTER_BRANCH_FLOW=single-tier

# Opt in to the original three-stage flow
export WALTER_BRANCH_FLOW=three-stage
```

What stays the same regardless of mode:

- Direct push to `main` / `master` / `staging` / `production` is
  blocked unconditionally. There is no bypass for that.
- The optional `WALTER_MANUAL_PR_REMOTE_PATTERN` gate (forces manual
  PR creation on matching remotes) still applies.

## Why this shape, not the alternatives

**Why not retire the three-stage flow entirely?**
The original ADR draft did this and removed the option. That is
wrong for a framework: it locks adopters who genuinely want the
three-stage flow into either patching the hook locally or running
without it. The framework should give the choice and document the
trade-off, not pick for everyone.

**Why not auto-detect from branch existence?**
"If `origin/dev` exists, enforce three-stage" is elegant but fragile.
A `dev` branch created by accident — or one that lingers from a
deleted feature/* — would silently flip the policy. Explicit config
is harder to surface but easier to reason about when the hook fires.

**Why not multiple flavours (e.g. release-branch model, gitflow)?**
Two modes covers the common cases without bloating the hook. Adding
a `release-branch` mode would require the hook to know about release
naming (`release/*`) and tagging behaviour, which is too much for
this layer. If a forker needs a different flow they can extend the
hook locally — the contract is small enough to do that without
re-engineering the rest of walter-os.

## Consequences

### Behavior change for current adopters

- **The solo operator (default)** — `--allow-branch-skip` is no
  longer required. Existing PRs that include the flag continue to
  work; the flag is now a no-op in `single-tier` mode.
- **Team operators on `three-stage`** — must set
  `WALTER_BRANCH_FLOW=three-stage` in their overlay. The hook
  behaviour matches the pre-ADR rule once the variable is set.

### Implementation slice in this PR

- `hooks/branch-flow-guard.sh` — reads `WALTER_BRANCH_FLOW`,
  defaults to `single-tier`. In `three-stage` mode, enforces the
  original `feature → dev → staging → main` gate with
  `--allow-branch-skip` bypass.
- `tests/hooks/branch-flow-guard.bats` — covers both modes plus the
  default-when-unset behaviour.
- `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, the contexts/, the
  commands/, the skills/, and `agents/implementer.md` — describe
  the default flow but cross-reference this ADR for the
  configurable alternative.

### Future re-evaluation

Revisit if a third common pattern emerges (release-branch model,
trunk-based with feature flags, etc.). The next likely extension is
adding `release/x.y` as a target in `single-tier` mode for projects
that cut tag branches.

## References

- Issue #43 — branch flow rule vs reality
- `AGENTS.md` "Branch flow" section
- `hooks/branch-flow-guard.sh`
- PRs #35, #45, #47 (recent examples that ran into the rule)
- Issue #50 — pre-existing `tests/oss/` failures (not directly
  related; surfaced during the implementation of this ADR)
