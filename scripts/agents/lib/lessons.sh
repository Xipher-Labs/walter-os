#!/usr/bin/env bash
# scripts/agents/lib/lessons.sh — Cross-agent learning broker.
#
# Provides:
#   lessons_init                    Create/migrate lessons.db (idempotent)
#   _lesson_embed <text>            Embed text -> JSON float array (mock-able)
#   lesson_write <agent> <headline> <body> <tags_json>
#                                   Insert a lesson into the DB
#   lesson_query <task_desc> <agent> [--context <ctx>]
#                                   Return top-5 relevant lessons as JSON array
#   lessons_list [--agent <name>] [--last <Nd>] [--tag <tag>]
#                                   List lessons in tabular form
#   lessons_rate <id> <score>       Update confidence for a lesson
#
# Environment:
#   LESSONS_DB          Path to SQLite DB (default: ~/.config/walter-os/lessons.db)
#   LITELLM_BASE_URL    LiteLLM endpoint (for real embeddings)
#   LITELLM_API_KEY     API key for LiteLLM
#   _LESSONS_MOCK_EMBED If 1, return deterministic mock embedding (for tests)
#
# Embedding strategy:
#   1. _LESSONS_MOCK_EMBED=1  -> deterministic mock (tests/CI)
#   2. LITELLM_BASE_URL set   -> POST /v1/embeddings model=walter-embed
#   3. Neither                -> empty embedding, FTS5 fallback for queries
#
# Refs: docs/specs/walter-council-v2.md T-9 T-10 T-11 Improvement 4

set -uo pipefail

LESSONS_DB="${LESSONS_DB:-$HOME/.config/walter-os/lessons.db}"
_LESSON_EMBED_TIMEOUT=5
_LESSON_TOP_K=5
_LESSON_CONFIDENCE_THRESHOLD=0.5

# Capture the lib's own directory at source-time (BASH_SOURCE[0] resolves here).
_LESSONS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ---- FTS5 runtime detection -------------------------------------------------

# Returns 0 if the sqlite3 binary has FTS5 support, 1 otherwise.
# Cached in _LESSONS_FTS5_AVAILABLE to avoid repeated sub-shell tests.
_LESSONS_FTS5_AVAILABLE=""

_lessons_has_fts5() {
  if [[ -n "$_LESSONS_FTS5_AVAILABLE" ]]; then
    [[ "$_LESSONS_FTS5_AVAILABLE" == "1" ]]
    return $?
  fi
  if "${_LESSONS_SQLITE3:-sqlite3}" :memory: \
       "CREATE VIRTUAL TABLE t USING fts5(c);" 2>/dev/null; then
    _LESSONS_FTS5_AVAILABLE="1"
    return 0
  else
    _LESSONS_FTS5_AVAILABLE="0"
    return 1
  fi
}

# ---- Schema migration -------------------------------------------------------

