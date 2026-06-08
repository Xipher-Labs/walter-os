---
description: Prepare and (in personal/* context) open a PR after the implementer is done. In work/* ([Company]), prepares everything but stops short of opening the PR.
argument-hint: <spec-slug>
---

Pre-flight checks (all must pass):

1. Branch flow: current branch must be `feature/$ARGUMENTS` (or
   `fix/$ARGUMENTS` / `chore/$ARGUMENTS`). Target branch follows
   `WALTER_BRANCH_FLOW`: default (`single-tier`) → `main`;
   `three-stage` → `dev`. See ADR 0013. The
   `branch-flow-guard.sh` hook blocks direct pushes to protected
   branches in both modes.
2. Tests: full suite passes locally.
3. Lint, typecheck, format: clean.
4. `definition-of-done-validator` skill: every AC in
   `docs/specs/$ARGUMENTS.md` has ≥1 passing test.
5. `pr-review` skill: reviewer subagent has approved (no blocking
   findings).
6. Security: if diff touches auth/crypto/money/medical/network, the
   `security-auditor` subagent has approved.
7. `daily-supply-chain-audit` was clean today.
8. No secrets in the diff (`grep` for typical key prefixes).

Generate PR description from this template:

```markdown
## Summary

<1–2 sentence pitch from the spec>

## Spec

`docs/specs/$ARGUMENTS.md`

## Acceptance Criteria

- [x] AC-1: <copied from spec, with test reference>
- [x] AC-2: <...>

## Test evidence

<screenshot/gif/recording link or short test output>

## Risk

<what could break? what's the rollback?>

## Checklist

- [x] Tests pass
- [x] Lint clean
- [x] DoD validator passed
- [x] Reviewer approved
- [x] Security auditor approved (if applicable)
- [x] No secrets in diff
- [x] Branch flow respected (feature → main; ADR 0013)

Closes <ticket-id>
Refs: docs/specs/$ARGUMENTS.md
```

Then:

**Personal context (`Projects-Personal/*`):**
- Push the branch: `git push -u origin feature/$ARGUMENTS`
- Open the PR via `gh pr create` with the body above
- Request Copilot review
- Report back with PR URL

**Work context (`work/*` / [Company]):**
- Push the branch: `git push -u origin feature/$ARGUMENTS`
- Print the `gh pr create` command with the prepared body, BUT DO NOT RUN
  IT. [Company] policy: humans open every PR.
- Print the URL the operator will get after they run the command.
## Multi-Model Review Routing

Use the operator's model-routing preferences before requesting non-Copilot
review rounds:

```bash
source "$WALTER_OS_HOME/scripts/walter/lib/model-router.sh"
review_model=""
walter_model_resolve backend_review review_model
```

Default routing prefers Codex for backend/security/infrastructure review and
Claude for frontend/UX/design work. Operators can override those aliases in
`~/.config/walter-os/overlay/personal.env`; PHI/medical work must stay on the
`phi` route and cannot be overridden to an external model.
