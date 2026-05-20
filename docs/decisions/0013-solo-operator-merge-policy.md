# 0013. Solo-operator merge policy — simplified branch flow

**Date**: 2026-05-20
**Status**: Accepted

## Context

The `AGENTS.md` "Branch flow (non-negotiable)" rule reads:

```
feature/<slug> → dev → staging → main
```

`hooks/branch-flow-guard.sh` enforces this at the Claude Code PreToolUse
layer by blocking `gh pr create --base main` from a `feature/*` branch
unless `--allow-branch-skip` is passed with a justification.

In practice the rule is theatrical for the current scale of the
project:

1. **`dev` and `staging` branches do not exist** on `origin`. Every
   feature PR for the last release cycle (#35, #45, #47) has targeted
   `main` directly using `--allow-branch-skip` plus a justification —
   the "hotfix" escape hatch is the default path.

2. **Walter-OS is operator-only today.** The bypass list in branch
   protection includes `f0x1777`. Any "required review" gate is
   bypassed for the solo operator on every merge anyway. Three-stage
   promotion does not provide value when nobody downstream is going to
   integration-test a `dev` branch against other in-flight PRs.

3. **Three new contributors have already submitted PRs** (`@MzzuMrz` via
   PR #36, the Copilot bot via PR #48, the codex bot via PR #32). They
   all opened against `main` because that is what the README, the
   CONTRIBUTING flow, and the GitHub UI all point at. Asking them to
   target a `dev` branch that does not exist is a documentation /
   reality mismatch.

The cost of keeping the documented rule is real:

- New contributors must guess the `--allow-branch-skip` workaround.
- The branch-flow-guard hook is the most-triggered hook in operator
  sessions; every PR creates a friction point.
- Documentation drift compounds: any change to AGENTS.md branch flow
  needs matching changes in `hooks/branch-flow-guard.sh`, in the
  `branch-flow-guard.bats` tests, and in every onboarding doc.

## Decision

**Drop the `dev`/`staging` branch tier requirement. Adopt a one-stage
feature flow: `feature/<slug>` → `main`.**

Direct push to `main` (and to `staging` / `production` / `master` if
those branches are ever created) stays blocked unconditionally — the
guard still enforces that.

The `--allow-branch-skip` flag is no longer the default escape hatch
and can be removed entirely. (If someone needs to hotfix a branch that
is not `main`, they create a feature branch and target the destination
explicitly.)

## Why not the alternatives

**Establish `dev` and `staging` for real.** This would require:
- Creating both branches with branch protection (1 approval, all
  required checks).
- A separate workflow that integration-tests `dev` against in-flight
  PRs nightly or on demand.
- A `dev → staging → main` promotion workflow (auto-PR on schedule,
  with semver tag handling).
- Onboarding doc updates that point new contributors at `dev`.

That is real engineering and ongoing maintenance for benefits the
project does not currently see at this scale. Revisit when:
- Two or more contributors are regularly merging the same week, OR
- A staging environment exists that needs a separate integration
  branch as its deploy source, OR
- The number of in-flight PRs at any one time exceeds five.

**Keep the rule as aspiration; flag every bypass.** That is the
current state and it is the worst of both — the rule reads as policy
but the hook fires constantly with bypass flags that nobody enforces.
Pick one direction.

## Consequences

### Required changes (this PR)

- `AGENTS.md` "Branch flow" section: rewrite to describe
  `feature/<slug>` → `main` as the canonical flow. Remove `dev` and
  `staging` references. Keep the direct-push-to-`main` block.
- `hooks/branch-flow-guard.sh`: remove the `feature/* → dev`,
  `dev → staging`, and `staging → main` cases. Keep the direct-push
  block and the optional `WALTER_MANUAL_PR_REMOTE_PATTERN`
  enforcement. Remove the `--allow-branch-skip` handling.
- `tests/hooks/branch-flow-guard.bats` (if present): update tests to
  match the new behavior. Drop the `dev`-base tests; keep the
  direct-push-block tests.

### Knock-on effects elsewhere

- Open PRs that used `--allow-branch-skip` in their command lines no
  longer need it — the next session can drop the flag without
  blockage.
- Recent PRs (#35, #45, #47) that referenced this ADR in their
  branch-skip justification can have that justification removed in
  follow-up CHANGELOG / spec hygiene.

### Future re-evaluation

When the project crosses any of the scale triggers in "Why not the
alternatives", revisit this ADR. The expected next form is `feature/*
→ release/x.y` (release-branch model), not the original three-tier
flow.

## References

- Issue #43 — branch flow rule vs reality
- `AGENTS.md` "Branch flow (non-negotiable)" section
- `hooks/branch-flow-guard.sh`
- PRs #35, #45, #47 (recent examples of `--allow-branch-skip` as the
  default)
