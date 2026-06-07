# Audit Chain Loki Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `walter-os audit verify-chain --from-loki` so operators can verify Loki-shipped audit-chain rows without requiring a live Loki instance in tests.

**Architecture:** Reuse the existing canonical local verifier by materializing Loki-returned JSONL lines into a temporary audit directory and verifying them with the same hash/root checks. The CLI accepts a real Loki URL/range path later, but this first slice ships the safe testable foundation through a `--mock-loki <fixture>` JSON response fixture.

**Tech Stack:** Bash, `jq`, Bats, existing `scripts/walter/lib/audit-chain.sh`, existing `bin/walter-os` audit dispatcher.

---

## Files

- Modify: `scripts/walter/lib/audit-chain.sh`
  - Add `walter_audit_verify_chain_from_loki_fixture <fixture> [date]`.
  - Parse Loki `/loki/api/v1/query_range`-style fixture JSON.
  - Extract stream values, sort by timestamp, write canonical JSONL lines to a temp audit dir, write the root from the last line, and call `walter_audit_verify_chain`.
- Modify: `bin/walter-os`
  - Dispatch `walter-os audit verify-chain --from-loki --mock-loki <fixture> [date]`.
  - Print actionable usage errors for unsupported live Loki mode in this slice.
- Add: `tests/walter/audit-chain-verify-from-loki.bats`
  - Fixture-backed tests for clean verification, tampered row failure, malformed fixture failure, and CLI usage errors.
- Modify: `CHANGELOG.md`
  - Add `[Unreleased]` security/observability note.

## Task 1: RED Tests For Loki Fixture Verification

- [ ] **Step 1: Add failing Bats coverage**

Create `tests/walter/audit-chain-verify-from-loki.bats` with:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AUDIT_LIB="$REPO_ROOT/scripts/walter/lib/audit-chain.sh"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-audit-loki.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_AUDIT_DATE="2026-06-04"
  export WALTER_AUDIT_NOW="2026-06-04T12:00:00Z"
  export WALTER_SESSION_ID="session-loki"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$WALTER_CONFIG"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-audit-loki.*) rm -rf "$TMP_HOME" ;;
  esac
}

_chain_path() {
  printf '%s/audit/chain-2026-06-04.jsonl\n' "$WALTER_CONFIG"
}

_fixture_path() {
  printf '%s/loki-response.json\n' "$TMP_HOME"
}

_make_chain() {
  bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'cat README.md' allow approval-gate ok >/dev/null"
  WALTER_AUDIT_NOW="2026-06-04T12:00:01Z" \
    bash -c "source '$AUDIT_LIB'; walter_audit_append Bash 'rm -rf /tmp/nope' block bash-denylist destructive >/dev/null"
}

_make_loki_fixture() {
  jq -Rs 'split("\n") | map(select(length > 0)) | to_entries | {
    status: "success",
    data: {
      resultType: "streams",
      result: [
        {
          stream: {app: "walter-os", kind: "audit-chain"},
          values: (map([((1000000000 + .key) | tostring), .value]))
        }
      ]
    }
  }' "$(_chain_path)" > "$(_fixture_path)"
}

@test "verify-chain --from-loki verifies a Loki query_range fixture" {
  _make_chain
  _make_loki_fixture

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: verified 2 row(s)"* ]]
  [[ "$output" == *"from Loki fixture"* ]]
}

@test "verify-chain --from-loki detects tampered fixture rows" {
  _make_chain
  _make_loki_fixture
  jq '.data.result[0].values[1][1] |= sub("destructive"; "tampered")' \
    "$(_fixture_path)" > "$TMP_HOME/tampered.json" && mv "$TMP_HOME/tampered.json" "$(_fixture_path)"

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"row 2: row_hash mismatch"* ]]
}

@test "verify-chain --from-loki rejects malformed Loki fixtures" {
  printf '{"status":"success","data":{"result":[]}}\n' > "$(_fixture_path)"

  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki --mock-loki "$(_fixture_path)" 2026-06-04

  [ "$status" -eq 1 ]
  [[ "$output" == *"no audit-chain rows found"* ]]
}

