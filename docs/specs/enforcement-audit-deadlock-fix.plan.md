# Plan — Enforcement audit-chain deadlock fix

**Spec**: `docs/specs/enforcement-audit-deadlock-fix.md` (issues #516 spec · #518 exec)
**Branch**: `codex/enforcement-doctor-bypass-fix` (already open) or
`fix/enforcement-audit-deadlock`
**Rigor**: major — every task is RED → GREEN → REFACTOR → COMMIT. Reviewer +
security-auditor sign-off before merge. Conventional commits, `Refs:
docs/specs/enforcement-audit-deadlock-fix.md`.

> Ordering: Task 0 restores a working shell *now* (no code). Tasks 1–2 fix the
> deadlock mechanism. Task 3 (D3) is gated on security-auditor sign-off and can
> ship behind `WALTER_AUDIT_STRICT` default. Tasks 4–6 are recovery + polish.

---

## Task 0 — Operational unblock (no code, do first)

Restore the shell so execution can even run hooks.

- Review the external submodule hook diff flagged CRITICAL on 2026-06-08
  (`marchetto-agent-skills/.../load-lessons.sh` checksum drift). If the
  submodule bump was reviewed, run `walter-os baseline-external-hooks`.
- Import the egress allowlist:
  `walter-os egress import "$WALTER_OS_HOME/contexts/_examples/egress-allowlist.example.txt"`.
- If today's chain is already poisoned, archive it:
  `mv ~/.config/walter-os/audit/chain-<today>.jsonl{,.broken}` and the matching
  `root-<today>.txt`, after `walter audit verify` on the archived copy for the
  record.
- **Verify**: a plain `git status` via Bash returns `allow` (shell restored).

## Task 1 — Append verifies last-row+root only (D2)

**File**: `scripts/walter/lib/audit-chain.sh`, `tests/audit/*` (bats).

- RED: add a test — build an N-row valid chain, corrupt row 1's `row_hash`,
  assert `walter_audit_append` still succeeds (last row + root intact) AND
  `walter audit verify` still FAILS on row 1.
- RED: add a perf/behavior test — append does not call
  `_walter_audit_verify_chain_file_unlocked` (assert via a shim/counter or by
  asserting append cost is independent of chain length).
- GREEN: in `walter_audit_append`, replace the full
  `_walter_audit_verify_chain_file_unlocked` call with a new
  `_walter_audit_verify_tail_unlocked` (verify last row hash + signature + root
  match only). Keep full verify in `walter audit verify`.
- **Verify**: `bats tests/audit/` + `tests/hooks/audit-chain-hook-integration.bats`.

## Task 2 — Audit append moves to the sandbox runner (D1)

**Files**: `scripts/walter/sandbox-hook-runner.sh`,
`hooks/{network-gate,bash-denylist,capability-check}.sh`,
`tests/hooks/*.bats`.

- RED: test that running `network-gate.sh` through `sandbox-hook-runner.sh`
  under the real read-only/key-blind profile (a) emits the child's decision
  JSON unchanged and (b) results in exactly one new signed audit row written by
  the runner.
- RED: test the child hooks no longer attempt their own append when invoked via
  the runner (env flag `WALTER_AUDIT_DELEGATED=1` set by the runner → child
  skips inline append).
- GREEN: in `sandbox-hook-runner.sh`, after `walter_sandbox_run` returns,
  parse the captured stdout decision and call `walter_audit_append` (un-sandboxed
  context can sign + write). Set `WALTER_AUDIT_DELEGATED=1` for the child.
- GREEN: in the three sandboxed hooks, guard the inline `_audit_decision` calls
  on `WALTER_AUDIT_DELEGATED` so they don't double-append (and don't fail-closed
  on the sandbox's inability to sign).
- **Verify**: `bats tests/hooks/network-gate.bats tests/hooks/bash-denylist.bats
  tests/hooks/capability-check.bats`; manual: a real Bash call in a session
  returns `allow` and a signed row lands.

## Task 3 — Two-class fail model (D3) — GATED on security-auditor

**Files**: `scripts/walter/sandbox-hook-runner.sh`, `audit-chain.sh` (or a small
`audit-degraded.sh` helper), `tests/hooks/*`, docs.

- Pre-req: security-auditor reviews D3 in the spec and approves or vetoes.
- RED: with the signer forced to fail and `WALTER_AUDIT_STRICT` unset, an *allow*
  child decision is relayed with an `AUDIT DEGRADED` systemMessage and a
  `DEGRADED-<date>.txt` breadcrumb appears; with `WALTER_AUDIT_STRICT=1` the same
  condition blocks; a *block* child decision always blocks.
- GREEN: implement the degraded branch in the runner's post-decision append.
- Doc: `docs/operational/` note on degraded mode + the strict kill-switch.
- **Verify**: new bats + existing suites green.
- If vetoed: skip; keep fail-closed; ensure Task 4 makes recovery one command.

## Task 4 — `walter doctor --unblock` (D4)

**Files**: `scripts/walter/subcommands/doctor.sh`, `tests/cli/*` or
`tests/walter/*`.

- RED: test `doctor --unblock` exits non-zero and prints (a) the real report
  path from `audit-status.json.report`, (b) the egress import command when the
  allowlist is missing, (c) the chain-rotate hint when today's append fails.
- RED: test `doctor --unblock --fix` imports the egress example + rotates a
  poisoned chain, then a follow-up append succeeds.
- GREEN: implement `--unblock [--fix]` reusing existing audit-chain + egress
  helpers.
- **Verify**: bats for doctor + a manual end-to-end unblock from a poisoned state.

## Task 5 — Fix daily-audit-gate block message + report path (AC-7)

**Files**: `hooks/daily-audit-gate.sh`, `tests/hooks/daily-audit-gate.bats`.

- RED: assert the block `reason` contains the path from
  `audit-status.json.report` (not a hardcoded `audit-${TODAY}.md`) and the
  correct ack command.
- GREEN: read `.report` from `audit-status.json`; fall back to today's path only
  if absent.
- **Verify**: `bats tests/hooks/daily-audit-gate.bats`.

## Task 6 — Docs + DoD

- Update `CHANGELOG.md` (v0.6.3 — enforcement deadlock recovery).
- `docs/operational/` runbook: "Agent shell blocked by audit-chain — recovery".
- Run `definition-of-done-validator`: every acceptance criterion (1–8) maps to a
  test from tasks 1–5.
- **Verify**: full `bats tests/hooks tests/audit` green; lint/shellcheck clean;
  reviewer + security-auditor approved.

---

## Risk notes

- D2 narrows append-time tamper detection. Mitigation: `verify` + close-day +
  scheduled Rekor still do full verification; document the threat-model delta in
  the spec's D2 (done) and have security-auditor confirm it's acceptable.
- Task 2 changes the trust boundary of *where* signing happens (runner, not
  child). The runner is already un-sandboxed and already handles the bypass
  audit log, so it is an appropriate place — but security-auditor must confirm
  the runner can't be tricked into signing a forged decision (it must sign the
  child's *actual* emitted decision, parsed strictly).
