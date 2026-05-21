# SPEC: Operator-declared task level enforcement

**Status:** Draft (2026-05-17). Awaiting operator approval.
**Triggered by:** Operator feedback in interactive setup discussion — current rigor self-classification is fragile, agents downgrade implicitly.
**Related:** `AGENTS.md` "Task rigor levels (tiny / small / major)", `hooks/branch-flow-guard.sh`, `setup/interactive-setup-prompt.md` §4, ADR 0014.
**Rigor classification:** MAJOR (touches `AGENTS.md`, `hooks/`, agent contract — auto-escalation per AGENTS.md).

---

## 1. Problem

`AGENTS.md` defines three task rigor levels (`tiny` / `small` / `major`) with
distinct gates per level — spec, tests, review, commit hygiene. Today the
agent **self-classifies** every task. This fails in three predictable ways:

1. **Implicit downgrade.** A task that looks like a config edit (tiny) turns
   out to touch auth or money flows — the agent has already skipped the spec
   and committed without TDD when it discovers the escalation trigger.
2. **Cross-session drift.** A multi-day feature classified as `major` on
   Monday gets touched by a fresh agent session on Wednesday, which reads the
   diff at face value and treats remaining work as `small`. The rigor floor
   is not durable across sessions.
3. **Operator surprise.** Operator believes "this is small" but the agent
   self-classifies as `major` and spends 40 minutes on spec + plan, or vice
   versa. There is no upfront contract.

Compounding these: the auto-escalation triggers in `AGENTS.md` (auth/, crypto/,
money, PHI, audit logs, prod migrations, hooks/) are **defensive only** — they
catch downgrade-to-tiny mistakes but do nothing to prevent
downgrade-to-small or to make the operator's intent visible.

## 2. Goals

- **G1.** Operator can declare the rigor floor for a task or a session before
  any code is touched.
- **G2.** Declaration is visible to the agent on every turn (no silent loss).
- **G3.** Declaration survives across Claude Code, Codex CLI, and Cursor
  sessions on the same machine.
- **G4.** Auto-escalation to `major` for auth/crypto/money/PHI/audit/hooks
  remains in force. Operator can floor higher, never lower the safety triggers.
- **G5.** Re-running the interactive setup honors the current declaration —
  does not silently reset it.
- **G6.** Mechanism is testable in CI (no agent-in-the-loop tests required).

## 3. Non-goals

- **NG1.** Not building a per-file or per-directory rigor map. The unit of
  declaration is the *task*, not the path.
- **NG2.** Not forcing operators to use it. `auto-classify` (current behavior)
  remains the default for backward compatibility.
- **NG3.** Not implementing a UI. CLI + env var + slash command only.
- **NG4.** Not implementing cross-machine sync of the current level. Each
  machine carries its own state file.
- **NG5.** Not changing what each rigor level *means* (the spec/test/review
  matrix in `AGENTS.md`). Only how the level gets selected.

## 4. Design (decisions locked, see ADR 0014)

### 4.1 Three layers, precedence top-down

```
Layer                              How set                              Persistence
─────────────────────────────────  ──────────────────────────────────   ──────────────
1. Auto-escalation triggers        AGENTS.md hard rule (never lower)    permanent
2. Per-session slash command       /level major  (in agent chat)        session
3. Persistent state file           ~/.config/walter-os/state/           machine-persistent
                                     current-task-level
4. Default policy                  WALTER_TASK_RIGOR_POLICY env var     shell-persistent
5. Implicit fallback               auto-classify                        none
```

The hook reads from layer 5 upward and stops at the first layer that resolves
a value. Layer 1 always wins on the *floor* (it can only raise, never lower).

### 4.2 Default policy values (`WALTER_TASK_RIGOR_POLICY`)

| Value | Meaning |
|---|---|
| `auto` (default) | Agent self-classifies; layer 1 still applies. |
| `always-ask` | Agent must prompt "tiny / small / major?" before any code-changing tool call. |
| `floor-small` | Tasks may not run at `tiny`. Minimum is `small` (TDD + atomic commit). |
| `floor-major` | Every task gets full spec + plan + TDD + DoD validator. Heavy. |

### 4.3 Slash command `/level`

Registered in `~/.claude/commands/level.md` (Claude Code skill format), with
documentation surfaces for Codex CLI and Cursor (different invocation paths,
same state file).

```
/level [tiny|small|major|clear]   — set current session's floor
/level                            — print current effective level + source
```

Writes/reads `~/.config/walter-os/state/current-task-level`. File format:

```
<level>
<timestamp ISO 8601>
<source: env|state|slash|auto>
```

### 4.4 Hook injection

`hooks/task-level-check.sh` runs on Claude Code `UserPromptSubmit` (and the
Codex CLI equivalent `before_prompt`). Reads the resolved level and emits a
system-prompt block:

```
OPERATOR-DECLARED TASK LEVEL: <level>
  Source: <env|state|slash|auto>
  Constraints:
    - <list per level: spec required, tests required, reviewer required, etc.>
  Auto-escalation triggers (always-on, cannot be downgraded):
    - auth/, crypto/, money, PHI, audit logs, prod migrations, hooks/, AGENTS.md
```

