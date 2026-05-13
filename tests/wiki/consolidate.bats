#!/usr/bin/env bats
# Tests for T-15: scripts/wiki/consolidate.sh
# Covers: AC-1, AC-2 of Improvement 3

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/wiki/consolidate.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures/wiki-test"
  [[ -f "$SCRIPT" ]] || skip "consolidate.sh not found"

  WORK_DIR="$(mktemp -d -t wiki-consolidate-XXXXXX)"
  cp -r "$FIXTURES"/. "$WORK_DIR"/

  REPORT_DIR="$(mktemp -d -t wiki-consolidate-report-XXXXXX)"
  export WIKI_CONSOLIDATE_REPORT="$REPORT_DIR/wiki-consolidation.json"
  export WIKI_CONSOLIDATE_LOG="$REPORT_DIR/wiki-consolidation.log"
  # Disable LiteLLM calls in tests
  export _LESSONS_MOCK_EMBED=1
  export LITELLM_BASE_URL=""
  # Disable Plane issue creation in tests (dry-run mode)
  export WIKI_CONSOLIDATE_DRY_RUN=1
}

teardown() {
  rm -rf "$WORK_DIR" "$REPORT_DIR"
}

@test "consolidate.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "consolidate.sh exits 0 on a valid wiki dir" {
  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]
}

@test "consolidate.sh generates a JSON report" {
  run bash "$SCRIPT" "$WORK_DIR"
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]
}

@test "consolidate.sh JSON report has candidates array" {
  run bash "$SCRIPT" "$WORK_DIR"
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]
  python3 -c "
import json
with open('$WIKI_CONSOLIDATE_REPORT') as f:
    data = json.load(f)
assert 'candidates' in data or isinstance(data, list), 'Missing candidates key'
" 2>/dev/null
}

@test "consolidate.sh produces output to stdout in dry-run mode" {
  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]
  # Should output something (even if empty candidates)
  [ -n "$output" ] || [ -f "$WIKI_CONSOLIDATE_REPORT" ]
}

@test "consolidate.sh completes in reasonable time" {
  local start end elapsed
  start="$(date +%s)"
  run bash "$SCRIPT" "$WORK_DIR"
  end="$(date +%s)"
  elapsed=$(( end - start ))
  # Should complete in under 60 seconds for 5 fixture files
  [ "$elapsed" -lt 60 ]
}

# --------------- Fix 8: Contradiction detection ---------------

@test "consolidate.sh report has contradictions key when LLM enabled" {
  # Copy contradiction fixture pages into work dir
  cp "$BATS_TEST_DIRNAME/../fixtures/wiki-test/tx-limit-a.md" "$WORK_DIR/"
  cp "$BATS_TEST_DIRNAME/../fixtures/wiki-test/tx-limit-b.md" "$WORK_DIR/"

  # Use mock LLM that returns YES for contradicting pages
  export WIKI_CONSOLIDATE_LLM_CMD="$BATS_TEST_DIRNAME/../fixtures/mock-llm-contradiction.sh"
  # Set similarity threshold above 1.0 (impossible with cosine) so no pages are dupes,
  # and all similar pairs fall into the contradiction window [0.0, 1.1).
  export WIKI_CONSOLIDATE_SIMILARITY_THRESHOLD="1.1"
  export WIKI_CONSOLIDATE_CONTRADICTION_THRESHOLD="0.0"

  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]
  # Report should have contradictions key
  python3 -c "
import json
with open('$WIKI_CONSOLIDATE_REPORT') as f:
    data = json.load(f)
assert 'contradictions' in data, f'Missing contradictions key. Keys: {list(data.keys())}'
" 2>/dev/null
}

@test "consolidate.sh contradiction section lists contradicting pages" {
  # Use a clean dir with ONLY the two contradicting pages (avoid other fixtures
  # filling the top-10 pairs and pushing the target pair out of scope)
  local CONTRA_DIR
  CONTRA_DIR="$(mktemp -d -t wiki-contra-XXXXXX)"
  cp "$BATS_TEST_DIRNAME/../fixtures/wiki-test/tx-limit-a.md" "$CONTRA_DIR/"
  cp "$BATS_TEST_DIRNAME/../fixtures/wiki-test/tx-limit-b.md" "$CONTRA_DIR/"

  export WIKI_CONSOLIDATE_LLM_CMD="$BATS_TEST_DIRNAME/../fixtures/mock-llm-contradiction.sh"
  # Set similarity threshold above 1.0 so all pairs are in contradiction window
  export WIKI_CONSOLIDATE_SIMILARITY_THRESHOLD="1.1"
  export WIKI_CONSOLIDATE_CONTRADICTION_THRESHOLD="0.0"

  run bash "$SCRIPT" "$CONTRA_DIR"
  rm -rf "$CONTRA_DIR"
  [ "$status" -eq 0 ]
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]

  python3 -c "