lessons_init() {
  mkdir -p "$(dirname "$LESSONS_DB")"

  # Find the sqlite3 binary — prefer Homebrew's (has FTS5), fall back to system.
  # Use `brew --prefix sqlite` to locate dynamically; avoids hardcoding Cellar version.
  local _sqlite3
  _sqlite3="$(command -v sqlite3 2>/dev/null)"
  local _brew_sqlite
  _brew_sqlite="$(brew --prefix sqlite 2>/dev/null || true)/bin/sqlite3"
  if [[ -x "$_brew_sqlite" ]]; then
    _sqlite3="$_brew_sqlite"
  fi
  [[ -z "$_sqlite3" ]] && { echo "lessons_init: sqlite3 not found" >&2; return 1; }
  export _LESSONS_SQLITE3="$_sqlite3"

  local schema_dir
  schema_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/migrations"
  local schema_sql="${schema_dir}/001_lessons_schema.sql"

  if [[ -f "$schema_sql" ]]; then
    # Run core schema (tables + indexes).  The schema file also contains FTS5
    # DDL — it's safe to pipe the whole file because each statement that uses
    # FTS5-only syntax will simply fail with sqlite's error which we suppress.
    # We run the core table DDL first (guaranteed to succeed), then attempt FTS5.
    "$_sqlite3" "$LESSONS_DB" <<'SQL' 2>/dev/null || true
CREATE TABLE IF NOT EXISTS lessons (
  id          TEXT PRIMARY KEY,
  source_agent TEXT NOT NULL,
  tags        TEXT,
  headline    TEXT NOT NULL,
  body        TEXT,
  embedding   BLOB,
  context     TEXT,
  created_at  TEXT NOT NULL,
  confidence  REAL NOT NULL DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS idx_lessons_agent ON lessons(source_agent);
CREATE INDEX IF NOT EXISTS idx_lessons_confidence ON lessons(confidence);
SQL
    # Attempt FTS5 extension — silently skip if sqlite3 lacks FTS5
    "$_sqlite3" "$LESSONS_DB" <<'SQL' 2>/dev/null || true
CREATE VIRTUAL TABLE IF NOT EXISTS lessons_fts USING fts5(
  headline, body, content='lessons', content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS lessons_ai AFTER INSERT ON lessons BEGIN
  INSERT INTO lessons_fts(rowid, headline, body) VALUES (new.rowid, new.headline, new.body);
END;
CREATE TRIGGER IF NOT EXISTS lessons_ad AFTER DELETE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body) VALUES ('delete', old.rowid, old.headline, old.body);
END;
CREATE TRIGGER IF NOT EXISTS lessons_au AFTER UPDATE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body) VALUES ('delete', old.rowid, old.headline, old.body);
  INSERT INTO lessons_fts(rowid, headline, body) VALUES (new.rowid, new.headline, new.body);
END;
SQL
  else
    # Inline minimal schema (graceful degradation when file not found)
    "$_sqlite3" "$LESSONS_DB" <<'SQL' 2>/dev/null || true
CREATE TABLE IF NOT EXISTS lessons (
  id          TEXT PRIMARY KEY,
  source_agent TEXT NOT NULL,
  tags        TEXT,
  headline    TEXT NOT NULL,
  body        TEXT,
  embedding   BLOB,
  context     TEXT,
  created_at  TEXT NOT NULL,
  confidence  REAL NOT NULL DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS idx_lessons_agent ON lessons(source_agent);
CREATE INDEX IF NOT EXISTS idx_lessons_confidence ON lessons(confidence);
SQL
    # Attempt FTS5 even in inline path
    "$_sqlite3" "$LESSONS_DB" <<'SQL' 2>/dev/null || true
CREATE VIRTUAL TABLE IF NOT EXISTS lessons_fts USING fts5(
  headline, body, content='lessons', content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS lessons_ai AFTER INSERT ON lessons BEGIN
  INSERT INTO lessons_fts(rowid, headline, body) VALUES (new.rowid, new.headline, new.body);
END;
CREATE TRIGGER IF NOT EXISTS lessons_ad AFTER DELETE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body) VALUES ('delete', old.rowid, old.headline, old.body);
END;
CREATE TRIGGER IF NOT EXISTS lessons_au AFTER UPDATE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body) VALUES ('delete', old.rowid, old.headline, old.body);
  INSERT INTO lessons_fts(rowid, headline, body) VALUES (new.rowid, new.headline, new.body);
END;
SQL
  fi

  # Verify core table exists
  "$_sqlite3" "$LESSONS_DB" "SELECT COUNT(*) FROM lessons;" > /dev/null 2>&1
}

# ---- Embedding --------------------------------------------------------------

_lesson_embed_mock() {
  # Deterministic 384-dim mock vector (all 0.01)
  python3 -c "import json; print(json.dumps([0.01]*384))" 2>/dev/null || echo "[]"
}

_lesson_embed_real() {
  local text="$1"
  local json_input
  # SECURITY: build JSON via jq, not by interpolating $text into a Python source
  # string. The previous `text = '''$text'''` form let untrusted lesson text
  # close the triple-quote and execute as Python (code injection). jq -R reads
  # stdin as a raw string and emits properly escaped JSON.
  json_input="$(printf '%s' "$text" | jq -Rcs '{model: "walter-embed", input: .}' 2>/dev/null)"
  if [[ -z "$json_input" ]]; then
    return 1
  fi

  local response
  response="$(curl -sf --max-time "$_LESSON_EMBED_TIMEOUT" \
    -X POST "${LITELLM_BASE_URL}/v1/embeddings" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${LITELLM_API_KEY:-}" \
    -d "$json_input" 2>/dev/null || echo "")"

  if [[ -n "$response" ]]; then
    # SECURITY: pipe the API response through stdin rather than interpolating
    # it into the Python source — a malicious or malformed response containing
    # `'''` would otherwise break out of the string literal.
    printf '%s' "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data['data'][0]['embedding']))
