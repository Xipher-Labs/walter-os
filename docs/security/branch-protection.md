# Branch protection — GitHub configuration checklist

This is what the operator (or any Walter-OS adopter) configures on GitHub
to make the branch flow `feature/* → dev → staging → main` actually
enforced server-side. The local hooks under `hooks/` catch most of
this on the operator's machine; branch protection is the server-side
backstop so a clone-and-push from another machine cannot route around
the local rules.

These settings live in GitHub, not in this repository — they are
configured per-repo via the Settings UI or via `gh api`. This document
is the canonical list of what to set.

## Current Walter-OS `main` state

Read-only GitHub API verification on 2026-06-09 shows the repository has
the CodeReviewID-relevant protection enabled:

- Required pull request reviews are enabled with 1 approving review.
- Stale approvals are dismissed when new commits are pushed.
- Administrators are included in protection enforcement.
- Force pushes and branch deletion are blocked.
- Linear history is required.
- The maintainer account is listed in bypass allowances for solo-maintainer
  recovery.

The remaining OpenSSF Scorecard `CodeReviewID` alert is therefore not a
missing branch-protection setting. The latest Scorecard evidence reports
`Found 0/30 approved changesets`, which is a history signal: future merged
PRs need approving reviews from another human account before Scorecard can
observe approved changesets. See
[`../operational/scorecard-hygiene.md`](../operational/scorecard-hygiene.md).

Current required status-check contexts on `main`:

- `Validate PR title format`
- `gitleaks secret scan`
- `semgrep custom rules`
- `shellcheck`
- `frontmatter lint`
- `cross-reference lint (policy drift)`
- `install.sh --dry-run`
- `bats hooks tests`
- `codeql analysis (javascript-typescript)`
- `osv-scanner dependency scan / osv-scan`

The OSV context includes `/ osv-scan` because the OSV workflow delegates to
Google's reusable workflow; GitHub branch protection stores the emitted
status-check context, not only the local YAML job name.

Signed commits remain recommended hardening for `main`, but they were not
part of the Scorecard `CodeReviewID` remediation: `required_signatures.enabled`
was `false` in the same 2026-06-09 read-only check.

## Per-branch rules

Apply identical settings to `main` and `staging`. Apply a softer profile
to `dev` (no required reviewer, but still require status checks).

### Required for `main` (production)

- [ ] Require a pull request before merging — **1 reviewer minimum**, no
      direct pushes. `Restrict pushes that create matching branches` and
      `Require approvals` both on.
- [ ] Dismiss stale pull request approvals when new commits are pushed.
- [ ] Require status checks to pass before merging. **Mark each of the
      following as required** (names must match GitHub status-check contexts
      exactly — copy from the branch-protection UI or protection API):
  - `bats hooks tests`
  - `shellcheck`
  - `frontmatter lint`
  - `gitleaks secret scan`
  - `Validate PR title format`
  - `semgrep custom rules`
  - `cross-reference lint (policy drift)`
  - `install.sh --dry-run`
  - `codeql analysis (javascript-typescript)`
  - `osv-scanner dependency scan / osv-scan`
- [ ] Require branches to be up to date before merging.
- [ ] **Require signed commits.** This is the high-trust signal — every
      merged commit on `main` must be verifiably signed by a known
      identity (GPG or SSH). See [signing-commits.md](signing-commits.md).
- [ ] Require linear history. No merge commits. The PR merge method on
      the repo settings should be "Squash" or "Rebase" only — disable
      "Merge commit".
- [ ] Include administrators (do not exempt yourself from your own rules).
- [ ] Restrict who can push to matching branches — only admins +
      maintainers. The branch protection's "Restrict pushes" list is the
      enforcement point; the `branch-flow-guard.sh` hook is the local
      reminder.
- [ ] Block force pushes.
- [ ] Block deletions.

### Required for `staging`

Same as `main` minus the second-reviewer requirement. Staging is the
pre-prod canary; 1 reviewer plus all status checks plus signed commits.

### Recommended for `dev`

- [ ] Require status checks (the same list, minus the heavyweight ones
      that run only on `main` like Scorecard).
- [ ] No required reviewer — `dev` is the integration branch and the
      operator self-merges feature work here after the local review
      loop converges.
- [ ] Still block force pushes and deletions.

## Conventional commit format

Walter-OS commits follow conventional commits:

```text
feat(<scope>): subject line ≤ 72 chars in imperative mood

Body explains the WHY, not the what. The diff shows what.

Refs: docs/specs/<slug>.md
Closes <PROJ>-<NNN>
```

Valid prefixes: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`,
`perf`, `security`. The commit-msg hook (planned, not yet wired) will
enforce the prefix; until then, this is a discipline rule for the
operator and a checklist item in PR review.

## Configuring via the GitHub API

The full Settings UI is the easiest way to set these once. To set the
critical rules programmatically (useful for new forks / new adopters):

```bash
# Replace OWNER/REPO. Requires gh CLI with admin scope on the repo.
OWNER_REPO=xipher-labs/walter-os
BRANCH=main

gh api -X PUT "repos/$OWNER_REPO/branches/$BRANCH/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "bats hooks tests",
      "shellcheck",
      "frontmatter lint",
      "gitleaks secret scan",
      "osv-scanner dependency scan / osv-scan",
      "Validate PR title format",
      "semgrep custom rules",
      "cross-reference lint (policy drift)",
      "install.sh --dry-run",
      "codeql analysis (javascript-typescript)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "required_signatures": true
}
EOF
```

`required_signatures: true` is the JSON equivalent of the "Require signed
commits" checkbox. It is enforced server-side: GitHub will reject a push
of any commit whose signature does not verify against a known GPG / SSH
key on the pusher's account.

The `restrictions` field can be set to limit pushes to specific users
or teams; `null` means "anyone with write access can push" (typical for
single-maintainer repos). For a multi-maintainer setup, narrow it.

## Verification

After applying the settings:

- [ ] Open a test PR from a feature branch to `main` without all required
      checks — confirm the merge button stays disabled.
- [ ] Try to push directly to `main` from a developer account — confirm
      it is rejected with `protected branch hook declined`.
- [ ] Push an unsigned commit to a PR targeting `main` — confirm the
      check fails with "commits must have verified signatures".
- [ ] Try to force-push to `main` — confirm it is rejected.

If any of these succeed, the corresponding setting was not applied;
re-check the UI.

## Related

- [signing-commits.md](signing-commits.md) — how to set up an SSH or
  GPG signing key on your machine and add it to GitHub.
- `hooks/branch-flow-guard.sh` — the local hook that mirrors the
  branch-flow rule before the operator hits push.
