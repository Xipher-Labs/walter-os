# Release Operations Automation

## Problem

Walter-OS releases currently depend on a manual checklist spread across PR
bodies, changelog edits, version files, review comments, tags, and post-merge
evidence. That is workable for a solo maintainer, but it is easy to miss one
small step during a release batch or stacked-PR sequence.

## Goals

- Add a read-only `walter-os release doctor` command.
- Validate release readiness from local files and GitHub PR evidence.
- Catch changelog, version, tag, review-thread, check, issue-link, and stacked
  PR retargeting problems before the operator clicks merge or creates a tag.
- Produce concise human output plus JSON for later Control Tower or n8n use.

## Non-Goals

- Do not auto-merge PRs.
- Do not push tags or create GitHub releases.
- Do not update changelog/version files.
- Do not bypass branch protection, review gates, or approval-gate hard limits.

## Decisions

### D1 — Read-only release doctor

The first slice is diagnostic only:

```bash
walter-os release doctor --target v0.6.1
```

It may call `gh` and `git` to read evidence, but it never mutates repository or
GitHub state. Fixture mode is available for tests:

```bash
walter-os release doctor --target v0.6.1 --fixture evidence.json
```

### D2 — Three decisions

| Decision | Exit | Meaning |
|---|---:|---|
| `ready` | 0 | No blocking findings or warnings were found. |
| `warn` | 0 | Release can proceed manually, but attention is needed. |
| `block` | 1 | A hard release-readiness gate failed. |

Malformed usage exits `64`; runtime/dependency failures exit `4`.

### D3 — Hard blockers vs warnings

Hard blockers include version drift, missing changelog entry, tag already
existing for the target version, failed or pending checks, pending review
requests, unresolved review threads, merge conflicts, and issue-closing hygiene
problems.

Warnings include stacked PRs that are otherwise healthy but require ordered
merge/retargeting after their base PR lands.

### D4 — Issue closure hygiene

PR bodies should use `Closes #...` only when the PR fully resolves the issue.
Partial slices should use `Refs #...`. The doctor cannot infer semantic
completion, but it can flag structurally risky cases:

- a PR with closing issue references but no verification evidence;
- a stacked PR whose base is not the release base and therefore will not close
  issues until retargeted.

## Acceptance Criteria

- AC1: `walter-os help` documents `release doctor`.
- AC2: clean evidence returns `ready` with exit 0.
- AC3: version, changelog, or tag drift returns `block`.
- AC4: failed/pending checks, pending review requests, unresolved review
  threads, or conflicts return `block`.
- AC5: stacked PRs return `warn` and include merge-order/retarget guidance.
- AC6: issue-closing hygiene problems return `block`.
- AC7: `--json` emits `decision`, `counts`, `findings`, `warnings`, and
  `target`.

## Related

- Issue: #307
- Umbrella: #266
- Prior primitives: `docs/specs/pr-score.md`,
  `docs/specs/post-merge-feedback-loop.md`
