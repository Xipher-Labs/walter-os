# OpenSSF Scorecard Hygiene Follow-up

Issue #396 tracks the current open Scorecard code-scanning alerts. This
runbook separates fixes that are visible in the repository from settings
that must be changed in GitHub by an operator.

## Current alert disposition

| Alert | Rule | Repository-visible action | Remaining action |
|---|---|---|---|
| #45 | `CodeReviewID` | `AGENTS.md` and `docs/security/branch-protection.md` document the PR review policy and required branch protection. | Manual GitHub setting: require pull requests and at least one approving review on `main`; include administrators; dismiss stale approvals. Read-only check on 2026-06-07 showed `required_approving_review_count: 0`, so this is still unresolved in GitHub settings. |
| #46 | `MaintainedID` | This repository has active commits, CI, release docs, and an open maintenance process. | No repo setting. Scorecard should clear after fresh activity is visible on the default branch and the weekly Scorecard run refreshes. |
| #47 | `SecurityPolicyID` | Root `SECURITY.md` exists and `.github/SECURITY.md` duplicates it for GitHub/Scorecard discoverability. | None expected after merge; wait for the next Scorecard run. |
| #48 | `CIIBestPracticesID` | `docs/security/openssf-silver-checklist.md` and `docs/specs/openssf-badges.md` record the OpenSSF Best Practices badge path. | Manual process: file the OpenSSF Passing badge at bestpractices.dev, then add the approved badge URL to `README.md`. |
| #50 | `FuzzingID` | Fuzzing is deferred because Walter-OS currently has shell/config/documentation-heavy surfaces and no dedicated parser/codec target selected for fuzzing. | Create a follow-up issue when a durable target lands, preferably for repo-config parsing, wiki frontmatter validation, or workflow normalization. |

## Safe read-only checks

These commands inspect settings without changing them:

```bash
gh api repos/Xipher-Labs/walter-os/branches/main/protection
gh api repos/Xipher-Labs/walter-os/community/profile
gh api repos/Xipher-Labs/walter-os/code-scanning/alerts -f state=open
```

If the branch-protection command returns `404` to a maintainer token, either
branch protection is not configured or the token lacks repository
administration read permission. Do not infer protection from local hooks; the
GitHub setting is the server-side control Scorecard can observe.

Observed on 2026-06-07 from the read-only branch-protection endpoint:

- `enforce_admins.enabled: true`
- `required_pull_request_reviews.dismiss_stale_reviews: true`
- `required_pull_request_reviews.required_approving_review_count: 0`
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

Until one of those surfaces is factored into a reusable function or library,
property-style Bats coverage is the lower-risk test investment.
