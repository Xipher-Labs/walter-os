# 0016. Hook checksums v2 — typed schema with content SHA256

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/audit-hook-content-hashing.md`
**Plan**: `docs/specs/audit-hook-content-hashing.plan.md`

## Context

External review 2026-05-21 surfaced a P0 BLOCKER: `audit.sh check_hooks` and `cmd_baseline_hooks` record the `.command` strings from `~/.claude/settings.json` but do NOT record the SHA256 of the script files those commands point at. The audit therefore detects "a hook was added/renamed/path-changed" but does NOT detect "`hooks/approval-gate.sh` was modified in place".

For a system where hooks ARE the security barrier — `approval-gate.sh` enforces the "blocked for ALL tiers" list, `bash-denylist.sh` blocks the destructive shell vectors, `branch-flow-guard.sh` blocks pushing to main, etc. — silent in-place modification is the most direct attack path. The current audit misses it entirely.

The fix needs a schema change: `hook-checksums.json` must store both the command string (existing behavior) AND a content SHA256 (new behavior). The question is HOW to migrate from the existing format (a flat array of strings) to a new format that carries the additional data.

We have an existing reference for the content-hashing pattern: `cmd_baseline_external_hooks` + `check_external_hooks` (audit P1-07, merged in PR #70). These already do per-file SHA256 hashing of `external/**/hooks/scripts/*` with portable GNU/BSD detection. The pattern is sound; we just haven't applied it to internal hooks.

## Decision

**Bump `hook-checksums.json` to a typed v2 schema with auto-migration on next `baseline-hooks` invocation.**

### v1 schema (current, to be deprecated)

```json
[
  "/abs/path/to/hook1.sh",
  "/abs/path/to/hook2.sh"
]
```

### v2 schema (this ADR)

```json
{
  "version": 2,
  "hooks": [
    {
      "command": "/abs/path/to/hook1.sh",
      "path": "/abs/path/to/hook1.sh",
      "sha256": "abc123...64chars"
    },
    {
      "command": "/abs/path/to/hook2.sh --arg",
      "path": "/abs/path/to/hook2.sh",
      "sha256": "def456..."
    }
  ]
}
```

- Top-level `version` key for forward-compatible bumps (v3 with Merkle root is in scope for OSS Trust epic #122).
- `command` is verbatim from settings.json (preserves the args, if any).
- `path` is the first whitespace-separated token of `command` (the executable). Empty if `command` is an inline shell expression.
- `sha256` is content hash of `path` (or empty if `path` is empty / unreadable).

### Migration semantics

- `walter-os baseline-hooks` against an existing v1 file: detects v1 via `jq 'type == "array"'`, logs an info-level "migrating to v2", writes v2.
- `audit.sh check_hooks` against an existing v1 file: emits an info-level finding "hook-checksums.json on legacy v1 schema, run `walter-os baseline-hooks` to migrate", falls back to v1 command-string-only comparison (no crash, no false-negative on the things v1 DID detect).
- First-run (no file): `check_hooks` calls into `cmd_baseline_hooks` to write v2 directly (skip the v1-then-migrate step).

### Drift severity matrix

| Comparison | Severity | Reasoning |
|---|---|---|
| New v2 entry added (commands grew) | high | Operator-added or attacker-added; needs review. Matches v1. |
| v2 entry removed (commands shrank) | medium | Less severe than added (attackers add capability, not remove). |
| `command` string changed | high | Path/args change = different hook semantics. Matches v1. |
| `path` unchanged, `sha256` changed | **crit** | The new case this ADR enables — in-place file modification. |
| `path` empty (inline command) — no SHA | info | Recorded for visibility; not gateable. |

## Why this approach

**Schema bump preserves audit history.** A typed object with `version: 2` is unambiguously distinguishable from v1's array via a single `jq` predicate. We don't need a parallel file or a separate version tag — the JSON type itself signals which schema.

**Auto-migration on next baseline keeps the workflow unchanged.** Operators don't need to learn a new command. The existing `walter-os baseline-hooks` is the natural moment to migrate (operator has already decided to refresh).

**Falls back gracefully on v1 files.** Until the operator runs `baseline-hooks`, the audit still works in v1 mode — just without the content check. This matches the principle "make the secure default available without forcing operator action; audit notices when defaults aren't current".

**Reuses the proven external-hook pattern.** `cmd_baseline_external_hooks` already solved GNU-vs-BSD `sha256sum` / `shasum` detection, empty-set handling, and deterministic JSON output. We copy the helpers; the only new logic is per-entry `(command, path, sha256)` triple construction.

**The version field future-proofs.** OSS Trust epic #122 (audit chain Merkle + signed receipts, issue #122 sub-item) will likely want a v3 schema with a top-level signed digest. v1 → v2 is one breaking schema bump; v2 → v3 will be another, easier because the version field already exists.

## Alternatives considered and rejected

### A) Keep v1 and add a parallel `hook-content-checksums.json` file

Two files: v1 stays as-is for command strings; new `hook-content-checksums.json` stores `{path: sha256}` for content.

**Rejected** because:
- Two files that must stay in sync = drift risk (one updated, the other not).
- Reviewer reading the audit code has to load two state files to understand a finding.
- The natural unit of "is this hook baseline current?" is a single record per hook — three columns (command, path, sha256) — not two parallel lookups.
- Doubles the surface for an attacker who can write to the operator's config dir (delete one file, get partial detection).

### B) Bump to v2 with hard-breaking format (no migration, manual operator action)

Ship v2; tell operators "run `walter-os baseline-hooks` after upgrade to migrate". If they don't, `check_hooks` errors loudly.

**Rejected** because:
- Hard-fail on existing installs is hostile: operator runs daily audit on Monday after pulling Friday's update, the audit blocks with "schema error, please re-baseline" — that's a session-blocker for a doc-only-feeling change.
- Soft auto-migration (the chosen approach) has zero operator cost and zero functional regression.

### C) Silent in-place migration on next `audit.sh check_hooks` (not via `baseline-hooks`)

Same as the chosen approach but the migration triggers during audit, not during baseline.

**Rejected** because:
- `audit.sh` is read-mostly. Having it auto-write the baseline file on first v1-encounter inverts the existing trust model where `audit.sh` reports state and `baseline-hooks` mutates it.
- Operator might run audit in a read-only context (CI job, sandboxed inspection) and a write-during-read is surprising.
- The migration is one operator command (`walter-os baseline-hooks`) — not worth bending the read-only invariant.

### D) Store SHA256 as a side-channel via Git LFS or signed receipt

For the OSS Trust epic (issue #122), checksums could go in a Merkle-tree + signed receipt file rather than plain JSON.

**Rejected for THIS scope** because:
- That's exactly issue #122's job (audit-chain-merkle-and-receipts). This ADR closes the immediate BLOCKER; the Merkle integration is a separate schema bump (v3) once the chain infrastructure lands.
- We don't want to block the BLOCKER fix on the larger epic landing.

### E) Use Git object hashes as the SHA source (let git compute the content hash)

`git hash-object <path>` would give a stable hash that matches what git itself sees.

**Rejected** because:
- The hooks may not be inside a git repo (e.g. a hand-installed `~/.claude/hooks/local-override.sh`). Git hash-object only works in a git context.
- SHA256 of file content is the universally portable approach.
- Git hash uses SHA-1 (or SHA-256 in newer repos with `--object-format=sha256`) and includes a `blob <size>\0` prefix — different from raw content SHA256, so a comparison against `sha256sum` output would not match.

## Consequences

**Positive:**

- Closes the F1 BLOCKER from external review 2026-05-21: in-place hook modification now detected at CRIT severity.
- Migration is silent + automatic on next `baseline-hooks`: operator pays zero adoption cost.
- v1 baseline files keep working in degraded mode (no crash, with an info-level prompt to migrate).
- Pattern matches existing external-hook content hashing — code reuse is clean.
- Forward-compatible: v3 with signed receipts can land on top without re-doing migration.

**Negative:**

- One-time CRIT spike possible on first audit run after migration IF the operator's local hooks were modified vs the canonical content (pre-existing tamper that current audit didn't detect). Documented in the CHANGELOG so operators know to expect it.
- Adds ~80 LOC across `audit.sh` + `bin/walter-os`. Doubles the per-hook record size in `hook-checksums.json` (still tiny — even with 50 hooks, < 10 KB).
- Schema-detection logic adds a `jq` call per audit run (negligible perf cost).

**Reversible:**

- Yes. Reverting the commits returns to v1 behavior. Operators with v2 baselines would see them ignored / treated as unknown schema on the reverted code; they could `walter-os baseline-hooks` to write back to v1. No data loss.

## Migration

1. PR lands the v2 schema + auto-migration + content-checking code.
2. `install.sh --upgrade` does not need to do anything special — next time the operator runs `walter-os baseline-hooks` (manually or via the daily audit gate), migration happens.
3. Existing operators see one-time `info` finding "legacy v1 schema, run baseline-hooks" until they migrate.
4. After migration, the v2 detection runs on every daily audit and any in-place hook modification is caught at CRIT.

## Open questions (non-blocking)

- **Q1**: should `cmd_baseline_hooks` print a diff between old + new baseline before writing? Proposed: yes (operator review before commit-to-baseline). Doesn't block the schema decision; just adds reviewer ergonomics.
- **Q2**: should the audit emit ONE CRIT per modified hook OR aggregate into a single CRIT listing all? Proposed: one CRIT per hook (each is a distinct security event).
- **Q3**: should the v2 record include a `last_seen` timestamp per hook? Proposed: no — adds state surface for no signal value (the baseline IS the "last seen acceptable" state; timestamping doubles the question).

## References

- External review 2026-05-21, finding F1 — source of this work
- Issue #115 — BLOCKER tracking
- Issue #122 — OSS Trust epic; this work is one leaf
- PR #70 (audit P1-07) — pattern reference for external-hook content hashing
- `skills/daily-supply-chain-audit/scripts/audit.sh` — implementation site
- `bin/walter-os` `cmd_baseline_hooks` + `cmd_baseline_external_hooks` — code reuse source
- ADR 0013 (solo-operator merge policy) — precedent for operator-configurable knobs with sane defaults
- ADR 0014 (CLI symlink path) — review-loop case study from the prior PR
- ADR 0015 (PR review severity gate, in flight as PR #114) — the framework that classified this as BLOCKER and motivated immediate action