import json
with open('$WIKI_CONSOLIDATE_REPORT') as f:
    data = json.load(f)
contradictions = data.get('contradictions', [])
# With mock LLM returning YES for 1232 vs 1644 pages, we expect at least 1 entry
assert len(contradictions) >= 1, f'Expected >= 1 contradiction, got {contradictions}'
" 2>/dev/null
}

@test "consolidate.sh with no LLM cmd emits empty contradictions array" {
  unset WIKI_CONSOLIDATE_LLM_CMD 2>/dev/null || true
  run bash "$SCRIPT" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]
  python3 -c "
import json
with open('$WIKI_CONSOLIDATE_REPORT') as f:
    data = json.load(f)
# Without LLM, contradictions key should exist (empty array)
assert 'contradictions' in data, 'Missing contradictions key'
" 2>/dev/null
}

@test "consolidate.sh: page with triple-quote in name does not inject into python" {
  # RED: a page_a/page_b path containing ''' must not cause python code injection.
  # The fix: all variable data must pass via env vars or tmp files, NOT interpolated.
  # Verify the fix is present: no raw '''${var}''' interpolation in the contradiction path.
  # The specific patterns that caused the bug:
  ! grep -q "json.loads('''\${" "$SCRIPT"
}

@test "consolidate.sh: candidates_json count uses env-var path not triple-quote" {
  # The num_cands line must NOT use python3 -c with triple-quote interpolation.
  # It should either: write to tmpfile then read, or use PYEOF heredoc.
  ! grep -q "json.loads('''\${candidates_json}" "$SCRIPT"
}

# ---- M7: contradiction_items must be declared before set -u access ----

@test "M17: stale_items JSON valid when filepath contains double-quote" {
  # M17: stale_items uses printf '{"path":"%s",...}' "$filepath" — a filepath
  # containing " breaks the JSON. Fix: use jq or python3 for safe construction.
  local STALE_DIR
  STALE_DIR="$(mktemp -d -t wiki-stale-m17-XXXXXX)"
  # Create a wiki page with a double-quote in the filename
  mkdir -p "$STALE_DIR"
  local bad_name='say "hello".md'
  local bad_path="$STALE_DIR/$bad_name"
  printf -- '---\ntype: note\ntitle: Bad\ncreated: 2020-01-01\ntags: []\n---\nBody.\n' > "$bad_path"

  # Make git think the file is very old (use a temp git repo)
  git -C "$STALE_DIR" init -q 2>/dev/null || true
  git -C "$STALE_DIR" config user.email "test@test.com" 2>/dev/null || true
  git -C "$STALE_DIR" config user.name "Test" 2>/dev/null || true

  export WIKI_CONSOLIDATE_STALE_DAYS=0
  export _LESSONS_MOCK_EMBED=0
  export WIKI_CONSOLIDATE_DRY_RUN=1
  unset WIKI_CONSOLIDATE_LLM_CMD 2>/dev/null || true

  run bash "$SCRIPT" "$STALE_DIR"
  rm -rf "$STALE_DIR"

  [ "$status" -eq 0 ]
  [ -f "$WIKI_CONSOLIDATE_REPORT" ]
  # The JSON report must be parseable — stale_pages must not be broken
  python3 -c "
import json
with open('$WIKI_CONSOLIDATE_REPORT') as f:
    data = json.load(f)
# stale_pages must be a valid array (even if empty due to no-inbound-links check)
assert isinstance(data.get('stale_pages', []), list), 'stale_pages must be a list'
" 2>&1
}

@test "consolidate.sh does not fail with set -u when embed available but no pairs (M7)" {
  # Bug: contradiction_items is declared inside if [[ -s tmp_embed2 ]] but
  # accessed OUTSIDE that if — when no pages produce embeddings, tmp_embed2
  # is empty, the if branch is skipped, contradiction_items is unbound, and
  # bash -u causes an error.
  # We force this path by:
  #   1. Setting WIKI_LLM_CMD to a mock (so the outer if condition is true)
  #   2. Using an empty dir (no pages → no embeds → tmp_embed2 empty → if skipped)
  local EMPTY_DIR
  EMPTY_DIR="$(mktemp -d -t wiki-empty-m7-XXXXXX)"
  local MOCK_LLM
  MOCK_LLM="$(mktemp)"
  printf '#!/usr/bin/env bash\necho "NO"\n' > "$MOCK_LLM"
  chmod +x "$MOCK_LLM"
  export WIKI_CONSOLIDATE_LLM_CMD="$MOCK_LLM"
  export _LESSONS_MOCK_EMBED=1  # enable embedding path
  run bash "$SCRIPT" "$EMPTY_DIR"
  rm -rf "$EMPTY_DIR"
  rm -f "$MOCK_LLM"
  # Must not fail with "unbound variable"
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ "unbound variable" ]]
  ! [[ "$output" =~ "contradiction_items" ]]
}
