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

For Round 2 cross-review (mandatory when PR exceeds Copilot's 20k-line cap, or
when touching multi-service deployment paths), first inspect the operator's
declared AI capability routes and effective model routing:

```bash
walter ai status
walter-os status --models
```

If `provider_codex` is available or the `code_review` /
`infra_security_backend` route resolves to Codex, run:

```bash
CODEX_MINIMAL_HOME="$(mktemp -d "${TMPDIR:-/tmp}/codex-minimal.XXXXXX")"
chmod 700 "$CODEX_MINIMAL_HOME"
trap 'rm -rf "$CODEX_MINIMAL_HOME"' EXIT
printf 'approval_policy = "never"\nmodel = "gpt-5.5"\n' \
  > "$CODEX_MINIMAL_HOME/config.toml"
cp ~/.codex/auth.json "$CODEX_MINIMAL_HOME/auth.json"
chmod 600 "$CODEX_MINIMAL_HOME/config.toml" "$CODEX_MINIMAL_HOME/auth.json"
CODEX_REVIEW_OUTPUT="$CODEX_MINIMAL_HOME/review.txt"
: > "$CODEX_REVIEW_OUTPUT"
chmod 600 "$CODEX_REVIEW_OUTPUT"
CODEX_HOME="$CODEX_MINIMAL_HOME" codex review --base <target-branch> \
  > "$CODEX_REVIEW_OUTPUT" 2>&1
```

- If Codex is unavailable, use the first declared reviewer route instead.
- If no second reviewer is declared, document the gap and escalate before merge.
- [ ] Copilot review requested (REST API above)
- [ ] Round 2 cross-review completed or explicitly escalated

## Checklist

- [ ] Branch targets the correct base (default `main` per single-tier flow; `dev` if `WALTER_BRANCH_FLOW=three-stage`)
- [ ] Conventional commit subject ≤72 chars, imperative mood
- [ ] Spec updated if acceptance criteria changed during implementation
- [ ] `Refs: docs/specs/<slug>.md` in commit footer (for major tasks)

## Contributor License Agreement

By opening this PR you agree to sign the [Contributor License Agreement](../blob/main/CLA.md)
once the CLA gate is active (see ADR-0019). The CLA Assistant bot will guide
you on your first PR — comment `I have read the CLA Document and I hereby sign
the CLA` on the PR. The signature persists for all future PRs from your
GitHub account.

Until the operator activates the CLA gate (per ADR-0019 migration step 1),
the bot is gated by the `WALTER_CLA_ACTIVE` repo variable and will not block
PRs.
