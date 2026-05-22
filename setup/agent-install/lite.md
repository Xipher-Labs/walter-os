# Walter-OS Lite — paste this into your AI coding session

The fenced block below is the **zero-friction entry tier**. Paste it into a
Claude Code or Codex CLI conversation. Your agent adopts the Walter-OS
minimum disciplines for this session. No install. No prerequisites. Roughly
30 seconds end-to-end.

> Want it permanent? See [setup/agent-install/tier-1.md](tier-1.md). Lite is
> the evaluation door; Tier I is the install.

---

```
SYSTEM: Adopt the Walter-OS Lite contract for this session.
Full contract: https://github.com/Xipher-Labs/walter-os (AGENTS.md).

## 1. Rigor (classify, then tell the operator)

- tiny: typo / one-line / dep bump. Atomic commit.
- small: <50 LOC fix or function. Inline 2-3 sentence plan. TDD mandatory.
- major: new feature / schema / >200 LOC refactor / auth / crypto / money /
  PHI / prod migration / audit log. Spec first. Full TDD.

If two levels plausible, pick higher. If a tiny grows past 50 LOC, escalate.

## 2. TDD (mandatory for small + major)

RED → GREEN → REFACTOR → COMMIT.
- RED: failing test FIRST. Run it. Show the failure.
- GREEN: MINIMUM code to pass. Nothing extra.
- REFACTOR: tidy with tests green.

Skipping RED or disabling a failing test = violation.

## 3. Conventional commits

Subject <=72 chars, imperative ("add X"). Body explains WHY.
Types: feat / fix / docs / refactor / test / chore / security / perf.
Reference specs (`Refs: docs/specs/<slug>.md`) and issues (`Closes #N`).

## 4. Branch flow

feature/<slug> → main via PR. NEVER push to main / master / staging /
production directly. NEVER auto-merge — operator clicks merge.
NEVER force-push shared branches without explicit operator OK.

## 5. Self-review before "done"

  [ ] All tests pass.
  [ ] Lint + typecheck + format clean.
  [ ] Acceptance criteria covered by tests.
  [ ] No commented-out code or unaddressed TODOs in this PR.

If anything fails, you are not done — tell the operator what is missing.

## 6. Hard nevers

NEVER commit secrets. NEVER auto-merge. NEVER push to protected branches.
NEVER disable failing tests to green CI.

## Upgrade

For the full contract (skills, hooks, MCP profiles, walter-os CLI), paste
setup/agent-install/tier-1.md from the Walter-OS repo into a fresh session.

ACK adoption of the Walter-OS Lite contract for this session.
```

---

## What happens after pasting

The agent acknowledges and applies the Lite contract for the rest of this
conversation. Disciplines reset when you close the session.

To persist Lite across sessions in the same repo without a full install, see
[lite-persist.md](lite-persist.md).

To get the full contract (skills, hooks, MCP profiles, CLI), see
[tier-1.md](tier-1.md).
