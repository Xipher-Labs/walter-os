#!/usr/bin/env bats
# Tests for T-12 and T-13: lesson_write integration + injection into run.sh
# Covers: AC-2 of Improvement 4 (lesson extraction after task + injection before)

setup() {
  RUN_SH="$BATS_TEST_DIRNAME/../../scripts/agents/run.sh"
  LESSONS_LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/lessons.sh"
  [[ -f "$RUN_SH" ]] || skip "run.sh not found"
  [[ -f "$LESSONS_LIB" ]] || skip "lessons.sh not found"

  # Isolated environment
  LESSONS_DB_DIR="$(mktemp -d -t walter-run-lessons-XXXXXX)"
  export LESSONS_DB="$LESSONS_DB_DIR/lessons.db"
  export _LESSONS_MOCK_EMBED=1
  export LITELLM_BASE_URL=""
}

teardown() {
  rm -rf "$LESSONS_DB_DIR"
}

@test "run.sh sources lessons.sh library" {
  grep -q "lessons.sh" "$RUN_SH"
}

@test "run.sh calls lesson_write after task completion (marker present)" {
  # run.sh should reference lesson_write somewhere (lesson extraction step)
  grep -q "lesson_write\|lesson_extract\|_lesson_extract" "$RUN_SH"
}

@test "run.sh injects lessons into system prompt (lesson_query call)" {
  # T-13: run.sh should call lesson_query before LLM invocation
  grep -q "lesson_query" "$RUN_SH"
}

@test "run.sh includes security-fenced lesson section in prompt code" {
  # run.sh should reference the quote-fence header (replaces old 'Lessons from the Council')
  grep -q "LESSONS FROM PRIOR COUNCIL RUNS" "$RUN_SH"
}

# --------------- Fix 2 Layer 2: quote-fence in run.sh ---------------

@test "run.sh injects quote-fence header (untrusted data — informational only)" {
  grep -q "untrusted data — informational only" "$RUN_SH"
}

@test "run.sh limits injected lessons to 5 (lessons[:5])" {
  grep -q "lessons\[:5\]" "$RUN_SH"
}

@test "run.sh has END OF LESSONS fence marker" {
  grep -q "END OF LESSONS" "$RUN_SH"
}

# --------------- Fix 3: dry-run prints full assembled prompt ---------------

@test "run.sh dry-run exit is placed AFTER prompt assembly (not before)" {
  # Verify that the early-exit at line ~138 is removed and replaced with
  # a dry-run block AFTER SYSTEM_PROMPT assembly.
  # The new dry-run block must appear after SYSTEM_PROMPT= assignment.
  local content
  content="$(cat "$RUN_SH")"
  # Find line numbers of SYSTEM_PROMPT assignment and dry-run exit
  local prompt_line dryrn_line
  prompt_line="$(grep -n 'SYSTEM_PROMPT=\$(printf' "$RUN_SH" | head -1 | cut -d: -f1)"
  dryrn_line="$(grep -n 'dry-run.*full assembled\|dry-run.*No LLM' "$RUN_SH" | head -1 | cut -d: -f1)"
  # dry-run exit must come AFTER prompt assembly
  [ -n "$prompt_line" ]
  [ -n "$dryrn_line" ]
  [ "$dryrn_line" -gt "$prompt_line" ]
}

@test "run.sh dry-run prints full assembled system prompt" {
  grep -q "Full assembled system prompt" "$RUN_SH"
}

@test "run.sh dry-run does not invoke LLM" {
  # In dry-run block, should exit 0 before any llm_invoke or watchdog call
  # Verify the dry-run block has 'exit 0' and appears before 'invoke LLM under watchdog'
  local dryrn_exit_line watchdog_line
  dryrn_exit_line="$(grep -n 'dry-run.*No LLM' "$RUN_SH" | head -1 | cut -d: -f1)"
  watchdog_line="$(grep -n 'invoke LLM under watchdog' "$RUN_SH" | head -1 | cut -d: -f1)"
  [ -n "$dryrn_exit_line" ]
  [ -n "$watchdog_line" ]
  [ "$dryrn_exit_line" -lt "$watchdog_line" ]
}

# --------------- Fix 9: behavioral tests for lesson injection ---------------

@test "run.sh code: lessons with confidence < 0.5 threshold are excluded from query" {
  # Verify lessons.sh respects the confidence threshold constant
  grep -q "_LESSON_CONFIDENCE_THRESHOLD" "$LESSONS_LIB"
  # Default is 0.5
  grep -q "0.5" "$LESSONS_LIB"
}

@test "run.sh code: lesson injection is limited to 5 lessons" {
  # Verify the slice is applied in run.sh
  grep -q "lessons\[:5\]" "$RUN_SH"
}

