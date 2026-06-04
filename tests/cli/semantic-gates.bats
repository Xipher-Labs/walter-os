#!/usr/bin/env bats
# tests/cli/semantic-gates.bats
#
# Covers: issue #229 / AD-4 - semantic gates for specs, acceptance
# criteria, architecture review evidence, and test relevance.
# Refs: docs/specs/semantic-gates.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_DIR="$(mktemp -d)"
  export HOME="$TMP_DIR/home"
  export WALTER_CONFIG="$TMP_DIR/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$HOME" "$WALTER_CONFIG" "$TMP_DIR/repo/docs/specs" "$TMP_DIR/repo/tests/cli"
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || exit
  case "$TMP_DIR" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_DIR" ;;
  esac
  true
}

write_valid_spec() {
  cat > "$TMP_DIR/repo/docs/specs/example-feature.md" <<'MARKDOWN'
# Example feature - spec

## Problem

Operators need a reliable way to know whether generated specs are ready for
implementation.

## Non-goals

- Replacing human architecture approval.

## Decisions

| Decision | Rationale |
|---|---|
| Keep gates advisory until wired into review automation. | This preserves the hard safety floor. |

## Architecture review

The implementation must be reviewed against the repo-config autonomy contract
and must not relax approval-gate hard limits.

## Acceptance criteria

- [ ] AC-1: `walter-os semantic-gates` exits 0 for a complete spec and referenced tests.
- [ ] AC-2: Bats coverage verifies missing test references fail closed.

## Test plan

- `bats tests/cli/semantic-gates.bats`

## Refs

- Issue #229
- docs/specs/autonomous-delivery-roadmap.md AD-4
MARKDOWN
}

write_referencing_test() {
  cat > "$TMP_DIR/repo/tests/cli/example-feature.bats" <<'BATS'
#!/usr/bin/env bats
# Refs: docs/specs/example-feature.md

@test "AC-1: example feature has test evidence" {
  true
}
BATS
}

@test "semantic-gates passes a complete spec with referenced tests" {
  write_valid_spec
  write_referencing_test

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"semantic-gates: pass"* ]]
  [[ "$output" == *"spec-completeness: pass"* ]]
  [[ "$output" == *"ac-testability: pass"* ]]
  [[ "$output" == *"architecture-review: pass"* ]]
  [[ "$output" == *"test-relevance: pass"* ]]
}

@test "semantic-gates fails when acceptance criteria are missing" {
  write_valid_spec
  write_referencing_test
  perl -0pi -e 's/## Acceptance criteria.*?## Test plan/## Test plan/s' \
    "$TMP_DIR/repo/docs/specs/example-feature.md"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"semantic-gates: fail"* ]]
  [[ "$output" == *"spec-completeness: fail"* ]]
  [[ "$output" == *"missing acceptance criteria section"* ]]
}

@test "semantic-gates fails when AC bullets are not testable" {
  write_valid_spec
  write_referencing_test
  perl -0pi -e 's/(## Acceptance criteria\n\n).*?(\n\n## Test plan)/$1- [ ] AC-1: Make the latest dashboard nicer.\n- [ ] AC-2: Add a contest mode later.$2/s' \
    "$TMP_DIR/repo/docs/specs/example-feature.md"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ac-testability: fail"* ]]
  [[ "$output" == *"AC bullets must include observable verification language"* ]]
}

@test "semantic-gates fails when no tests reference the spec" {
  write_valid_spec

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test-relevance: fail"* ]]
  [[ "$output" == *"no test file references docs/specs/example-feature.md"* ]]
}

@test "semantic-gates accepts non-shell test files that reference the spec" {
  write_valid_spec
  cat > "$TMP_DIR/repo/tests/cli/example_feature_test.go" <<'GO'
package example

// Refs: docs/specs/example-feature.md
func TestExampleFeature(t *testing.T) {}
GO

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"test-relevance: pass"* ]]
  [[ "$output" == *"tests/cli/example_feature_test.go"* ]]
}

@test "semantic-gates --json emits machine-readable gate results" {
  write_valid_spec
  write_referencing_test

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo" --json

  [ "$status" -eq 0 ]
  jq -e '.status == "pass"' <<<"$output"
  jq -e '.gates["spec-completeness"].status == "pass"' <<<"$output"
  jq -e '.gates["test-relevance"].evidence[0] | contains("tests/cli/example-feature.bats")' <<<"$output"
}
