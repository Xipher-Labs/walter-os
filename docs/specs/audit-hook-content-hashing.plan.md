# PLAN: Audit hook content hashing (F1 BLOCKER closure)

**Spec:** `docs/specs/audit-hook-content-hashing.md`
**ADR:** `docs/decisions/0016-hook-checksums-v2-schema.md`
**Branch:** `feature/audit-hook-content-hashing`
**Total tasks:** 12 (10 implementation + 2 verification).
**Estimated effort:** 3–4 hours, mostly because the pattern reference (`cmd_baseline_external_hooks` + `check_external_hooks`) does most of the heavy lifting already.

Each task follows RED-GREEN-REFACTOR per `test-driven-development` skill.

---

## Phase A — Test scaffolding (RED)

### A1. New bats test files

- `tests/audit/internal-hook-content-baseline.bats` (AC1, AC6)
- `tests/audit/internal-hook-content-drift.bats` (AC2, AC3, AC8, AC9, AC10)
- `tests/audit/internal-hook-checksums-migration.bats` (AC4, AC5)

Each file: shebang + REPO_ROOT discovery + 1 placeholder per AC. Use `mktemp` for sandboxed `$HOME` + `$CLAUDE_HOME` + `$WALTER_CONFIG`.

**Verify:** `bats --list tests/audit/internal-hook-*.bats` mentions all three.

### A2. Write failing tests

Per the AC mapping above. All tests reference functions that don't yet exist:
- `cmd_baseline_hooks` (already exists but emits v1, will be changed)
- `check_hooks` (already exists, will be enhanced)

Tests should fail with output like "v2 schema not detected" or "no CRIT emitted on content change".

**Verify:** all 10 ACs FAIL (RED).

---

## Phase B — Schema migration helper

### B1. Add `_hook_checksums_schema_version` helper to `bin/walter-os`

```bash
# Reads ${WALTER_CONFIG}/hook-checksums.json and returns the schema version
# detected: "v1" (array of strings), "v2" (object with .version=2), or "missing".
_hook_checksums_schema_version() {
  local file="${WALTER_CONFIG}/hook-checksums.json"
  [[ -f "$file" ]] || { echo "missing"; return; }
  if jq -e 'type == "object" and .version == 2' "$file" >/dev/null 2>&1; then
    echo "v2"
  elif jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
    echo "v1"
  else
    echo "unknown"  # corrupted or hand-edited; treat conservatively
  fi
}
```

**Verify:** unit-style test in `tests/audit/internal-hook-checksums-migration.bats` calls the helper with each schema variant.

### B2. Add `_hash_file` portable helper to `bin/walter-os`

Mirrors the GNU-vs-BSD detection from `cmd_baseline_external_hooks`:

```bash
_hash_file() {
  local file="$1"
  [[ -r "$file" ]] || { echo ""; return; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
  else
    echo ""
  fi
}
```

**Verify:** call with a known-content file, assert returns 64-char hex.

---

## Phase C — `cmd_baseline_hooks` v2

### C1. Rewrite `cmd_baseline_hooks`

```bash
cmd_baseline_hooks() {
  require_jq
  local settings="$CLAUDE_SETTINGS"
  [[ -f "$settings" ]] || { echo "settings missing" >&2; exit 2; }

  local prev_schema; prev_schema=$(_hook_checksums_schema_version)
  if [[ "$prev_schema" == "v1" ]]; then
    echo "info: migrating hook-checksums.json from v1 (string array) to v2 (typed object)"
  fi

  local hooks_json
  hooks_json=$(jq '[.hooks // {} | .. | objects | select(has("command"))]' "$settings")

  local result='{"version": 2, "hooks": []}'
  while IFS= read -r entry; do
    local cmd; cmd=$(jq -r '.command' <<<"$entry")
    local path; path=$(awk '{print $1}' <<<"$cmd")
    local sha=""
    if [[ -n "$path" && -f "$path" ]]; then
      sha=$(_hash_file "$path")
    fi
    result=$(jq --arg c "$cmd" --arg p "$path" --arg s "$sha" \
      '.hooks += [{command: $c, path: $p, sha256: $s}]' <<<"$result")
  done < <(jq -c '.[]' <<<"$hooks_json")

  local out="${WALTER_CONFIG}/hook-checksums.json"
  echo "$result" | jq --sort-keys '.' > "${out}.tmp" && mv "${out}.tmp" "$out"
  echo "✓ Hook checksums refreshed (v2): $out"
}
```

**Verify:** AC1, AC4, AC6 PASS.

---

## Phase D — `check_hooks` v2 detection

### D1. Update `check_hooks` in `audit.sh`

Handle both schema versions:
- v1 detected → emit `info` "legacy schema", fall back to current command-string-only comparison
- v2 detected → walk each entry: re-hash `path`, compare to stored `sha256`, emit `crit` on mismatch (per-entry detail)
- Missing → silent first-run snapshot (current behavior preserved, but write v2 schema directly)

