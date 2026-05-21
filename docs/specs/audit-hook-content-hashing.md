# SPEC: Audit hook checksums hash CONTENT, not command paths (P0 BLOCKER)

**Status:** Draft (2026-05-21). Awaiting operator approval.
**Triggered by:** External review 2026-05-21 finding F1; tracked in issue #115. Operator labeled BLOCKER per Walter-OS severity-gate framework (PR #114) and instructed "lo cerraría esto antes de cualquier otra cosa".
**Related:** `skills/daily-supply-chain-audit/scripts/audit.sh` `check_hooks`, `bin/walter-os` `cmd_baseline_hooks`, audit P1-07 (PR #70) — the external-hook pattern this spec mirrors for internal hooks, ADR 0016.
**Rigor classification:** MAJOR (touches `skills/daily-supply-chain-audit/scripts/audit.sh` + `bin/walter-os`, both on auto-escalation paths; security barrier integrity is the function this work restores).

---

## 1. Problem

`audit.sh check_hooks` and `cmd_baseline_hooks` (the supply-chain detector for changes to Claude Code's hook configuration) store the `.command` STRINGS from `~/.claude/settings.json`. They do NOT store the SHA256 of the script file each command points to.

Result: the audit detects:
- A hook being ADDED to settings.json (the command-string array grows)
- A hook being REMOVED (the array shrinks)
- A hook's path being CHANGED (the string differs)

But the audit does NOT detect:
- An attacker modifying `hooks/approval-gate.sh` in place, keeping the same path
- An attacker modifying `hooks/bash-denylist.sh`, `hooks/branch-flow-guard.sh`, `hooks/pr-title-validator.sh`, `hooks/wiki-validator.sh`, or `hooks/daily-audit-gate.sh` in place

These hooks ARE the security barrier (`approval-gate.sh` enforces the "blocked for ALL tiers" list; `bash-denylist.sh` blocks `rm -rf /`, `git push --force`, `gh pr merge`, etc.). A silent in-place modification is the exact attack the daily supply-chain audit is supposed to detect, and it currently does not.

## 2. The curious asymmetry that proves this can be fixed cheaply

For `external/**/hooks/scripts/*` (operator's git-submodule paths), the audit DOES implement content-level SHA256 hashing + CRIT severity on drift. That work landed in PR #70 (audit P1-07). The pattern is already in the codebase:

- `cmd_baseline_external_hooks` (bin/walter-os ~line 269): writes `external-hook-checksums.json` as a `{path: sha256}` map using `find + xargs + sha256sum + jq`. Handles GNU vs BSD differences. Empty-set safe.
- `check_external_hooks` (audit.sh ~line 395): re-hashes the same paths, diffs against baseline, emits CRIT on mismatch.

This spec extends the same posture to the `~/.claude/settings.json`-registered internal hooks.

## 3. Goals

- **G1.** Detect in-place modification of any hook script referenced by `~/.claude/settings.json` (file content changed, path unchanged).
- **G2.** Preserve existing path-drift detection (added/removed/renamed hooks still fire HIGH).
- **G3.** Drift on content of a registered hook = **CRIT** severity (the most severe, since this is the security-barrier-tampering case).
- **G4.** Baseline migration: existing `hook-checksums.json` (current schema: JSON array of strings) auto-migrates to the new schema on first `baseline-hooks` run after this change ships, OR on first `check_hooks` run that finds old-format data.
- **G5.** Idempotency: `baseline-hooks` produces deterministic output (same input → same JSON, byte-for-byte).
- **G6.** Cross-platform: works on macOS (BSD `shasum`) AND Linux (`sha256sum`), exactly mirroring `cmd_baseline_external_hooks`.
- **G7.** No regression on the existing `check_hooks` HIGH detection for added/removed/renamed hooks.

## 4. Non-goals

- **NG1.** Not extending content-hashing to hook script DEPENDENCIES (a hook that sources another script — that's a deeper scope). The hook script itself is the unit of trust.
- **NG2.** Not signing the checksums (cryptographic signature of the baseline). That's part of `audit-chain-merkle-and-receipts` (issue #122) and out of scope here.
- **NG3.** Not auto-rolling-back drift. Detection emits CRIT; the operator decides remediation.
- **NG4.** Not adding new hooks to the matrix or changing what hooks fire — purely a detection / audit change.
- **NG5.** Not modifying `cmd_baseline_external_hooks` or `check_external_hooks` — pattern reference, do not touch.

## 5. Design (decisions locked, see ADR 0016)

### 5.1 Schema migration — `hook-checksums.json`

**Current schema (v1, to be deprecated):**
```json
[
  "/abs/path/to/hook1.sh",
  "/abs/path/to/hook2.sh"
]
```
A JSON array of command strings.

**New schema (v2):**
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

Top-level `version` key allows future schema bumps without re-doing migration logic.

`command` is the verbatim string from settings.json (may include CLI args).
`path` is the resolved file path (first whitespace-separated token of `command`, or empty for inline commands).
`sha256` is the content hash of `path`, or empty string when `path` is empty or the file is inaccessible.

### 5.2 Migration rule

On `baseline-hooks` invocation:
- If existing file matches v1 schema (`jq 'type == "array"'`) → log "migrating from v1 schema" and write v2.
- If existing file matches v2 schema → overwrite with current v2 content.
- If existing file missing → write v2 (first-run case).

On `check_hooks` invocation:
- If file matches v1 schema → emit `info` finding "hook-checksums.json on legacy v1 schema — run `walter-os baseline-hooks` to migrate", and skip content checks (fall back to current behavior of comparing command-strings only).
- If file matches v2 → compare current SHA256 of each `path` against stored value; emit `crit` on mismatch (per-entry detail).

### 5.3 Drift detection rules

| Comparison | Severity | Reasoning |
|---|---|---|
| New v2 entry added (commands grew) | high | Could be operator-added or attacker-added; needs review. (Matches current v1 high behavior.) |
| v2 entry removed (commands shrank) | medium | Less severe than added (attacker would add capability, not remove); flag for review. |
| `command` string changed | high | Path/args change = different hook semantics. (Matches current v1 high behavior.) |
| `path` unchanged, `sha256` changed | **crit** | The new case this spec closes — in-place file modification. |
| `path` empty (inline command) — no SHA to check | info | Recorded but not gateable; operator should avoid inline commands per AGENTS.md best practice |

### 5.4 Cross-platform implementation

Reuse `cmd_baseline_external_hooks`'s pattern:
- Detect `sha256sum` (GNU) or fallback to `shasum -a 256` (macOS BSD)
- Read each command-string's resolved path, content-hash it
- Output JSON via `jq --sort-keys` for deterministic output

### 5.5 Hash failures

If a resolved `path` is not a regular file (symlink to nothing, deleted file, permissions denied):
- `sha256` field = empty string
- A `check_hooks` run with empty sha256 in baseline AND empty sha256 currently = OK (no drift)
- A check with empty sha256 in baseline AND non-empty currently = high "hook restored / created" finding
- A check with non-empty sha256 in baseline AND empty currently = high "hook file missing or unreadable" finding

## 6. Acceptance criteria

Each gets at least one test (per AGENTS.md DoD rule).

- [ ] **AC1.** Sandbox a `settings.json` with hook command pointing at a temp script. `walter-os baseline-hooks` writes a v2 `hook-checksums.json` containing that hook's content SHA256. Tested via `tests/audit/internal-hook-content-baseline.bats`.
- [ ] **AC2.** Modify the temp script in place (same path, different content). `audit.sh check_hooks` (sourced directly for unit testing) emits a CRIT finding with stable ID `hook-content-modified`. Tested via `tests/audit/internal-hook-content-drift.bats`.
- [ ] **AC3.** Existing path-drift detection still fires HIGH when a new hook command is added or removed (no regression on current v1 behavior). Tested in the same file as AC2.
- [ ] **AC4.** v1 → v2 migration: `walter-os baseline-hooks` invoked against an existing v1 file (string array) writes a v2 file (object with version=2 + hooks array). Tested via `tests/audit/internal-hook-checksums-migration.bats`.
- [ ] **AC5.** Legacy detection: `audit.sh check_hooks` against a v1 file emits an `info` finding "legacy v1 schema — migrate via baseline-hooks" and gracefully falls back to v1 detection without crashing.
- [ ] **AC6.** Idempotency: two consecutive `walter-os baseline-hooks` runs against unchanged input produce byte-identical output files.
- [ ] **AC7.** Cross-platform: tests pass on both GNU `sha256sum` and BSD `shasum -a 256` paths. Tested via a shim that forces each path explicitly.
- [ ] **AC8.** Empty `path` (inline command in settings.json): baseline records empty sha256, audit emits info-level recording the inline command for visibility (not a finding-blocker).
- [ ] **AC9.** Missing file: baseline records empty sha256 + warns "path does not resolve to file". Audit emits high "hook file missing" if the baseline had a non-empty sha256.
- [ ] **AC10.** Permission denied: same as missing file (empty sha256, warning + audit-time high).
- [ ] **AC11.** AGENTS.md "daily-supply-chain-audit" reference updated to document content-hashing for internal hooks (mirroring the existing external-hook note).
- [ ] **AC12.** ADR 0016 documents the schema migration design choice with rejected alternatives.

## 7. Out-of-scope follow-ups (file separately)

- **F1.** Schema v3: signed baseline (Merkle root from `audit-chain-merkle-and-receipts` issue #122) — extends but does not block this work.
- **F2.** Auto-restore: a `walter-os hook-restore <name>` that fetches the canonical content from the walter-os repo (git blob lookup at the pinned commit) and rewrites the local hook file. Defensive but adds attack surface (auto-rewrite of security barriers).
- **F3.** Per-hook policy: declare some hooks as "tamper-allowed" (operator might want to customize) — current scope: every hook in settings.json is tamper-protected.

## 8. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| v1 baseline accidentally truncated during migration | Low | Med | Migration writes to `mktemp + mv`. Failure leaves v1 file intact. |
| New schema breaks downstream consumer | Low | Low | Only walter-os internals consume hook-checksums.json. Grep confirms no external consumers. |
| BSD `shasum` output format differs from GNU on edge cases | Low | Low | Pattern already used in `cmd_baseline_external_hooks` — same regex `^(?<hash>[0-9a-f]{64})[[:space:]]+\*?(?<path>.+)$` |
| Hash mismatch on Sunday morning false-alarm | Med | Low | CRIT severity surfaces it; operator can run `walter-os baseline-hooks` to re-baseline after legitimate edit. AGENTS.md already documents this workflow for external hooks. |
| First-time CRIT spam if operator's hooks were modified before this lands | Med | Low | One-time spike on first run after migration. Documented in CHANGELOG entry. |

## 9. Open questions for operator

- Q1: should v1 → v2 migration prompt the operator for confirmation, OR auto-migrate silently on `baseline-hooks`? Proposed: auto-migrate silently with `info`-level log entry. (Operator who runs `baseline-hooks` has implicit intent to refresh.)
- Q2: should the audit emit one CRIT per modified hook, or aggregate into one CRIT listing all modified hooks? Proposed: one CRIT per hook (each is a distinct security event; aggregate would hide the count).
- Q3: should `cmd_baseline_hooks` print a diff of what changed vs the previous baseline? Proposed: yes — operator visibility before they commit to the new baseline. Format: human-readable list of (hook, old_sha, new_sha).

## 10. References

- External review F1 — 2026-05-21 (the source finding)
- Issue #115 — tracking
- Issue #122 — OSS Trust epic; this work is a leaf of that
- audit P1-07 / PR #70 — pattern reference (external hook content hashing)
- `skills/daily-supply-chain-audit/scripts/audit.sh` `check_hooks` (line ~107) — implementation site
- `skills/daily-supply-chain-audit/scripts/audit.sh` `check_external_hooks` (line ~395) — pattern reference
- `bin/walter-os` `cmd_baseline_hooks` (line ~254) — CLI site
- `bin/walter-os` `cmd_baseline_external_hooks` (line ~269) — pattern reference
- AGENTS.md "daily-supply-chain-audit" reference — promise to be honored
