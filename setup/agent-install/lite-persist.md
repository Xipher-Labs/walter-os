# Walter-OS Lite — persist disciplines across sessions

This file is the **optional companion** to `lite.md`. Where `lite.md`
installs disciplines into a single agent session (in-memory only), this file
writes a minimal `.walter-os-lite/AGENTS.md` into your current repository
directory so the disciplines persist across all future Claude Code or Codex
CLI sessions in that directory.

Lite-persist sits between Lite (in-session only, zero file changes) and
Tier I (full install with `install.sh`, overlay, symlinks, the works). Use
it when you've evaluated Lite and want it to keep applying in this repo
without doing a full install yet.

> Want the disciplines machine-wide (across every repo)? See Tier I:
> [setup/agent-install/tier-1.md](tier-1.md).

---

```
SYSTEM: Persist the Walter-OS Lite disciplines in this repository.

Perform these steps in order:

1. Create the directory `.walter-os-lite/` in the current repository root.

2. Write the file `.walter-os-lite/AGENTS.md` with the following content
   verbatim:

---
# Walter-OS Lite (persisted contract)

These rules apply for every change in this repository. They are a minimal
subset of the full Walter-OS contract (https://github.com/Xipher-Labs/walter-os).

## 1. Classify before you start (rigor)
- tiny: typo / single-line config / dep bump. No spec. Atomic commit.
- small: <50 LOC bug fix or function add. 2-3 sentence inline plan. TDD
  mandatory. Atomic commit.
- major: new feature / schema change / >200 LOC refactor / auth / crypto /
  money / PHI / production migration. Write a spec first. Full TDD.

## 2. TDD gate (mandatory for small + major)
RED (failing test) → GREEN (minimum code) → REFACTOR → COMMIT.
Skipping RED is a violation. Disabling a failing test is a violation.

## 3. Conventional commits
feat / fix / docs / refactor / test / chore / security / perf — subject
<=72 chars, imperative mood, body explains WHY.

## 4. Branch flow + push policy
feature/<slug> -> main via PR. NEVER push to main/master/staging/production
directly. NEVER auto-merge. Operator clicks merge.

## 5. Self-review checklist (before reporting done)
All tests pass / lint+typecheck clean / acceptance criteria covered by
tests / no commented-out code or unaddressed TODOs.

## 6. Hard nevers
NEVER commit secrets / auto-merge / disable failing tests / push to
protected branches.

## Upgrade path
For the full agent contract (skills, hooks, MCP profiles, walter-os CLI),
install Tier I: <https://github.com/Xipher-Labs/walter-os/blob/main/setup/agent-install/tier-1.md>.
---
   (end of .walter-os-lite/AGENTS.md content)

3. Append `.walter-os-lite/` to the repository root `.gitignore` if not
   already present. The .walter-os-lite/ directory is for personal
   evaluation, not team-wide enforcement — that is Tier II and above.

4. Report:
   - PASS: ".walter-os-lite/AGENTS.md written + .gitignore updated."
   - The file will be picked up by Claude Code / Codex CLI on the next
     session in this directory.

5. Adopt the disciplines for THIS session too (they only apply to future
   sessions otherwise).

ACK when complete.
```

---

## What just happened

The agent created `.walter-os-lite/AGENTS.md` in your current repo + added
the directory to `.gitignore`. Every future Claude Code or Codex CLI session
opened in this directory will pick up the Lite disciplines automatically.

The file is intentionally gitignored — Lite is for individual evaluation,
not team-wide enforcement. To enforce disciplines team-wide, use Tier I and
commit the full contract.

## How to verify

Run `walter-os doctor --lite` from your repo root:

- `PASS` — `.walter-os-lite/AGENTS.md` present and parseable.
- `NONE` — file absent; the agent didn't complete the persist step.

## How to remove

Delete `.walter-os-lite/` and remove the line from `.gitignore`.

## Upgrade

For the full contract (skills catalog, hooks, MCP profiles, walter-os CLI),
follow Tier I: [setup/agent-install/tier-1.md](tier-1.md).
