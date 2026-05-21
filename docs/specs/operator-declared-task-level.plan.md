# PLAN: Operator-declared task level enforcement

**Spec:** `docs/specs/operator-declared-task-level.md`
**ADR:** `docs/decisions/0014-operator-declared-task-level.md`
**Branch:** `feature/operator-declared-task-level`
**Total tasks:** 14 (12 implementation + 2 verification).
**Estimated effort:** 4–6 hours assuming Bats + bash familiarity.

Each task follows the RED-GREEN-REFACTOR discipline. Skip RED is a violation
of `test-driven-development` (superpowers).

---

## Phase A — Test scaffolding (foundation)

### A1. Create Bats test directory + fixtures

**Files:**
- `tests/hooks/task-level-fixtures/auto-env.sh` (sets `WALTER_TASK_RIGOR_POLICY=auto`)
- `tests/hooks/task-level-fixtures/floor-small-env.sh`
- `tests/hooks/task-level-fixtures/floor-major-env.sh`
- `tests/hooks/task-level-fixtures/always-ask-env.sh`
- `tests/hooks/task-level-fixtures/state-with-major.txt` (`major\n2026-05-17T10:00:00Z\nslash`)
- `tests/hooks/task-level-fixtures/state-with-tiny.txt`
- `tests/hooks/task-level-fixtures/auto-escalation-paths.txt` (one per line:
  `auth/foo.ts`, `crypto/bar.rs`, `programs/lib.rs`, `migrations/001.sql`,
  `hooks/branch-flow-guard.sh`)

**Verify:** `bats --list tests/hooks/` mentions the new files (none, just dir exists).

### A2. Write failing tests for resolution precedence (RED)

**File:** `tests/hooks/task-level-resolution.bats`