except Exception:
    print('')
" 2>/dev/null || echo ""
  fi
}

_lesson_embed() {
  local text="$1"

  if [[ "${_LESSONS_MOCK_EMBED:-0}" == "1" ]]; then
    _lesson_embed_mock
    return 0
  fi

  if [[ -n "${LITELLM_BASE_URL:-}" ]]; then
    local result
    result="$(_lesson_embed_real "$text")"
    if [[ -n "$result" ]]; then
      printf '%s' "$result"
      return 0
    fi
  fi

  echo ""
}

# ---- UUID generation --------------------------------------------------------

_gen_uuid() {
  python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null \
    || { date +%s%N | sha256sum | head -c 8; echo "-$(date +%s)"; }
}

# ---- Write ------------------------------------------------------------------

# _lesson_sanitize_text <text> <max_len>
# Sanitize untrusted lesson text before storage:
#   1. Run through the secret redactor (strips API keys, tokens, etc.)
#   2. Strip result markers and LLM special tokens
#   3. Remove ASCII control characters (except TAB and LF)
#   4. Hard-cap at max_len chars, appending " [truncated]" if needed
_lesson_sanitize_text() {
  local text="$1"
  local max_len="${2:-2000}"
  # Locate secret redactor: explicit REDACTOR env > WALTER_OS_HOME > script-relative
  local redactor="${REDACTOR:-}"
  if [[ -z "$redactor" ]]; then
    # Use _LESSONS_LIB_DIR captured at source time (reliable even when sourced)
    local _candidate="${_LESSONS_LIB_DIR}/../../agent-secret-redactor.sh"
    if [[ -x "$_candidate" ]]; then
      redactor="$_candidate"
    elif [[ -n "${WALTER_OS_HOME:-}" && -x "${WALTER_OS_HOME}/scripts/agent-secret-redactor.sh" ]]; then
      redactor="${WALTER_OS_HOME}/scripts/agent-secret-redactor.sh"
    fi
  fi

  # Layer 1a — inline redaction of common secret patterns (no external dep)
  # Applied before the redactor script so it always runs regardless of WALTER_OS_HOME.
  if command -v perl >/dev/null 2>&1; then
    text="$(printf '%s' "$text" | perl -pe '
      s|sk-ant-[a-zA-Z0-9_\-]{20,}|<REDACTED:anthropic>|g;
      s|sk-proj-[a-zA-Z0-9_\-]{20,}|<REDACTED:openai>|g;
      s|sk-[a-zA-Z0-9]{20,}|<REDACTED:openai>|g;
      s|AIza[0-9A-Za-z_\-]{35}|<REDACTED:google>|g;
      s|gh[pousr]_[A-Za-z0-9]{36,}|<REDACTED:github>|g;
      s|AKIA[0-9A-Z]{16}|<REDACTED:aws-access>|g;
      s|xox[abp]-[0-9]+-[0-9]+-[A-Za-z0-9]+|<REDACTED:slack>|g;
      s|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|<REDACTED:jwt>|g;
      s/(?:rk|pk|sk)_(?:test|live)_[A-Za-z0-9]{20,}/<REDACTED:stripe>/gi;
      s|Bearer\s+[A-Za-z0-9._\-]+|Bearer <REDACTED:token>|gi;
    ' 2>/dev/null || printf '%s' "$text")"
  fi

  # Layer 1b — secret redactor script (if available)
  if [[ -x "$redactor" ]]; then
    text="$(printf '%s' "$text" | "$redactor" 2>/dev/null || printf '%s' "$text")"
  fi

  # Layer 2 — strip result markers + LLM special tokens
  text="$(printf '%s' "$text" | \
    sed -E 's/<<<RESULT_[A-Z_]+>>>//g; s/<\|im_start\|>//g; s/<\|im_end\|>//g; s/\n\nHuman://g; s/\n\nAssistant://g')"

  # Layer 3 — strip non-printable control chars (keep TAB=0x09, LF=0x0A)
  text="$(printf '%s' "$text" | LC_ALL=C tr -d '\000-\010\013-\037\177')"

  # Layer 4 — hard cap at max_len (inclusive of " [truncated]" suffix)
  local _suffix=" [truncated]"
  if [[ "${#text}" -gt "$max_len" ]]; then
    local _keep=$(( max_len - ${#_suffix} ))
    [[ "$_keep" -lt 0 ]] && _keep=0
    text="${text:0:$_keep}${_suffix}"
  fi

  printf '%s' "$text"
}

# lesson_write <agent> <headline> <body> <tags_json>
lesson_write() {
  local agent="${1:-unknown}"
  local headline="${2:-}"
  local body="${3:-}"
  local tags="${4:-[]}"

  [[ -z "$headline" ]] && { echo "lesson_write: headline required" >&2; return 1; }

  lessons_init || return 1

  # Sanitize at write time: redact secrets, strip injection markers, cap lengths
  headline="$(_lesson_sanitize_text "$headline" 200)"
  body="$(_lesson_sanitize_text "$body" 2000)"

  local id created_at
  id="$(_gen_uuid)"
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local embed_json
  embed_json="$(_lesson_embed "$headline $body")"

  local context="${WALTER_AGENT_CONTEXT:-}"

  # Escape single quotes for SQLite inline SQL (single-quote doubling per SQL spec)
  local agent_esc headline_esc body_esc tags_esc embed_esc context_esc
  agent_esc="${agent//"'"/"''"}"         # M18: escape agent — was missing in prior version
  headline_esc="${headline//"'"/"''"}"
  body_esc="${body//"'"/"''"}"
  tags_esc="${tags//"'"/"''"}"
  embed_esc="${embed_json//"'"/"''"}"
  context_esc="${context//"'"/"''"}"

  "${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" \
    "INSERT INTO lessons (id, source_agent, tags, headline, body, embedding, context, created_at, confidence) VALUES ('${id}', '${agent_esc}', '${tags_esc}', '${headline_esc}', '${body_esc}', '${embed_esc}', '${context_esc}', '${created_at}', 1.0);"
}

# ---- Query ------------------------------------------------------------------

# lesson_query <task_description> <agent_name> [--context <ctx>]
lesson_query() {
  local task_desc="${1:-}"
  local _agent_name="${2:-}"  # reserved for future per-agent filtering; unused now
  local context_filter=""

  shift 2 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context) context_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$task_desc" ]] && { echo "[]"; return 0; }

  lessons_init || { echo "[]"; return 0; }

  local count
  count="$("${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" \
    "SELECT COUNT(*) FROM lessons WHERE confidence >= ${_LESSON_CONFIDENCE_THRESHOLD};" \
    2>/dev/null || echo 0)"
  if [[ "$count" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  local query_embed
  query_embed="$(_lesson_embed "$task_desc")"

  # Escape single quotes in context_filter for both SQL branches (vector + FTS).
  # Declared once here to guarantee consistent escaping across all query paths.
  local context_filter_esc="${context_filter//"'"/"''"}"

  local where_clause="WHERE confidence >= ${_LESSON_CONFIDENCE_THRESHOLD}"
  if [[ -n "$context_filter" ]]; then
    where_clause="${where_clause} AND (context = '${context_filter_esc}' OR context = '' OR context IS NULL)"
  fi

  if [[ -n "$query_embed" ]]; then
    # Vector similarity path via Python
    # Use ASCII 0x1F (Unit Separator) as column delimiter — safe from pipe chars in text.
    local rows
    rows="$("${_LESSONS_SQLITE3:-sqlite3}" -separator $'\x1f' "$LESSONS_DB" \
      "SELECT id, source_agent, headline, body, tags, embedding, confidence FROM lessons ${where_clause};" \
      2>/dev/null || echo "")"

    if [[ -n "$rows" ]]; then
      local results
      # Write rows to temp file to avoid heredoc quoting issues
      local tmp_rows tmp_vec
      tmp_rows="$(mktemp)"
      tmp_vec="$(mktemp)"
      printf '%s\n' "$rows" > "$tmp_rows"
      printf '%s\n' "$query_embed" > "$tmp_vec"

      results="$(python3 - "$tmp_vec" "$tmp_rows" "$_LESSON_TOP_K" "$_LESSON_CONFIDENCE_THRESHOLD" <<'PYEOF' 2>/dev/null
import sys, json, math

with open(sys.argv[1]) as f:
    query_vec_json = f.read().strip()
with open(sys.argv[2]) as f:
    rows_text = f.read()

top_k = int(sys.argv[3])
threshold = float(sys.argv[4])

def cosine(a, b):
    if not a or not b:
        return 0.0
    dot = sum(x*y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x*x for x in a))
    mag_b = math.sqrt(sum(x*x for x in b))
    if mag_a == 0 or mag_b == 0:
        return 0.0
    return dot / (mag_a * mag_b)

try:
    q = json.loads(query_vec_json) if query_vec_json else []
except:
    q = []

scored = []
SEP = '\x1f'  # ASCII Unit Separator — safe from pipe chars in lesson text
for line in rows_text.strip().split('\n'):
    if not line:
        continue
    parts = line.split(SEP)
    if len(parts) < 7:
        continue
    lid, agent, headline, body, tags, embed_json, conf_str = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    try:
        conf = float(conf_str)
    except:
        conf = 1.0
    if conf < threshold:
        continue
    sim = 0.0
    if q and embed_json:
        try:
            ev = json.loads(embed_json)
            sim = cosine(q, ev)
        except:
            sim = 0.0
    scored.append({
        "id": lid,
        "source_agent": agent,
        "headline": headline,
        "body": body,
        "tags": tags,
        "similarity": round(sim, 4),
        "confidence": conf
    })

scored.sort(key=lambda x: x['similarity'], reverse=True)
print(json.dumps(scored[:top_k]))
PYEOF
)"
      rm -f "$tmp_rows" "$tmp_vec"

      if [[ -n "$results" ]]; then
        printf '%s' "$results"
        return 0
      fi
    fi
  fi

  # FTS5 fallback (or LIKE fallback when FTS5 is unavailable)
  local fts_where="WHERE l.confidence >= ${_LESSON_CONFIDENCE_THRESHOLD}"
  if [[ -n "$context_filter" ]]; then
    fts_where="${fts_where} AND (l.context = '${context_filter_esc}' OR l.context = '' OR l.context IS NULL)"
  fi

  # Simple tokenization: first 5 words of task description (sanitized)
  local fts_query
  fts_query="$(printf '%s' "$task_desc" | tr -s '[:space:]' '\n' | \
    grep -v '^$' | head -5 | tr '\n' ' ' | sed 's/ *$//' | \
    LC_ALL=C tr -d "\"';")"

  if [[ -n "$fts_query" ]]; then
    local fts_rows=""

    if _lessons_has_fts5; then
      # FTS5 path — use virtual table for ranked keyword search.
      # 0x1F (Unit Separator) avoids pipe chars in lesson text breaking column splits.
      local fts_query_esc="${fts_query//\"/\"\"}"
      fts_rows="$("${_LESSONS_SQLITE3:-sqlite3}" -separator $'\x1f' "$LESSONS_DB" \
        "SELECT l.id, l.source_agent, l.headline, l.body, l.tags, l.confidence
         FROM lessons l
         JOIN lessons_fts f ON l.rowid = f.rowid
         ${fts_where}
         AND lessons_fts MATCH '\"${fts_query_esc}\"'
         ORDER BY rank
         LIMIT ${_LESSON_TOP_K};" 2>/dev/null || echo "")"
    else
      # LIKE fallback — sqlite3 build lacks FTS5 module.
      # 0x1F (Unit Separator) avoids pipe chars in lesson text breaking column splits.
      echo "lessons: FTS5 unavailable; falling back to LIKE search" >&2
      # Build a LIKE condition for the first keyword only (safe enough for search)
      local first_kw
      first_kw="$(printf '%s' "$fts_query" | awk '{print $1}' | LC_ALL=C tr -d "\"';")"
      if [[ -n "$first_kw" ]]; then
        local first_kw_esc="${first_kw//"'"/"''"}"
        fts_rows="$("${_LESSONS_SQLITE3:-sqlite3}" -separator $'\x1f' "$LESSONS_DB" \
          "SELECT id, source_agent, headline, body, tags, confidence
           FROM lessons
           ${fts_where//WHERE l./WHERE }
           AND (headline LIKE '%${first_kw_esc}%' OR body LIKE '%${first_kw_esc}%')
           ORDER BY confidence DESC
           LIMIT ${_LESSON_TOP_K};" 2>/dev/null || echo "")"
      fi
    fi

    if [[ -n "$fts_rows" ]]; then
      # SECURITY: pipe sqlite output via stdin instead of interpolating into the
      # Python source. Lesson body/headline can contain `'''`, which under the
      # previous form would have broken out of the triple-quoted string.
      # Separator is 0x1F (Unit Separator) — safe from pipe chars in lesson text.
      printf '%s' "$fts_rows" | python3 -c "
import json, sys
SEP = '\x1f'  # ASCII Unit Separator — must match sqlite3 -separator arg
rows = sys.stdin.read()
result = []
for line in rows.strip().split('\n'):
    if not line: continue
    parts = line.split(SEP)
    if len(parts) < 6: continue
    try:
        conf = float(parts[5])
    except Exception:
        conf = 1.0
    result.append({
        'id': parts[0], 'source_agent': parts[1],
        'headline': parts[2], 'body': parts[3],
        'tags': parts[4], 'confidence': conf,
        'similarity': None
    })
print(json.dumps(result))
" 2>/dev/null || echo "[]"
      return 0
    fi
  fi

  echo "[]"
}

# ---- List -------------------------------------------------------------------

# lessons_list [--agent <name>] [--last <Nd>] [--tag <tag>]
lessons_list() {
  local agent_filter="" days_filter="" tag_filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent_filter="$2"; shift 2 ;;
      --last)
        local raw_days="${2:-7d}"
        days_filter="${raw_days//d/}"
        shift 2
        ;;
      --tag) tag_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  lessons_init || return 1

  # Validate days_filter as a positive integer before interpolation
  if [[ -n "$days_filter" ]]; then
    if ! [[ "$days_filter" =~ ^[0-9]+$ ]]; then
      echo "lessons_list: --last / --days must be a positive integer, got: '${days_filter}'" >&2
      return 1
    fi
  fi

  # Escape single quotes in string filters
  local agent_filter_esc="${agent_filter//"'"/"''"}"
  local tag_filter_esc="${tag_filter//"'"/"''"}"

  local where="WHERE 1=1"
  [[ -n "$agent_filter" ]] && where="${where} AND source_agent = '${agent_filter_esc}'"
  if [[ -n "$days_filter" ]]; then
    where="${where} AND created_at >= datetime('now', '-${days_filter} days')"
  fi
  if [[ -n "$tag_filter" ]]; then
    where="${where} AND tags LIKE '%${tag_filter_esc}%'"
  fi

  printf "%-36s  %-12s  %-8s  %s\n" "ID" "AGENT" "CONF" "HEADLINE"
  printf "%-36s  %-12s  %-8s  %s\n" \
    "────────────────────────────────────" \
    "────────────" \
    "────────" \
    "────────────────────────────────────────"

  # Use 0x1F (Unit Separator) to avoid pipe chars in headlines breaking column parsing.
  "${_LESSONS_SQLITE3:-sqlite3}" -separator $'\x1f' "$LESSONS_DB" \
    "SELECT id, source_agent, printf('%.2f', confidence), headline FROM lessons ${where} ORDER BY created_at DESC;" \
    2>/dev/null | while IFS=$'\x1f' read -r lid agent conf headline; do
      printf "%-36s  %-12s  %-8s  %s\n" "$lid" "$agent" "$conf" "${headline:0:60}"
    done
}

