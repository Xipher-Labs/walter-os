# 0014. Operator-declared task level — three-layer resolution with state file persistence

**Date**: 2026-05-17
**Status**: Proposed
**Spec**: `docs/specs/operator-declared-task-level.md`
**Plan**: `docs/specs/operator-declared-task-level.plan.md`

## Context

`AGENTS.md` defines three task rigor levels (`tiny` / `small` / `major`)
with distinct gates per level — spec, tests, review, commit hygiene.
Today the agent self-classifies every task. Three failure modes are
recurrent in practice (see spec §1):

1. **Implicit downgrade.** Agent treats a config edit as `tiny`, then
   discovers mid-implementation that it touches an auto-escalation
   trigger (auth / crypto / money / PHI / hooks). By then the spec was
   skipped and a non-TDD commit was made.

2. **Cross-session drift.** A `major` feature spans multiple sessions.
   A fresh agent session reads the partial diff and classifies remaining
   work as `small`. The rigor floor is not durable.

3. **Operator surprise.** Operator and agent disagree about what
   classification a task deserves. Agent spends 40 minutes on a spec
   the operator considered unnecessary, or skips it where the operator
   wanted full rigor. No upfront contract.

The auto-escalation triggers in `AGENTS.md` (auth/, crypto/, money,
PHI, audit logs, prod migrations, hooks/, AGENTS.md) are *defensive
only*. They prevent the worst case (downgrade-to-tiny on a critical
path) but cannot lift an operator's intent that a particular
non-critical task deserves more rigor than its surface suggests.

## Decision

**Introduce a three-layer resolution model for the task rigor floor,
with auto-escalation always on top.**

```
Layer                            How set                              Persistence
───────────────────────────────  ──────────────────────────────────   ────────────────
1. Auto-escalation triggers      AGENTS.md hard rule (never lower)    permanent
2. Per-session slash command     /level major  (agent chat)           session
3. Persistent state file         ~/.config/walter-os/state/           machine-persistent
                                   current-task-level
4. Default policy                WALTER_TASK_RIGOR_POLICY env var     shell-persistent
5. Implicit fallback             auto-classify                        none
```

Effective level = max(layer 1 trigger, layer 2 slash, layer 3 state,
layer 4 env policy). Layer 1 only raises; the others can set a
declared floor.

`hooks/task-level-check.sh` (new) runs on Claude Code
`UserPromptSubmit` and Codex CLI `before_prompt`. It computes the
effective level, writes the OPERATOR-DECLARED block (see spec §4.4)
to the agent's context on every turn, and refuses code-changing tool
calls that violate the floor.

The CLI gains `walter-os level {get,set,clear}` and Claude Code gains
the `/level` slash command — both write the same state file at
`~/.config/walter-os/state/current-task-level`.

## Why this approach

**Visibility on every turn beats config-file checking.** Agents are
not reliable at re-reading `AGENTS.md` mid-session. Re-injecting the
resolved level into the system context every UserPromptSubmit is cheap
(< 5 ms) and makes the policy a first-class part of the agent's
working memory.

**Three layers serve three different operator workflows:**

- *Env var* is for the operator who wants the same policy on every
  task in a project (shell `.env`, dotfiles).
- *State file* is for the operator who runs a multi-day major task
  and wants the floor to survive session restarts.
- *Slash command* is for the operator who declares per-task scope
  in-the-moment and doesn't want to type at the shell.

Each layer maps to a real friction point we observed; collapsing them
into one would force operators back to manual workarounds.

**State file as source of truth, slash and CLI as sugar.** All paths
write the same file. This means Codex CLI users and Cursor users can
participate even without the Claude-Code-specific slash command —
they edit the file or use `walter-os level set`. The slash command
is convenience, not load-bearing.

**Auto-escalation stays unconditional.** This is critical. The
operator can floor *higher* than the auto-classifier (force `major`
on what looks like a quick fix). They cannot floor *lower* than the
auto-escalation triggers (cannot mark an auth change as `tiny`). This
preserves the safety property that motivated the AGENTS.md rules in
the first place.

## Alternatives considered and rejected

### A) Env var only

Single `WALTER_TASK_RIGOR_POLICY` env var, no state file, no slash
command. Simplest implementation.

**Rejected** because:

- No per-session declaration — operator who runs `auto` by default
  cannot temporarily floor a single task to `major` without exporting
  the var in their shell, then unexporting after.
- No persistence across slash commands (which is the natural
  interaction surface inside Claude Code today).
- Forces operators back to `export WALTER_TASK_RIGOR_POLICY=...` for
  every task — exactly the friction we're trying to remove.

