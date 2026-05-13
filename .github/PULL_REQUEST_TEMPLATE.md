<!-- TITLE FORMAT: [TYPE] -CATEGORY- title -->
<!-- TYPE: FEAT / FIX / DOCS / CHORE / TEST -->
<!-- CATEGORY: SECURITY / BUSINESS / COMPLIANCE / OPERATIONS / TECHNICAL / CUSTOMER / CONTENT / LEARNING -->
<!-- Example: [FEAT] -BUSINESS- pricing experiment skill -->
<!-- See CONTRIBUTING.md -> "Title convention" for details -->

## Spec

**Spec**: `docs/specs/<slug>.md`
<!-- Link to the spec this PR implements. For tiny/small changes, describe
     the change inline in 2-3 sentences instead. -->

## Problem summary

<!-- 1-2 sentences: what was wrong or missing before this PR? -->

## Changes

<!-- Brief description of what changed. The diff shows what; explain why. -->

## Test plan

- [ ] All bats tests pass (`bats tests/`)
- [ ] Acceptance criteria in the spec have corresponding test assertions
- [ ] `shellcheck` clean on any new shell scripts
- [ ] `markdownlint` clean on any new Markdown files (if `markdownlint-cli` installed)
- [ ] If adding contact emails: ensure no `TODO(pre-launch)` HTML comments remain
      (`grep -rn "TODO(pre-launch)" . --include="*.md"` should return 0 non-test matches)
- [ ] Build clean (`cd apps/control-tower && pnpm build`) if Control Tower touched

## Copilot review

After opening this PR, request Copilot review via:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<NUM>/requested_reviewers \
  --input - <<<'{"reviewers":["copilot-pull-request-reviewer[bot]"]}'
```

For Codex review (mandatory when PR exceeds Copilot's 20k-line cap, or when
touching multi-service deployment paths):

```bash
codex review --base main > /tmp/codex-review.txt 2>&1
```

- [ ] Copilot review requested (REST API above)

## Checklist

- [ ] Branch targets `dev` (not `main`)
- [ ] Conventional commit subject ≤72 chars, imperative mood
- [ ] Spec updated if acceptance criteria changed during implementation
- [ ] `Refs: docs/specs/<slug>.md` in commit footer (for major tasks)
