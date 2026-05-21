---
name: track-pending
description: Capture deferred work without leaving it as a TODO comment or an out-of-band note. Use this skill whenever you finish a change and notice something out of scope — a stale README, a missing test, a flaky CI assertion, a follow-up refactor — that you should not fix in the current PR but must not lose. Writes structured entries to `walter-pending.md` at the repo root. Triggers on phrases like "track this", "defer this", "out of scope", "follow-up", "for a later PR", "tech debt", "track-pending".
---

# Track Pending

A bounded ledger for "I'll come back to that". Lives at
`walter-pending.md` at the repo root, version-controlled like any
other doc.

## Why a separate ledger and not GitHub issues

GitHub issues are the right home for things the world should see —
bugs, feature requests, large design decisions. They are the wrong
home for the dozens of small follow-ups a working session generates:
"this comment is stale", "this test asserts the wrong thing", "this
import is unused", "we should rename `foo` once the migration lands".

Three concrete failures of the issue-tracker-as-debt-ledger model:

1. **Search vs. issue tracker mismatch.** When you are editing
   `auth/session.ts` and want to know what is deferred for that file,
   `grep walter-pending.md auth/session.ts` is one keystroke. The
   issue tracker requires you to remember a label, a milestone, a
   query.
2. **Velocity of small wins.** A weekly sweep of 8 ten-minute
   follow-ups ships in one afternoon. The same 8 items as issues add
   ~5 minutes each of triage, labeling, and PR-linking overhead.
3. **Visibility for the operator alone.** Most deferred work is
   between you and your future self. Open issues with no audience
   make the project look noisier than it is.

`walter-pending.md` complements GitHub issues — it does not replace
them. Use issues for shared work; use this ledger for self-debt.

## File format

`walter-pending.md` is a flat markdown file with one entry per
deferred item. Each entry has a strict frontmatter-style preamble
followed by a free-form body.

```markdown
# Walter-OS pending

A bounded ledger of deferred follow-up work. Entries are sorted
newest-first. When an entry is resolved, remove it (do not leave a
"[DONE]" stub — the git history is the audit trail).

---

## TP-0042 — fix stale comment in auth/session.ts:140

- type: docs
- severity: low
- area: auth
- created: 2026-05-20
- defer-until: next-auth-refactor
- owner: operator

The comment block on line 140 still says "uses bcrypt"; we switched
to argon2 in PR #312. Quick edit but I want to do it alongside the
next auth pass so the explanatory comment also covers why argon2.

---

## TP-0041 — add bats coverage for `walter-os spend report --by-task`

- type: test
- severity: medium
- area: walter-os/cli
- created: 2026-05-18
- defer-until: v0.4.0
- owner: operator

`tests/walter/spend.bats` covers `--by-agent` but skips the
`--by-task` path. Acceptance: at least 2 test cases — empty result
and a record with at least 1 entry per task.

---
```

Fields:

| Field | Required? | Allowed values |
|---|---|---|
| `TP-<NNNN>` | yes | Monotonic. Run `grep -c '^## TP-' walter-pending.md` + 1 to get the next number. |
| `type` | yes | `feat` / `fix` / `docs` / `test` / `refactor` / `chore` / `security` / `perf` |
| `severity` | yes | `low` / `medium` / `high` / `block-ship` |
| `area` | yes | Free-form, but stay consistent (`auth`, `cli`, `compose/<service>`, `docs`, etc.) |
| `created` | yes | ISO-8601 date |
| `defer-until` | yes | Either an ISO date, a version tag (`v0.4.0`), an event (`next-auth-refactor`), or the literal `never` (entries marked `never` are aspirations that should probably be deleted rather than tracked) |
| `owner` | yes | The operator's handle, a contributor handle, or `unassigned` |
| Body | yes | One paragraph minimum. Explain WHY this is deferred, not just WHAT. The future-self reading this needs the context that made you defer it. |

## When to write a TP entry vs file an issue vs fix inline

| Situation | Action |
|---|---|
| Single-line typo, comment fix, dead import you notice during a PR — under 2 minutes | Fix inline. Do not create a TP entry for things that take less time to fix than to write down. |
| A small follow-up that the current PR shouldn't carry (scope drift) | TP entry. |
| A bug that affects users in production | GitHub issue. Add a `bug` label. Optionally cross-reference a TP entry that links back. |
| A design decision that needs operator input (e.g. "should we use option A or B") | Spec at `docs/specs/<slug>.md` + ADR if the decision is durable. |
| A security finding | TP entry if it is operator-facing and low severity. GitHub issue (or private disclosure per `SECURITY.md`) if it is high severity or exploitable. |
| Tech debt that affects multiple files / requires planning | TP entry first. Promote to a spec when you actually decide to tackle it. |

