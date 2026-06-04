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

remove_acceptance_criteria() {
  local spec="$TMP_DIR/repo/docs/specs/example-feature.md"
  awk '
    /^## Acceptance criteria$/ { skip = 1; next }
    /^## Test plan$/ { skip = 0; print; next }
    !skip { print }
  ' "$spec" > "$spec.tmp"
  mv "$spec.tmp" "$spec"
}

replace_acceptance_criteria_with_weak_substrings() {
  local spec="$TMP_DIR/repo/docs/specs/example-feature.md"
  awk '
    /^## Acceptance criteria$/ {
      print
      print ""
      print "- [ ] AC-1: Make the latest dashboard nicer."
      print "- [ ] AC-2: Add a contest mode later."
      skip = 1
      next
    }
    skip && /^## Test plan$/ {
      skip = 0
      print ""
      print
      next
    }
    !skip { print }
  ' "$spec" > "$spec.tmp"
  mv "$spec.tmp" "$spec"
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
  remove_acceptance_criteria

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
  replace_acceptance_criteria_with_weak_substrings

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

@test "semantic-gates fails when architecture review section is empty" {
  cat > "$TMP_DIR/repo/docs/specs/example-feature.md" <<'MARKDOWN'
# Example feature - spec

## Problem

Operators need a readiness check.

## Non-goals

- Replacing human approval.

## Decisions

| Choice | Why |
|---|---|
| Use a CLI. | It is small. |

## Architecture review

## Acceptance criteria

- [ ] AC-1: Verify this exits 1 when review evidence is empty.

## Test plan

- `bats tests/cli/semantic-gates.bats`
MARKDOWN
  write_referencing_test

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"architecture-review: fail"* ]]
  [[ "$output" == *"missing reviewable decision/risk language"* ]]
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

@test "semantic-gates extracts uppercase acceptance criteria sections" {
  write_valid_spec
  write_referencing_test
  awk '{ if ($0 == "## Acceptance criteria") print "## ACCEPTANCE CRITERIA"; else print }' \
    "$TMP_DIR/repo/docs/specs/example-feature.md" \
    > "$TMP_DIR/repo/docs/specs/example-feature.md.tmp"
  mv "$TMP_DIR/repo/docs/specs/example-feature.md.tmp" \
    "$TMP_DIR/repo/docs/specs/example-feature.md"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ac-testability: pass"* ]]
}

@test "semantic-gates accepts numbered spec headings" {
  write_valid_spec
  write_referencing_test
  awk '
    {
      if ($0 == "## Non-goals") print "## 3. Non-goals"
      else if ($0 == "## Acceptance criteria") print "## 5. Acceptance criteria"
      else if ($0 == "## Test plan") print "## 6. Test plan"
      else print
    }
  ' "$TMP_DIR/repo/docs/specs/example-feature.md" \
    > "$TMP_DIR/repo/docs/specs/example-feature.md.tmp"
  mv "$TMP_DIR/repo/docs/specs/example-feature.md.tmp" \
    "$TMP_DIR/repo/docs/specs/example-feature.md"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"spec-completeness: pass"* ]]
  [[ "$output" == *"ac-testability: pass"* ]]
}

@test "semantic-gates rejects repo directories outside the spec path" {
  write_valid_spec
  write_referencing_test
  mkdir -p "$TMP_DIR/other-repo"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/other-repo"

  [ "$status" -eq 2 ]
  [[ "$output" == *"spec file must be inside repo directory"* ]]
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

@test "semantic-gates --json escapes tab and carriage return messages" {
  write_valid_spec
  write_referencing_test
  replace_acceptance_criteria_with_weak_substrings
  awk '
    /^## Test plan$/ {
      printf "- [ ] AC-3: Keep this\tweak\r\n\n"
      print
      next
    }
    { print }
  ' "$TMP_DIR/repo/docs/specs/example-feature.md" \
    > "$TMP_DIR/repo/docs/specs/example-feature.md.tmp"
  mv "$TMP_DIR/repo/docs/specs/example-feature.md.tmp" \
    "$TMP_DIR/repo/docs/specs/example-feature.md"

  run "$WALTER_OS_BIN" semantic-gates "$TMP_DIR/repo/docs/specs/example-feature.md" \
    --repo "$TMP_DIR/repo" --json

  [ "$status" -eq 1 ]
  jq -e '.status == "fail"' <<<"$output"
  jq -e 'any(.gates["ac-testability"].messages[]; contains("\t") or contains("\r"))' <<<"$output"
}