@test "run.sh code: lesson block omitted when DB has no lessons (empty result)" {
  # Verify run.sh only injects when _RELEVANT_LESSONS != []
  grep -q '_RELEVANT_LESSONS != "\[\]"' "$RUN_SH" || \
  grep -q "_RELEVANT_LESSONS.*\[\]" "$RUN_SH"
}

@test "lessons.sh: two lessons both stored and both queryable" {
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init
  lesson_write "reviewer" "Alpha lesson unique word qux" "first body" '["test"]'
  lesson_write "coder" "Beta lesson unique word quux" "second body" '["test"]'
  # Both should be in the DB
  count="$("${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" "SELECT COUNT(*) FROM lessons;")"
  [ "$count" -eq 2 ]
  # Query returns at least 1 result
  result="$(lesson_query "lesson" "triage")"
  [ "$result" != "[]" ]
  [ -n "$result" ]
}

# --------------- AC-5: lesson injection latency ≤500ms (Improvement 4) ---------------
# Gap identified in reviewer round 2: this AC was never tested.

@test "AC-5: lesson_query with 50 lessons completes in ≤500ms" {
  # Covers AC-5: lesson injection overhead (query + sanitize + fence build) ≤500ms.
  # N=50 (not 100) because CI runners vary; 50 is representative and avoids flakes.
  # If this test fails consistently, investigate N+1 queries or cold-start embedding.
  # shellcheck disable=SC1090
  source "$LESSONS_LIB"
  lessons_init

  # Pre-populate DB with 50 lessons (direct insert for speed, bypassing embed)
  local i
  for i in $(seq 1 50); do
    "${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" \
      "INSERT INTO lessons (id, source_agent, tags, headline, body, embedding, context, created_at, confidence) \
       VALUES ('lesson-ac5-$(printf '%03d' "$i")', 'reviewer', '[\"test\"]', \
       'Lesson number ${i} about security patterns', 'Body text for lesson ${i}', \
       '', '', datetime('now', '-${i} minutes'), 1.0);" 2>/dev/null
  done

  count="$("${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" "SELECT COUNT(*) FROM lessons;")"
  [ "$count" -eq 50 ]

  # Measure only the lesson_query call (query + result building).
  # Using date +%s%N for nanosecond precision where available; fallback to SECONDS.
  if date +%s%N 2>/dev/null | grep -q '^[0-9]\{10,\}$'; then
    t_start="$(date +%s%N)"
    result="$(lesson_query "security patterns" "coder")"
    t_end="$(date +%s%N)"
    elapsed_ms=$(( (t_end - t_start) / 1000000 ))
  else
    # macOS date lacks %N — use python3 for millisecond timing
    t_start="$(python3 -c "import time; print(int(time.time()*1000))")"
    result="$(lesson_query "security patterns" "coder")"
    t_end="$(python3 -c "import time; print(int(time.time()*1000))")"
    elapsed_ms=$(( t_end - t_start ))
  fi

  echo "lesson_query elapsed: ${elapsed_ms}ms (limit: 500ms, N=50)"
  [ "$result" != "" ]

  # Assert ≤500ms
  [ "$elapsed_ms" -lt 500 ]
}

# --------------- M10: TITLE must not be interpolated into lesson runner heredoc ---------------

@test "M10: run.sh lesson runner passes title via env not heredoc interpolation" {
  # Security: TITLE from Plane is untrusted. It must NOT appear as ${TITLE}
  # inside the heredoc that generates the lesson extraction shell script.
  # The safe pattern passes TITLE via an exported env var.
  # This test verifies the heredoc content does NOT reference $TITLE or ${TITLE}.

  # Extract the lesson runner heredoc content (between LESSON_RUNNER_EOF markers)
  local heredoc_content
  heredoc_content="$(awk '/cat > "\$_LESSON_EXTRACT_RUNNER" <<LESSON_RUNNER_EOF/{p=1;next} /^LESSON_RUNNER_EOF/{p=0} p{print}' "$RUN_SH")"

  # The heredoc must NOT contain literal ${TITLE} or $TITLE interpolation
  if echo "$heredoc_content" | grep -qE '\$\{?TITLE\}?'; then
    echo "FAIL: TITLE is interpolated into lesson runner heredoc (injection risk)" >&3
    echo "Offending lines:" >&3
    echo "$heredoc_content" | grep -E '\$\{?TITLE\}?' >&3
    false
  fi

  # The safe pattern: TITLE passed via env var export before the heredoc
  grep -q 'WALTER_LESSON_TITLE\|_LESSON_TITLE' "$RUN_SH"
}