# ---- Rate -------------------------------------------------------------------

# lessons_rate <id> <score>
lessons_rate() {
  local id="${1:-}"
  local score="${2:-}"

  [[ -z "$id" || -z "$score" ]] && {
    echo "lessons_rate: id and score required" >&2
    echo "Usage: lessons_rate <id> <0.0..1.0>" >&2
    return 1
  }

  # Validate score: must be a float in [0.0, 1.0].
  # SECURITY: do not interpolate $score into the Python source — a malicious
  # value could close the string literal and execute arbitrary code. Pre-check
  # shape with a bash regex, then pass via stdin for the range check.
  if ! [[ "$score" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    echo "lessons_rate: score must be a float in [0.0, 1.0], got: ${score}" >&2
    return 1
  fi
  if ! printf '%s' "$score" | python3 -c "
import sys
s = float(sys.stdin.read().strip())
assert 0.0 <= s <= 1.0
" 2>/dev/null; then
    echo "lessons_rate: score must be a float in [0.0, 1.0], got: ${score}" >&2
    return 1
  fi

  lessons_init || return 1

  # Escape id to prevent SQL injection
  local id_esc="${id//"'"/"''"}"

  "${_LESSONS_SQLITE3:-sqlite3}" "$LESSONS_DB" \
    "UPDATE lessons SET confidence = ${score} WHERE id = '${id_esc}';" 2>/dev/null
  echo "Updated confidence for $id to $score"
}