Pseudocode:
```bash
check_hooks() {
  local settings="${CLAUDE_HOME}/settings.json"
  local checksums="${WALTER_CONFIG}/hook-checksums.json"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null 2>&1 || { finding high "no-jq" ...; return 0; }

  # First run: write v2 baseline silently
  if [[ ! -f "$checksums" ]]; then
    # Call into cmd_baseline_hooks via the CLI for code reuse, suppressing output
    walter-os baseline-hooks >/dev/null 2>&1
    return 0
  fi

  # Detect schema
  local schema
  if jq -e 'type == "object" and .version == 2' "$checksums" >/dev/null 2>&1; then
    schema=v2
  elif jq -e 'type == "array"' "$checksums" >/dev/null 2>&1; then
    schema=v1
    finding info "hook-checksums-v1-schema" \
      "hook-checksums.json on legacy v1 schema (command-strings only)" \
      "Run: walter-os baseline-hooks to migrate to v2 (content-hashing)"
    # Fall through to v1 string-array comparison (current behavior)
    _check_hooks_v1 "$settings" "$checksums"
    return 0
  else
    finding high "hook-checksums-corrupted" \
      "hook-checksums.json schema not recognized" \
      "Inspect manually then: walter-os baseline-hooks"
    return 0
  fi

  # v2: per-entry content check
  local current_baseline; current_baseline=$(jq '.hooks' "$checksums")
  while IFS= read -r entry; do
    local cmd path stored_sha
    cmd=$(jq -r '.command' <<<"$entry")
    path=$(jq -r '.path' <<<"$entry")
    stored_sha=$(jq -r '.sha256' <<<"$entry")
    if [[ -z "$path" ]]; then continue; fi  # inline command — already info-recorded
    if [[ ! -f "$path" ]]; then
      finding high "hook-file-missing" \
        "Hook file vanished or unreadable: $path (cmd: $cmd)" \
        "Restore from git OR baseline-hooks if intentional"
      continue
    fi
    local current_sha; current_sha=$(_hash_file "$path")
    if [[ "$current_sha" != "$stored_sha" ]]; then
      finding crit "hook-content-modified" \
        "Hook script CONTENT changed (path unchanged): $path. Stored sha: ${stored_sha:0:12}..., current sha: ${current_sha:0:12}..." \
        "REVIEW: git diff $path. If intentional: walter-os baseline-hooks"
    fi
  done < <(jq -c '.[]' <<<"$current_baseline")

  # Also detect command-string-level drift (added/removed)
  _check_hooks_command_drift "$settings" "$checksums"
}
```

Plus helpers `_check_hooks_v1` (old behavior) and `_check_hooks_command_drift` (the path-drift detection, same as v1 high finding).

**Verify:** AC2, AC3, AC5, AC8, AC9, AC10 PASS.

### D2. Cross-platform sanity

Run the bats tests with `PATH` shimmed to force `shasum` only (BSD path) AND with only `sha256sum` (GNU path). **Verify:** AC7 PASS on both.

---

## Phase E — Docs + ADR

### E1. ADR 0016

Already drafted as part of this Plan; finalize during implementation. Documents the schema migration decision + rejected alternatives:
- Alt A: keep v1 + extend with parallel content-checksums file (rejected: two files in sync = drift risk)
- Alt B: bump to v2 with breaking format (rejected: breaks existing operator baselines)
- Alt C: silent in-place migration on next baseline-hooks run (CHOSEN)

### E2. AGENTS.md update

The "daily-supply-chain-audit" section already lists what the audit checks. Add a line confirming content-hashing covers internal hooks (matches the existing external-hooks coverage). Single-line change.

### E3. CHANGELOG entry

Under unreleased:
```
### Security
- Audit hook checksums now hash script CONTENT, not just command paths.
  In-place modification of `hooks/approval-gate.sh` (or any registered
  hook) is now detected as CRIT severity. Closes external review F1
  / issue #115. Existing v1 hook-checksums.json files auto-migrate on
  next `walter-os baseline-hooks` run.
```

---

## Phase F — Verification

### F1. Full new test suite

```bash
bats tests/audit/internal-hook-content-baseline.bats
bats tests/audit/internal-hook-content-drift.bats
bats tests/audit/internal-hook-checksums-migration.bats
```

**Verify:** AC1-AC10 PASS.

### F2. Existing audit suite regression

```bash
bats tests/audit/
```

**Verify:** no regression on existing external-hook tests or other audit checks.

### F3. DoD validator + PR

- Run `definition-of-done-validator` against the spec.
- Open PR titled `[FIX] -SECURITY- audit hook checksums hash content not paths (closes #115)`.
- Request Copilot review per AGENTS.md.
- This PR cannot use auto-merge from #114's framework (the marker file doesn't exist on main yet, and the work touches `hooks/`/audit chain anyway — auto-escalation BLOCKER per the framework). Operator merges manually after review rounds.

---

## Out-of-plan items (file separately per spec §7)

- F1 (spec §7): schema v3 with signed baseline (Merkle root) — tied to issue #122 (OSS Trust epic)
- F2: `walter-os hook-restore` auto-restore from git
- F3: per-hook tamper-allowed policy

---

## Commit strategy

One commit per task (~12 commits). Conventional commit messages.

PR title: `[FIX] -SECURITY- audit hook checksums hash content not paths (closes #115)`
(matches `hooks/pr-title-validator.sh` convention.)