This makes the level **visible in every turn**, not buried in a config file
the agent might or might not re-read.

### 4.5 Failure modes (what the hook refuses)

- If `current-task-level=major` and the agent attempts `Edit`/`Write` without
  a spec at `docs/specs/<slug>.md` — block with error explaining the floor.
- If `WALTER_TASK_RIGOR_POLICY=always-ask` and the session has no slash-set
  level — block the first code-changing tool with "declare level first".
- If the operator manually deletes the state file mid-session, the hook falls
  back to the env var on the next turn (no error, just downgrade in the
  visible context block).

## 5. Acceptance criteria

Each criterion gets at least one test (per AGENTS.md DoD rule).

- [ ] **AC1.** `WALTER_TASK_RIGOR_POLICY=floor-small` blocks any code-changing
  tool that would run without RED-GREEN-REFACTOR. Tested via hook unit test
  using a `stub-tool-call.json` fixture.
- [ ] **AC2.** `/level major` writes the state file, persists across one
  process boundary (close + reopen Claude Code), and the next session reads it.
  Tested via Bats: `bats tests/hooks/task-level-state.bats`.
- [ ] **AC3.** `/level clear` removes the state file. Next turn falls back to
  the env var. Tested in the same Bats file.
- [ ] **AC4.** Auto-escalation: setting `/level tiny` then editing a file
  matching `auth/**` or `crypto/**` raises the effective level to `major`
  and surfaces the override reason in the hook output. Tested with a fixture
  matrix (auth/foo.ts, crypto/bar.rs, programs/lib.rs, etc.).
- [ ] **AC5.** Hook output (the OPERATOR-DECLARED block) is present on
  every `UserPromptSubmit` event during an interactive session. Tested via
  `bats tests/hooks/task-level-injection.bats` parsing the rendered hook
  output.
- [ ] **AC6.** `install.sh --upgrade` is idempotent w.r.t. the state file —
  preserves existing declarations, scaffolds the directory only if missing.
- [ ] **AC7.** `setup/interactive-setup-prompt.md` §4 picks up the new env
  var name and the new slash command. Setup wizard writes
  `WALTER_TASK_RIGOR_POLICY` to `~/.config/walter-os/overlay/personal.env`.
- [ ] **AC8.** `AGENTS.md` updated with a new "Operator-declared task level"
  subsection documenting the three layers + precedence.
- [ ] **AC9.** ADR 0014 explains the choice over rejected alternatives
  (single env var only; single slash command only; per-directory map; YAML
  policy file).
- [ ] **AC10.** Existing rigor tests still pass (no regression on the
  auto-classify default).

## 6. Out-of-scope follow-ups (file separately if desired)

- **F1.** Auto-detect the rigor level from PR diff size + path patterns on PR
  open (would help in code-review-only flows where the operator never set
  `/level`).
- **F2.** Telemetry: aggregate per-week how many tasks ran at which level,
  surface in Control Tower. Useful but not blocking.
- **F3.** Cross-machine sync of `state/current-task-level` via Syncthing or
  the operator's own dotfiles repo. Skipped in NG4.
- **F4.** Per-project override: `<repo>/.walter-os/task-level` file that
  beats the global state. Deferred until a real need arises.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Operator forgets to clear `floor-major` and every quick fix takes 40 min | High | Med | `/level` with no args prints current + source so operator notices; CLI alias `walter-os level` shows it in shell. |
| Slash command not portable to Codex / Cursor | High | Low | State file is the source of truth; slash command is sugar. Codex/Cursor users edit the file directly or use env var. |
| Hook latency on every UserPromptSubmit | Med | Low | Hook is a 30-line bash script reading a 3-line file. Should be < 5 ms. Benchmark in AC test. |
| Race condition on concurrent agents writing the state file | Low | Med | Atomic write via `mktemp + mv`. Documented in hook code. |
| AC10 regression (auto default breaks) | Low | High | Run full `bats tests/hooks/` suite before merge. CI gates this. |

## 8. Open questions for operator

None blocking. The design is locked per the chat discussion. The operator
should confirm:

- (Q1) Default policy in personal overlay: `auto` or `always-ask`? Recommend
  `auto` for first release, lets the operator opt in to stricter modes as
  habits develop.
- (Q2) Is the `/level` slash command also surfaced as `walter-os level
  <tiny|small|major|clear>` for shell use? Recommend yes — symmetry beats
  duplication.

## 9. References

- `AGENTS.md` §"Universal disciplines" → "Task rigor levels (tiny / small / major)"
- `docs/decisions/0013-solo-operator-merge-policy.md` — precedent for
  operator-configurable framework knobs.
- `setup/interactive-setup-prompt.md` §4 — the placeholder env var name
  already documented (`WALTER_TASK_RIGOR_POLICY`).
- `hooks/branch-flow-guard.sh` — pattern for hook + env var + self-test.
- `obra/superpowers` skills: `test-driven-development`, `writing-plans`,
  `verification-before-completion`.
