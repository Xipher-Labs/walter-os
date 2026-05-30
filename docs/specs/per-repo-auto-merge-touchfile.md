# Per-repo auto-merge authorization via `.walter-os/auto-merge-authorized`

**Status**: spec drafted; implementation pending.
**Owner**: TBD.
**Related ADR**: future ADR-NNNN to be opened on first implementation PR.

## Problem

The global AGENTS.md hardcodes:

> Never auto-merge a PR. The operator clicks merge.

This is the safe default — but for low-stakes operator-personal repos
(scratch projects, dotfiles, hackathon scaffolds, internal tooling
forks), the every-PR-needs-manual-merge step adds friction that the
operator explicitly wants to skip.

The README's Disciplines section now documents the convention:

> **Per-repo opt-in**: `touch .walter-os/auto-merge-authorized` in the
> repo root authorizes the agent to merge a PR once all gates pass
> (CI green + DoD validator clean + review loop converged). The
> touch-file is committed (so the policy travels with the repo) and is
> the only place where the otherwise-hardcoded "never auto-merge" rule
> yields. Removing the file restores manual-merge.

This spec turns that documented convention into actual enforcement.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Touchfile path is `.walter-os/auto-merge-authorized`** (repo root). | Single canonical path; `.walter-os/` directory matches the existing convention for per-repo Walter-OS metadata (`.walter-os-lite/`). |
| D-2 | **File is COMMITTED to the repo**, not in `.gitignore`. | The policy is repo-scope, not operator-scope. A clone of the repo to a different machine inherits the same policy. |
| D-3 | **File contents are advisory only** — agent reads presence/absence, not body. | Keeps the contract simple. Operators may write a comment in the file explaining why the policy is opt-in (will not be parsed). |
| D-4 | **All gates must still pass** — auto-merge only fires when CI is green AND DoD validator is clean AND review loop has converged (Copilot R1 + reviewer R2 + Codex R2 all returned no findings, OR remaining findings are P3 cosmetic). | The touchfile authorizes the agent to *click* merge; it does NOT lower the quality bar. |
| D-5 | **Enforced in two places**: (a) `bin/walter-os` adds a `walter-os auto-merge-check` subcommand that returns 0 if all preconditions are met; (b) the `walter-review-loop` composite Action checks the touchfile + calls `gh pr merge --auto --squash` when present. | Both the CLI and the CI loop need the same answer; centralize in one helper. |
| D-6 | **Branch-flow-guard hook is UNCHANGED**. | The hook blocks direct pushes to `main`/`master`/`staging`/`production`. Auto-merge goes through `gh pr merge`, not a direct push — the hook doesn't trip. |
| D-7 | **Override on a per-PR basis**: a PR body containing `walter-os: no-auto-merge` overrides D-1 for THAT PR even if the touchfile exists. | Lets the operator hold a specific PR for manual review without removing the repo-level policy. |
| D-8 | **Audit visibility**: every auto-merge by the agent posts a comment on the PR with the commit-SHA of the touchfile + the green-CI run URL. | Operator can scan the history of auto-merged PRs after the fact. |

## Acceptance criteria

### AC-1 — touchfile detection

- `walter-os auto-merge-check` exits 0 when `<repo-root>/.walter-os/auto-merge-authorized` exists.
- Exits 1 when the file is absent.
- Exits 1 when the file exists but is at any other path (e.g.
  `auto-merge-authorized` in the root, no `.walter-os/` directory).
- bats: `tests/cli/walter-os-auto-merge-check.bats`.

### AC-2 — gate composition

- `walter-os auto-merge-check` exits 0 only when ALL of:
  - Touchfile present (AC-1).
  - Current branch has an open PR.
  - PR's `mergeable` status is `MERGEABLE`.
  - PR's CI statusCheckRollup has zero `FAILURE` conclusions.
  - PR body does NOT contain `walter-os: no-auto-merge`.
- bats: same file.

### AC-3 — composite Action wiring

- `.github/actions/walter-review-loop/action.yml` adds a step:
  if `walter-os auto-merge-check` returns 0, run `gh pr merge --auto --squash`.
- bats: `tests/github-actions/walter-review-loop.bats` extended.

### AC-4 — audit comment

- On successful auto-merge, post a PR comment:
  ```
  🤖 Auto-merged by Walter-OS — per-repo policy
  Touchfile: `.walter-os/auto-merge-authorized` @ <commit-sha>
  CI run: <url>
  ```
- bats: same.

### AC-5 — documentation

- README `Disciplines` table row already mentions the convention
  (shipped with the v0.5.1 README rewrite — see the
  README.md Merge-policy row).
- `docs/operational/customization-patterns.md` adds a "Layer 5 — Merge
  policy" section explaining the touchfile.
- This spec links from `README.md` Updates section.

### AC-6 — refusal path

- When `walter-os auto-merge-check` exits 1, the composite Action does
  NOT call `gh pr merge`. The agent emits a comment on the PR:
  ```
  ⏸ Auto-merge not authorized for this repo.
  Touchfile absent: `.walter-os/auto-merge-authorized`.
  Operator: click Merge when ready, or `touch .walter-os/auto-merge-authorized && git add . && git commit && git push` to opt in.
  ```

## Threat model

| Attack | Mitigation |
|---|---|
| Attacker opens PR that creates the touchfile + merges itself in one PR | The touchfile must exist at HEAD of `main` BEFORE the auto-merge check runs. A PR that adds the file cannot self-auto-merge — the check still sees the pre-PR state. |
| Attacker modifies an existing touchfile to change behavior | The file contents are advisory only (D-3). Existence is the only signal. |
| Operator forgets they opted in to auto-merge on a stale repo | Audit trail (D-8) — every auto-merge posts a PR comment naming the touchfile commit-SHA. Operator can grep for `Auto-merged by Walter-OS` across PRs to surface the policy. |
| Hostile contributor adds touchfile via PR | The touchfile-adding PR itself follows the normal merge policy (operator clicks merge for that PR). After that PR merges, subsequent PRs become eligible. So the FIRST authorization is always manual. |

## Out of scope

- Squash vs rebase vs merge-commit choice — D-5 picks squash as the
  default; per-repo overrides are a future enhancement.
- Branch-protection-rule integration (GitHub's own auto-merge requires
  branch protection rules to be set up; this spec does not configure
  them).
- Auto-merging across multiple repos via a Walter-OS-wide global
  authorization. The touchfile is per-repo by design — that's the whole
  point.

## References

- README.md `Disciplines` table → Merge policy row
- `contexts/projects-personal/AGENTS.md:23` — current default
  "Auto-PR enabled after review iterations converge" (which still
  requires operator to click merge)
- `contexts/work/AGENTS.md:75` — current default "Never auto-merge a PR"
- ADR pending: TBD
