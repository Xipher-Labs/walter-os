# OpenSSF Scorecard Hygiene Follow-up

Issue #396 tracks the current open Scorecard code-scanning alerts. This
runbook separates fixes that are visible in the repository from settings
that must be changed in GitHub by an operator.

## Current alert disposition

| Alert | Rule | Repository-visible action | Remaining action |
|---|---|---|---|
| #45 | `CodeReviewID` | `AGENTS.md` and `docs/security/branch-protection.md` document the PR review policy and required branch protection. On 2026-06-07, `main` was updated to require one approval while preserving the solo-maintainer bypass. | Scorecard still reports `Found 0/30 approved changesets`. Clearing the alert requires future merged PRs with approving reviews, or an explicit solo-operator exception until a second human reviewer exists. |
| #46 | `MaintainedID` | This repository has active commits, CI, release docs, and an open maintenance process. | Scorecard still reports `Repository was created within the last 90 days`. No repo setting can clear this early-age signal; re-check after the 90-day window and the next Scorecard refresh. |
| #47 | `SecurityPolicyID` | Root `SECURITY.md` exists and `.github/SECURITY.md` duplicates it for GitHub/Scorecard discoverability. | None expected after merge; wait for the next Scorecard run. |
| #48 | `CIIBestPracticesID` | `docs/security/openssf-silver-checklist.md`, `docs/specs/openssf-badges.md`, and `docs/operational/openssf-badge-filing-runbook.md` record the OpenSSF Best Practices badge path. | Manual process: file the OpenSSF Passing badge at bestpractices.dev, record the approved project URL here as evidence, then add the approved badge URL to `README.md`. |
| #50 | `FuzzingID` | Control Tower now includes a bounded `fast-check` property-based fuzz target for prompt-sanitization boundaries. | Re-run Scorecard after merge. If the alert remains open, keep the fuzz target for coverage but treat Scorecard detection as requiring a stronger integration such as OSS-Fuzz or CIFuzz. |

## Safe read-only checks

These commands inspect settings without changing them:

```bash
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api "repos/${repo}/branches/main/protection"
gh api "repos/${repo}/community/profile"
gh api "repos/${repo}/code-scanning/alerts" -f state=open
```

If the branch-protection command returns `404` to a maintainer token, either
branch protection is not configured or the token lacks repository
administration read permission. Do not infer protection from local hooks; the
GitHub setting is the server-side control Scorecard can observe.

Observed on 2026-06-07 from the read-only branch-protection endpoint after
the review-protection setting update:

- `enforce_admins.enabled: true`
- `required_pull_request_reviews.dismiss_stale_reviews: true`
- `required_pull_request_reviews.required_approving_review_count: 1`
- `required_pull_request_reviews.bypass_pull_request_allowances.users:`
  contains the maintainer account
- `required_linear_history.enabled: true`
- `allow_force_pushes.enabled: false`
- `allow_deletions.enabled: false`
- `required_status_checks.strict: false`

## Manual GitHub setting for CodeReviewID

For `main`, configure branch protection or a repository ruleset with:

- Require a pull request before merging.
- Require at least one approving review.
- Dismiss stale pull request approvals when new commits are pushed.
- Include administrators.
- Block force pushes and branch deletion.
- Require the status checks listed in `docs/security/branch-protection.md`.

Do not make this change from automation unless the operator explicitly asks
for that single GitHub settings update.

## Fuzzing follow-up candidates

Fuzzing is most useful when the project has a stable, input-heavy library
boundary. Candidate targets:

- `bin/walter-os` repo-config parsing and schema validation.
- `hooks/wiki-validator.sh` frontmatter handling.
- Workflow normalization helpers used by `tests/install/workflow-lint.bats`.

The first maintained target is the Control Tower prompt-sanitization boundary:

```bash
pnpm --dir apps/control-tower exec vitest run tests/unit/sanitize.fuzz.test.ts
WALTER_FUZZ_RUNS=1000 pnpm --dir apps/control-tower exec vitest run tests/unit/sanitize.fuzz.test.ts
```

The default CI budget is intentionally small (`WALTER_FUZZ_RUNS=100` by
default) because it runs as part of the existing Control Tower unit-test job.
Use a higher local budget before changing `apps/control-tower/lib/sanitize.ts`.