### B) Slash command only (no state file, no env var)

Per-session only. State lives in the agent's transcript.

**Rejected** because:

- Loss on session restart. The "cross-session drift" failure mode from
  spec §1.2 is exactly what this fails to fix.
- Codex CLI and Cursor have no equivalent slash command surface.
  Forcing Claude-Code-only would split the contract.

### C) Per-directory or per-file map

`.walter-os/task-level.yml` per repo subdirectory mapping path globs to
rigor levels.

**Rejected** because:

- The unit of declaration is the *task*, not the path. A task often
  spans many files and a path-based map doesn't match the work shape.
- Maintenance burden — every new directory needs a decision.
- The auto-escalation triggers in AGENTS.md already do path-based
  matching for the safety subset; adding a parallel system for the
  operator-declared subset doubles cognitive load.

We deferred this to spec §6 NG4 — open future-work bucket if a real
need surfaces.

### D) Single YAML policy file

`~/.config/walter-os/policy.yml` with all knobs (rigor, branch flow,
trust tiers, MCP profile) merged into one declarative file.

**Rejected for *this* change** because:

- Out of scope. The other knobs already have their own files (per ADR
  0009 for trust tiers, ADR 0013 for branch flow). Centralizing them
  is a separate refactor that should be motivated independently.
- Introduces a YAML schema dependency where bash + env var + state
  file is sufficient.

Could be reconsidered in a future ADR if the overlay's surface area
grows past 6–8 knobs.

### E) GitHub PR label `rigor:major` as source of truth

Trust the PR label set by the operator as the rigor declaration.

**Rejected** because:

- PR label is set *after* the work has started — the rigor decision
  has to be visible *before* the agent writes code.
- GitHub-specific, doesn't help Cursor users editing locally without
  a PR yet.
- Forgejo and other Git hosts may not have parallel label semantics.

## Consequences

**Positive:**

- Operator gets per-task and per-session declaration with cross-session
  persistence (the gap in current AGENTS.md self-classification).
- Hook makes the resolved level visible on every turn — no silent
  drift even in long sessions.
- CLI + slash command + env var + state file is enough surface to
  match all three operator workflows (env, persistent, per-session)
  without forcing one to dominate.
- Auto-escalation safety is preserved unchanged.
- Testable in CI via Bats hook tests — no agent-in-the-loop tests
  required for the contract.

**Negative:**

- New hook on every `UserPromptSubmit` event. Latency must stay
  < 5 ms (covered in spec §7 risk matrix, plan B2 self-test).
- More state surfaces to remember: env var, state file, slash command.
  Mitigated by `walter-os level get` printing the effective level and
  source on demand.
- Operators who never use the feature pay a small docs-noise cost
  (new section in AGENTS.md). The default behavior (`auto`) matches
  pre-change behavior, so there is no migration burden.
- Slash command works only in Claude Code today. Cursor and Codex
  users edit the state file or use the CLI. Documented as the
  expected gradient — not a blocker.

**Reversible:**

- Yes. Removing the hook from `~/.claude/settings.json` and deleting
  `hooks/task-level-check.sh` reverts to current behavior. State file
  becomes inert. Env var becomes ignored. No data loss.

## Migration

1. `install.sh --upgrade` writes the new hook, scaffolds the state
   directory, and adds the slash command. No-op if the file already
   exists.
2. Operators who do nothing keep `auto` behavior (current default).
3. Operators who want to opt in run `walter-os level set major` (or
   set the env var in their overlay).
4. The interactive setup prompt (`setup/interactive-setup-prompt.md`
   §4) is updated to surface the new env var and slash command.

## Open questions (non-blocking)

- Q1: Should `floor-major` apply to commits made by background agents
  (cron, n8n workflows) or only interactive sessions? *Proposed
  resolution*: only interactive. Background agents already have their
  own approval-gate via `hooks/approval-gate.sh`; layering a second
  gate creates dead-locks.
- Q2: Should the hook also gate `Read` operations? *Proposed
  resolution*: no. Read is informational; only code-changing tool
  calls (`Edit`, `Write`, `Bash` with non-read commands) need the
  gate.

## References

- AGENTS.md "Universal disciplines" → "Task rigor levels"
- spec `docs/specs/operator-declared-task-level.md`
- plan `docs/specs/operator-declared-task-level.plan.md`
- ADR 0009 (agent trust tiers) — same pattern: per-agent value, gate
  applied at hook layer.
- ADR 0013 (solo-operator merge policy) — precedent for
  operator-configurable framework knobs with env-var control.