@test "verify-chain --from-loki requires mock fixture until live Loki is implemented" {
  run bash "$WALTER_OS_BIN" audit verify-chain --from-loki 2026-06-04

  [ "$status" -eq 2 ]
  [[ "$output" == *"--mock-loki <fixture>"* ]]
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
bats tests/walter/audit-chain-verify-from-loki.bats
```

Expected: FAIL because `--from-loki` is not implemented.

## Task 2: GREEN Library Implementation

- [ ] **Step 1: Add minimal fixture verifier**

Modify `scripts/walter/lib/audit-chain.sh` to add:

```bash
walter_audit_verify_chain_from_loki_fixture() {
  local fixture="$1" date_value="${2:-$(walter_audit_date)}"
  local tmp_config tmp_audit values_count previous_config status

  if [[ ! -f "$fixture" ]]; then
    echo "walter-audit-chain: Loki fixture not found: $fixture" >&2
    return 1
  fi
  if ! _walter_audit_jq_available; then
    echo "walter-audit-chain: jq required" >&2
    return 3
  fi

  tmp_config="$(mktemp -d "${TMPDIR:-/tmp}/walter-audit-loki.XXXXXX")" || return 1
  tmp_audit="${tmp_config}/audit"
  mkdir -p "$tmp_audit" || {
    rm -rf "$tmp_config"
    return 1
  }

  values_count="$(jq '[.data.result[]?.values[]?] | length' "$fixture" 2>/dev/null)" || {
    rm -rf "$tmp_config"
    echo "walter-audit-chain: invalid Loki fixture JSON: $fixture" >&2
    return 1
  }
  if [[ "$values_count" -eq 0 ]]; then
    rm -rf "$tmp_config"
    echo "walter-audit-chain: no audit-chain rows found in Loki fixture: $fixture" >&2
    return 1
  fi

  jq -r '[.data.result[]?.values[]?] | sort_by(.[0] | tonumber) | .[][1]' \
    "$fixture" > "${tmp_audit}/chain-${date_value}.jsonl" || {
      rm -rf "$tmp_config"
      echo "walter-audit-chain: failed to extract Loki fixture rows: $fixture" >&2
      return 1
    }
  if [[ ! -s "${tmp_audit}/chain-${date_value}.jsonl" ]]; then
    rm -rf "$tmp_config"
    echo "walter-audit-chain: no audit-chain rows found in Loki fixture: $fixture" >&2
    return 1
  fi

  local previous_line root_hash
  previous_line="$(tail -n 1 "${tmp_audit}/chain-${date_value}.jsonl")"
  root_hash="$(walter_audit_hash_string "$previous_line")"
  printf '%s' "$root_hash" > "${tmp_audit}/root-${date_value}.txt"

  previous_config="${WALTER_CONFIG:-}"
  WALTER_CONFIG="$tmp_config" walter_audit_verify_chain "$date_value"
  status="$?"
  if [[ -n "$previous_config" ]]; then
    WALTER_CONFIG="$previous_config"
  else
    unset WALTER_CONFIG
  fi
  rm -rf "$tmp_config"
  [[ "$status" -eq 0 ]] || return "$status"
  printf 'ok: verified from Loki fixture: %s\n' "$fixture"
}
```

- [ ] **Step 2: Wire `bin/walter-os` dispatch**

In `cmd_audit`, parse `verify-chain --from-loki --mock-loki <fixture> [date]` and call the new function. Unsupported live Loki mode exits 2 with a usage message.

- [ ] **Step 3: Run tests and verify GREEN**

Run:

```bash
bats tests/walter/audit-chain-verify-from-loki.bats tests/walter/audit-chain-verify.bats
```

Expected: PASS.

## Task 3: Docs And Final Verification

- [ ] **Step 1: Add CHANGELOG note**

Add one `[Unreleased]` bullet under security/observability:

```markdown
- Added fixture-backed `walter-os audit verify-chain --from-loki --mock-loki` verification for Loki-shipped audit-chain rows.
```

- [ ] **Step 2: Run final checks**

Run:

```bash
bats tests/walter/audit-chain-verify-from-loki.bats tests/walter/audit-chain-verify.bats tests/agents/audit-telemetry-dashboard.bats
bash -n bin/walter-os scripts/walter/lib/audit-chain.sh
shellcheck -e SC1091,SC2155 bin/walter-os scripts/walter/lib/audit-chain.sh
git diff --check
```

Expected: all pass.

- [ ] **Step 3: Commit and PR**

Commit:

```bash
git add CHANGELOG.md bin/walter-os scripts/walter/lib/audit-chain.sh tests/walter/audit-chain-verify-from-loki.bats docs/superpowers/plans/2026-06-04-audit-chain-loki-verify.md
git commit -m "feat: verify audit chains from Loki fixtures"
```

Open PR title:

```text
[FEAT] -SECURITY- verify audit chains from Loki fixtures
```

PR body must reference `Refs #122` and note this is B-3 AC-3 fixture-backed foundation, not live Loki querying.

## Self-Review

- Spec coverage: covers audit telemetry AC-3 verification path in a fixture-backed first slice. Live Loki network querying remains explicitly out of scope for this PR.
- Placeholder scan: no `TBD`, no unresolved implementation placeholders.
- Type consistency: CLI flag names are `--from-loki` and `--mock-loki`, matching tests and implementation tasks.