Tests (all should fail because hook doesn't exist yet):
- `@test "env=auto, no state → effective=auto, source=env"`
- `@test "env=floor-small, no state → effective=floor-small, source=env"`
- `@test "env=auto, state=major → effective=major, source=state"`
- `@test "env=floor-major, state=tiny → effective=major (floor wins)"`
- `@test "no env, no state → effective=auto, source=default"`

**Verify:** `bats tests/hooks/task-level-resolution.bats` reports 5 failures.

---

## Phase B — Core hook implementation

### B1. Implement `hooks/task-level-check.sh` skeleton

**File:** `hooks/task-level-check.sh`

Stub that:
1. Reads `WALTER_TASK_RIGOR_POLICY` (default `auto`).
2. Reads `~/.config/walter-os/state/current-task-level` if exists (first line).
3. Resolves effective level: `state` beats `env` for the *floor*; final level
   is `max(env-floor, state-declared, auto-escalation-floor)`.
4. Emits to stdout the OPERATOR-DECLARED block (see spec §4.4).
5. Exits 0 always (informational hook, not a gate yet).

**Verify:** `bats tests/hooks/task-level-resolution.bats` — 5/5 GREEN.

### B2. Add `--self-test` mode

Pattern from `hooks/branch-flow-guard.sh`. Runs an in-process matrix of
(env, state) → expected effective level. Exits non-zero on any mismatch.

**Verify:** `./hooks/task-level-check.sh --self-test` → "OK (10 cases)".

### B3. Atomic state file writes

In the helper function that writes to `current-task-level`:
- Write to `mktemp` in the same dir.
- `mv` over the destination (atomic on POSIX same-FS).
- `chmod 600` (operator-only readable, prevents other-user snoop).

**Test:** new bats test `task-level-atomicity.bats` — runs 10 concurrent
writes via `&` background jobs, asserts file is never half-written.

---

## Phase C — Auto-escalation enforcement

### C1. Implement path-pattern auto-escalation

Add to `hooks/task-level-check.sh`: when given a list of paths (via
`--for-paths`), check each against the trigger patterns from AGENTS.md:

```
auth/**, crypto/**, programs/**, migrations/**, hooks/**,
AGENTS.md, install.sh, mcp/servers.json,
**/secrets/**, **/.env*
```

If any path matches → floor becomes `major` regardless of declared level.

**Test:** `task-level-auto-escalation.bats` — feeds each path in the fixture
file from A1 and asserts effective=major.

### C2. Money-pattern detection

In addition to path triggers, detect content triggers in staged files:
- Stripe API calls (`stripe.charges.create`, `paymentintents`).
- Solana token transfers (`SystemProgram.transfer`, `TokenInstruction::Transfer`).
- AWS billing endpoints, `subscription`, `invoice` SQL columns.

This is heuristic — emit a warning, not a hard block (the false-positive rate
on token-detection regexes is too high to gate on).

**Test:** `task-level-money-detect.bats` — 5 positive samples + 5 negative.

---

## Phase D — Slash command + CLI

### D1. Claude Code slash command `/level`

**File:** `~/.claude/commands/level.md` (installed by `install.sh --upgrade`).

```markdown
---
name: level
description: Set or query the current task rigor floor.
allowed-tools: Bash
---

When called with no args, run `~/.config/walter-os/bin/walter-os level get`.
When called with `tiny|small|major`, run `walter-os level set <arg>`.
When called with `clear`, run `walter-os level clear`.
```

**Test:** manual — slash command appears in Claude Code's `/help` after
`install.sh --upgrade` + restart.

### D2. CLI subcommand `walter-os level`

**File:** `bin/walter-os` (extend existing CLI).

```
walter-os level get        # print current effective + source
walter-os level set major  # write state file, source=slash
walter-os level clear      # rm state file
```

**Test:** `tests/cli/walter-os-level.bats` — exit code + output matrix.

### D3. Symmetry doc

Add a 5-line block to `bin/walter-os --help` output explaining the level
subcommand. Update `docs/operational/cli-reference.md` if it exists.

---

## Phase E — Hook wiring + agent contract update

### E1. Wire hook into Claude Code settings

**File:** `~/.claude/settings.json` (templated by `install.sh`).

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "command": "$HOME/.config/walter-os/hooks/task-level-check.sh" }
    ]
  }
}
```

**Test:** `./install.sh --dry-run` shows the diff that would write this.

### E2. Wire hook into Codex CLI

**File:** `~/.codex/config.toml` template (operator overlay).

```toml
[hooks.before_prompt]
command = "$HOME/.config/walter-os/hooks/task-level-check.sh"
```

**Test:** `setup/codex-config.toml.example` updated; `install.sh --check`
validates the example parses.

### E3. Update AGENTS.md

Insert new subsection under "Universal disciplines" → "Task rigor levels"
documenting:
- The three layers (env / state / slash).
- Precedence (auto-escalation > slash > state > env > default).
- How operators set each.
- That auto-escalation is unconditional.

**Test:** none — doc change. Reviewer reads.

### E4. Update setup/interactive-setup-prompt.md

§4 already references `WALTER_TASK_RIGOR_POLICY`. Confirm the four values
match the implementation. Add a note that the operator can also run
`/level` mid-session.

---

## Phase F — Verification

### F1. Run full hook test suite

```bash
bats tests/hooks/
```

Expected: all GREEN. AC1–AC5 + AC10 covered.

### F2. Run install.sh idempotency check

```bash
./install.sh --upgrade
./install.sh --upgrade  # second run, should be no-op
diff <(./install.sh --dry-run) /dev/null  # empty diff
```

Expected: AC6 covered.

### F3. Manual smoke test in real Claude Code session

1. Open Claude Code in this repo.
2. `/level major` → confirm state file written.
3. Restart Claude Code (close + reopen).
4. New session — first prompt — confirm the OPERATOR-DECLARED block appears
   in the system context and reads `major (source: state)`.
5. `/level clear` → confirm state file removed.
6. Next prompt → block reads `auto (source: default)`.

Expected: AC2, AC3, AC5 covered.

### F4. DoD validator pass

```bash
walter-os skills run definition-of-done-validator \
  --spec docs/specs/operator-declared-task-level.md
```

Expected: 10/10 acceptance criteria mapped to tests. AC matrix printed.

---

## Out-of-plan items (require operator approval to add later)

- Telemetry → Control Tower dashboard (F2 from spec §6).
- Per-project override file (F4 from spec §6).
- Cross-machine sync of state (F3 from spec §6, explicitly NG4).

---

## Commit strategy

One commit per task (A1, A2, B1, …). Conventional commits:

```
feat: scaffold task-level hook tests (A1)
feat: add resolution precedence to task-level hook (B1)
test: cover auto-escalation paths (C1)
docs: ADR 0014 + AGENTS.md operator-declared task level
```

Final commit: `feat: operator-declared task level enforcement` referencing
the spec and ADR in the footer.

PR title: `[FEAT] -OPERATIONS- operator-declared task level enforcement`
(matches `hooks/pr-title-validator.sh` convention).