## When to write the entry

The default operator workflow is:

1. Working on a PR. Notice something out of scope.
2. **Before** opening the PR: add the TP entry as a separate commit
   with prefix `track:` (e.g., `track: TP-0042 stale comment in
   auth/session.ts`).
3. PR description includes a "Tracked follow-ups" bullet pointing at
   the TP IDs.

Writing the entry **before** opening the PR keeps the deferred work
in the same atomic unit as the work that surfaced it. Adding it
after the merge tends to lose context (you forget why you deferred).

## `walter-os pending` CLI helpers

This skill ships alongside CLI shortcuts (see `bin/walter-os
pending`) for the common operations:

```bash
# List all open entries (default sort: severity desc, created desc)
walter-os pending list

# Filter
walter-os pending list --severity high
walter-os pending list --owner self --overdue
walter-os pending list --area auth

# Add a new entry — opens the file in $EDITOR with frontmatter pre-filled
walter-os pending add --type fix --severity medium --area cli "rename --pin to --version"

# Mark resolved (deletes the entry)
walter-os pending resolve TP-0042

# Stats
walter-os pending stats
```

If the CLI subcommand is not yet installed (Phase 5 #2 `debt-report`
extends this skill into a richer tool — see the execution plan),
the file is still hand-editable as plain markdown.

## Anti-patterns

1. **`// TODO: ...` comments in code.** They rot. They never get
   removed even after the work is done. They make grep useless.
   Promote any code TODO to a TP entry and delete the comment.
2. **Long entries with no `defer-until`.** Every entry needs a
   trigger condition. "We should do this someday" is not a deferral,
   it is a wishlist. Either commit to a version/event or delete.
3. **TP entries that link to closed work without removal.** The git
   history is the audit trail. Resolved entries are deleted, not
   archived. If you find yourself wanting "an archive of resolved
   entries", you are confusing this with a changelog.
4. **Cross-cutting TPs that should be specs.** If an entry takes
   more than three lines to describe, it is not a tracking entry —
   it is a spec waiting to be written. Promote.

## Hard rules

- **`walter-pending.md` is tracked by git.** It is part of the repo,
  not gitignored. Other contributors should see the operator's
  deferred work.
- **Never put secrets in a TP entry.** Path references are fine;
  credentials, hostnames, internal URLs are not. The file is in the
  public repo (for OSS projects).
- **PR descriptions reference TP IDs by number, not by inlined
  body.** Keeps PR bodies small and lets the ledger evolve
  independently.
- **One TP per concern.** Do not pack three unrelated items into a
  single entry. Each line in the file should be greppable for one
  topic.

## Integration with other Walter-OS skills

- **`oss-readiness`** runs a sanity check that `walter-pending.md`
  exists at repo root and has no `block-ship` entries before an OSS
  release.
- **`pr-review`** flags any inline `// TODO` / `# TODO` /
  `<!-- TODO -->` introduced in the PR diff and prompts the operator
  to promote it to a TP entry.
- **`definition-of-done-validator`** does not gate on TP entries.
  TPs are explicitly out-of-scope of the current PR by design.
- **Phase 5 `debt-report` CLI** (issue #2) builds on this convention
  with richer querying and cross-repo aggregation. Same file format,
  bigger tool.

## Operator workflow (composed example)

```bash
# Mid-PR: notice the README is stale on the section you're editing
walter-os pending add \
  --type docs --severity low --area docs \
  --defer-until next-readme-pass \
  "README section X mentions Y but we removed Y in PR Z"

# Continue your PR work. Before opening the PR:
git log --oneline -5    # confirm the `track:` commit is in the branch
git add walter-pending.md
git commit -m "track: TP-NNNN README section X stale"

# PR description includes:
# > **Tracked follow-ups**: TP-NNNN (out-of-scope doc update).

# Later, when you pick up the next-readme-pass cycle:
walter-os pending list --defer-until next-readme-pass
walter-os pending resolve TP-NNNN
```

## References

- Walter-OS execution plan Phase 4 (founder-skills epic, #4).
- Issue #2 — `walter-os debt-report` CLI (Phase 5 follow-up that
  extends this skill).
- `skills/oss-readiness/SKILL.md` — the consumer that gates a release
  on no `block-ship` entries.
- `skills/pr-review/SKILL.md` — flags inline TODOs and promotes them.
