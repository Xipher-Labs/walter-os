# Enforcement audit-chain deadlock — recovery + fail-mode redesign

**Status**: ready for `/write-plan` execution (plan: `enforcement-audit-deadlock-fix.plan.md`)
**Issue**: #516 (spec/epic) · sibling exec issue #518
**Target release**: v0.6.3 (patch — restores a working agent shell)
**Severity**: P0 — every Bash (and, once the day's chain grows, every Write/Read)
tool call is blocked in any Claude Code session whose PreToolUse hooks are the
Walter-OS chain. This is a total denial-of-service on the operator's own agent.
**Depends on / touches**: `hooks/network-gate.sh`, `hooks/bash-denylist.sh`,
`hooks/capability-check.sh`, `hooks/approval-gate.sh`,
`scripts/walter/sandbox-hook-runner.sh`, `scripts/walter/lib/audit-chain.sh`,
`setup/sandbox-profiles/walter-hook-default.sb`,
`scripts/walter/subcommands/doctor.sh`.
Auth/crypto/audit-trail surface → **major rigor**: reviewer + security-auditor
sign-off required before merge.

## Problem

As of ~2026-06-10, a fresh Claude Code session in this repo cannot run a single
Bash command. Every call returns:

```
network-gate: audit-chain append failed; refusing unaudited decision
bash-denylist: audit-chain append failed; refusing unaudited decision
approval-gate: audit-chain append failed; refusing unaudited decision
```

The audit was performed entirely through a non-gated MCP (Desktop Commander),
which is itself a second finding (out of scope here, tracked separately).

### Root cause (confirmed in code)

Two security features contradict each other:

1. **Sandbox profile is read-only and key-blind.**
   `setup/sandbox-profiles/walter-hook-default.sb` runs the sandboxed hooks
   with `(allow file-write* (subpath SCRATCH))` + `/dev/null` only, and
   `(deny file-read* (regex #".*\\.key$"))`. So a hook running inside the
   sandbox cannot read the session signing key nor write to
   `~/.config/walter-os/audit/`.

2. **Every safety hook now requires a *signed* audit append per decision.**
   `network-gate.sh`, `bash-denylist.sh`, and `capability-check.sh` are
   wrapped by `sandbox-hook-runner.sh` and source `audit-chain.sh`. Their
   `_audit_decision` / `audit_*` helpers call `walter_audit_append`, which
   (a) reads the session `*.key` to ED25519-sign the row and (b) writes to the
   audit dir. Inside the sandbox both are denied → append fails → the hook's
   own fail-closed path blocks the tool call.

`approval-gate.sh` runs **un-sandboxed** yet *also* fails. That exposes the
second half of the root cause:

3. **Append re-verifies the entire day's chain, and one bad row poisons the
   whole day.** `walter_audit_append` calls
   `_walter_audit_verify_chain_file_unlocked` on every append — full
   re-hash + ED25519 verify of every prior row, under a 10s lock. Once any
   single row fails verification (e.g. a partial/unsigned row written by a
   sandboxed hook mid-failure, or a row signed by a session whose pubkey the
   sandbox couldn't read), **every subsequent append for that date fails** —
   including from un-sandboxed hooks. The chain is a single point of failure
   with no self-repair path.

### Aggravating factors

- **O(n²) append cost + lock contention.** Full-chain verification per append
  means appends get slower all day, and because Claude Code runs all hooks of a
  matcher concurrently (Bash has 6, Write has 3), they race on the single
  `.chain.lock`. Sequential single calls can pass while parallel calls fail —
  observed live this session.
- **No recovery path.** `daily-audit-gate.sh` hard-blocks on an unresolved
  CRITICAL but its block message points at `audit-${TODAY}.md`, which is not the
  real report (`audit-status.json.report` → `audit-2026-06-08.md`). The operator
  is told to run `walter-os ack <id>` with no id and a wrong path.
- **Missing egress allowlist.** `~/.config/walter-os/egress-allowlist.txt` does
  not exist, so even with the audit fixed, network-gate's default-deny would
  block every outbound call. Flagged INFO in the 2026-06-08 report, never
  imported.

## Decisions

### D1 — Audit append moves OUT of the sandboxed child (chosen)

The sandboxed hook decides allow/block; the **un-sandboxed**
`sandbox-hook-runner.sh` performs the audit append for that decision after the
child returns. The child emits its decision JSON (already does); the runner
parses it, appends a signed row keyed off `decision`/`reason`/hook name, then
relays the child's stdout unchanged.

- **Rejected**: granting the sandbox profile write access to the audit dir +
  read access to `*.key`. That re-opens exactly the exfil path the sandbox
  exists to close (a compromised hook could sign arbitrary rows / read the key).

`approval-gate.sh` and `branch-flow-guard.sh` already run un-sandboxed and keep
appending inline.

### D2 — Append verifies only the last row + root, not the whole chain (chosen)

`walter_audit_append` verifies (a) the last row's `row_hash`, (b) its signature,
and (c) that `root-<date>.txt` matches `hash(last_row)` before chaining the new
row. Full-chain verification stays in `walter audit verify` / close-day /
scheduled Rekor anchoring, where O(n) per-day is acceptable.

- Tamper-evidence is preserved: every row still commits `prev_hash`, the root is
  still updated atomically per append, and `verify` still catches any mid-chain
  edit. We trade "detect tampering at write time" (which an attacker who can
  edit the chain can also bypass) for "writes don't get quadratically slower and
  one bad row doesn't brick the day".
- **Rejected**: keep full verification (the current O(n²) + poison-the-day
  behavior).

### D3 — Two-class fail model: security fail-closed, audit-infra fail-degraded (RECOMMENDED — needs security-auditor sign-off)

Separate two distinct failure causes that today both hard-block:

- **Security decision** (the hook actually decided *block*): unchanged —
  fail-closed, command blocked.
- **Audit-writer infrastructure failure** (the hook decided *allow* but the
  signed append could not be written — missing key, unwritable dir, sign error):
  emit the hook's real decision and attach a loud `systemMessage`
  `"AUDIT DEGRADED: <reason>"`, and drop a breadcrumb at
  `~/.config/walter-os/audit/DEGRADED-<date>.txt`. A misconfiguration must not
  be a total DoS on the operator.

This is bounded by a kill-switch: `WALTER_AUDIT_STRICT=1` (or a config flag)
restores today's strict fail-closed behavior for operators who require it. The
breadcrumb means degraded mode is always visible and the daily audit can surface
it.

- **Conservative fallback if security-auditor rejects D3**: keep full
  fail-closed, but make D1+D2+the `doctor --unblock` recovery (D4) mandatory so
  the deadlock is one command to clear, and document `WALTER_AUDIT_STRICT=0` as
  an explicit opt-out break-glass.

### D4 — `walter doctor --unblock` recovery command (chosen)

Extend `doctor.sh` (already has `--enforcement`) with `--unblock` that detects
and reports, and `--unblock --fix` that applies the safe remediations:

- audit-chain for today fails to append (poisoned/locked) → offer to rotate the
  day's chain (archive + re-root) after a `verify` of the archived copy;
- `egress-allowlist.txt` missing → offer `walter-os egress import <example>`;
- unresolved CRITICAL in `audit-status.json` → print the real report path + the
  exact `walter-os ack`/`baseline-external-hooks` command;
- stale `.chain.lock` → report owner pid + safe removal.

### D5 — Operational unblock is task 0 (chosen)

Independently of the code fix, the operator must clear the standing block to get
a shell back: triage the 2026-06-08 CRITICAL (external submodule hook checksum
drift — `walter-os baseline-external-hooks` if the submodule bump was reviewed)
and import the egress allowlist example. Documented as plan task 0.

## Acceptance criteria

1. A sandboxed safety hook (`network-gate`/`bash-denylist`/`capability-check`)
   reaches an allow/block decision and that decision is recorded as a signed
   audit row **without the sandboxed child reading any `*.key` or writing to the
   audit dir**. (test: run the hook through `sandbox-hook-runner.sh` under the
   real profile; assert decision JSON emitted unchanged AND a new signed row
   appended by the runner.)
2. `walter_audit_append` performs O(1) verification (last row + root only); a
   chain with a *valid* last row + matching root accepts a new append even if an
   earlier row is corrupted, while `walter audit verify` still FAILS on that
   corrupted row. (two tests.)
3. With the audit writer unable to sign/write and `WALTER_AUDIT_STRICT` unset,
   an *allow* decision is emitted with an `AUDIT DEGRADED` systemMessage and a
   `DEGRADED-<date>.txt` breadcrumb is written; with `WALTER_AUDIT_STRICT=1` the
   same condition blocks. (two tests — gated on D3 sign-off.)
4. A genuine *block* decision still blocks regardless of audit-writer state.
   (test.)
5. Six concurrent appends for one tool event all succeed (no lock-timeout
   block). (test.)
6. `walter doctor --unblock` exits non-zero and prints the real report path +
   exact remediation commands when today's chain append fails OR the egress
   allowlist is missing OR a CRITICAL is unresolved; `--unblock --fix` clears the
   safe ones and a subsequent Bash call succeeds. (test.)
7. `daily-audit-gate.sh` block message points at `audit-status.json.report`, not
   a hardcoded `audit-${TODAY}.md`. (test.)
8. Existing hook bats suites (`network-gate`, `bash-denylist`, `approval-gate`,
   `capability-check`, `audit-chain-hook-integration`) still pass.

## Non-goals

- **Not** closing the MCP-bypass hole (Desktop Commander / filesystem MCP skip
  all gates). Separate P1 finding + spec.
- **Not** rewriting `audit-chain.sh` / `sandbox.sh` out of bash. Strategic, but
  not on the P0 recovery path.
- **Not** changing the Merkle/Rekor anchoring design
  (`audit-chain-merkle-and-receipts.md`) beyond moving the verify scope at
  append time.
- **Not** weakening any hard limit (auth/money/PHI/secrets/destructive). Those
  stay non-overridable and fail-closed.

## References

- `docs/specs/audit-chain-merkle-and-receipts.md` — chain design this consumes.
- `docs/specs/signed-audit-rows.plan.md` — where the per-row signing landed.
- `docs/specs/process-isolation-sandbox.md` (#122 A-3) — the sandbox layer.
- `docs/specs/network-egress-allowlist.md` — egress allowlist + import command.
- Live audit, 2026-06-10 (this session): root-cause walk + DoS reproduction.
