#!/usr/bin/env bash
# scripts/wiki/consolidate.sh — weekly wiki consolidation job.
#
# Usage:
#   consolidate.sh [<wiki-dir>]
#
# Environment:
#   WIKI_DIR                          Wiki dir to scan (default: ~/sync/wiki)
#   WIKI_CONSOLIDATE_REPORT           JSON report output path
#   WIKI_CONSOLIDATE_LOG              Log file path
#   WIKI_CONSOLIDATE_DRY_RUN          If 1, print to stdout; skip Plane issue creation
#   WIKI_CONSOLIDATE_SIMILARITY_THRESHOLD  Cosine threshold (default 0.92)
#   WIKI_CONSOLIDATE_STALE_DAYS       Days before stale (default 180)
#   _LESSONS_MOCK_EMBED               If 1, use mock embeddings (for tests)
#   LITELLM_BASE_URL                  LiteLLM endpoint
#
# Steps:
#   1. Dedupe — embed first 500 chars, pairwise cosine similarity > threshold
#   2. Stale detection — pages older than STALE_DAYS with no inbound links
#   3. Write JSON report
#   4. In non-dry-run: create Plane issue with wiki:consolidation label
#
# Exit code: always 0 (errors go to log)
#
# Refs: docs/specs/walter-council-v2.md T-15 Improvement 3

set -uo pipefail

WIKI_DIR="${1:-${WIKI_DIR:-$HOME/sync/wiki}}"
REPORT_FILE="${WIKI_CONSOLIDATE_REPORT:-/tmp/wiki-consolidation-$(date +%Y-%m-%d).json}"
LOG_FILE="${WIKI_CONSOLIDATE_LOG:-/var/log/walter-council/wiki-consolidation.log}"
DRY_RUN="${WIKI_CONSOLIDATE_DRY_RUN:-0}"
SIMILARITY_THRESHOLD="${WIKI_CONSOLIDATE_SIMILARITY_THRESHOLD:-0.92}"
STALE_DAYS="${WIKI_CONSOLIDATE_STALE_DAYS:-180}"
# WIKI_CONSOLIDATE_LLM_CMD: optional command that reads a prompt on stdin and
# outputs YES/NO + reason. Defaults to a curl call to LiteLLM if LITELLM_BASE_URL set.
WIKI_LLM_CMD="${WIKI_CONSOLIDATE_LLM_CMD:-}"
# Similarity window for contradiction candidates: pairs with sim in [low, high)
# that are NOT dupes (sim < SIMILARITY_THRESHOLD) but semantically close enough.
CONTRADICTION_THRESHOLD="${WIKI_CONSOLIDATE_CONTRADICTION_THRESHOLD:-0.7}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_LIB="${SCRIPT_DIR}/../agents/lib/lessons.sh"

_EMBED_AVAILABLE=0
if [[ -f "$LESSONS_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$LESSONS_LIB" 2>/dev/null || true
  _EMBED_AVAILABLE=1
fi

_log() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '{"ts":"%s","msg":"%s"}\n' "$ts" "${msg//\"/\\\"}" >> "$LOG_FILE" 2>/dev/null || true
  echo "[consolidate] $msg"
}

_page_excerpt() {
  local filepath="$1"
  awk '/^---$/{if(++c==2){p=1;next}} p{print}' "$filepath" \
    | tr -d '\n' | cut -c1-500
}

_has_inbound_links() {
  local filepath="$1"
  local slug
  slug="$(basename "$filepath" .md)"
  grep -rlq "\[\[$slug\]\]" "$WIKI_DIR" 2>/dev/null
}

_git_age_days() {
  local filepath="$1"
  local last_modified
  last_modified="$(git -C "$(dirname "$filepath")" log --format="%ct" -- "$filepath" 2>/dev/null | head -1)"
  if [[ -n "$last_modified" ]]; then
    local now
    now="$(date +%s)"
    echo $(( (now - last_modified) / 86400 ))
  else
    local mtime
    mtime="$(stat -f "%m" "$filepath" 2>/dev/null || stat -c "%Y" "$filepath" 2>/dev/null || echo 0)"
    local now
    now="$(date +%s)"
    echo $(( (now - mtime) / 86400 ))
  fi
}

_json_array() {
  local joined="" item
  for item in "$@"; do
    if [[ -n "$joined" ]]; then
      joined+=","
    fi
    joined+="$item"
  done
  printf '[%s]' "$joined"
}

main() {
  if [[ ! -d "$WIKI_DIR" ]]; then
    _log "wiki dir not found: $WIKI_DIR"
    exit 0
  fi

  _log "Starting wiki consolidation for $WIKI_DIR"

  local pages=()
  while IFS= read -r -d '' filepath; do
    pages+=("$filepath")
  done < <(find "$WIKI_DIR" -name '*.md' \
    -not -name 'index.md' -not -name 'log.md' \
    -print0 | sort -z)

  local total="${#pages[@]}"
  _log "Found $total pages to analyze"

  local candidates_json="[]"
  local stale_json="[]"

  # ---- Phase 1: Dedupe via embedding similarity ----
  if [[ "$_EMBED_AVAILABLE" -eq 1 && "$total" -gt 1 ]]; then
    local tmp_embeds
    tmp_embeds="$(mktemp)"

    for filepath in "${pages[@]}"; do
      local excerpt
      excerpt="$(_page_excerpt "$filepath")"
      if [[ -n "$excerpt" ]]; then
        local embed
        embed="$(_lesson_embed "$excerpt" 2>/dev/null || echo "")"
        if [[ -n "$embed" ]]; then
          printf '%s\t%s\n' "$filepath" "$embed" >> "$tmp_embeds"
        fi
      fi
    done

    if [[ -s "$tmp_embeds" ]]; then
      local sim_results
      sim_results="$(python3 - "$tmp_embeds" "$SIMILARITY_THRESHOLD" 2>/dev/null <<'PYEOF'
import sys, json, math, itertools

threshold = float(sys.argv[2])

def cosine(a, b):
    if not a or not b:
        return 0.0
    dot = sum(x*y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x*x for x in a))
    mag_b = math.sqrt(sum(x*x for x in b))
    if mag_a == 0 or mag_b == 0:
        return 0.0
    return dot / (mag_a * mag_b)

pages = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line or '\t' not in line:
            continue
        path, embed_json = line.split('\t', 1)
        try:
            vec = json.loads(embed_json)
            pages.append((path, vec))
        except:
            pass

candidates = []
for (p1, v1), (p2, v2) in itertools.combinations(pages, 2):
    sim = cosine(v1, v2)
    if sim >= threshold:
        candidates.append({
            "page_a": p1,
            "page_b": p2,
            "similarity_score": round(sim, 4),
            "reason": f"cosine similarity {sim:.4f} >= {threshold}"
        })

candidates.sort(key=lambda x: x["similarity_score"], reverse=True)
print(json.dumps(candidates))
PYEOF
)"
      if [[ -n "$sim_results" ]]; then
        candidates_json="$sim_results"
      fi
    fi
    rm -f "$tmp_embeds"

    local num_cands
    num_cands="$(WALTER_CANDS_JSON="$candidates_json" python3 - <<'PYEOF' 2>/dev/null || echo 0
import os, json
print(len(json.loads(os.environ.get('WALTER_CANDS_JSON', '[]'))))
PYEOF
)"
    _log "Duplicate candidates: $num_cands"
  fi

  # ---- Phase 2: Stale detection ----
  local stale_items=()
  for filepath in "${pages[@]}"; do
    local age
    age="$(_git_age_days "$filepath")"
    if [[ "$age" -gt "$STALE_DAYS" ]]; then
      if ! _has_inbound_links "$filepath" 2>/dev/null; then
        # M17: use jq (or python3) to safely escape filepath — avoids JSON breakage
        # when the path contains double-quotes or backslashes.
        local stale_entry
        if command -v jq >/dev/null 2>&1; then
          stale_entry="$(jq -n --arg path "$filepath" --argjson age "$age" \
            '{path: $path, age_days: $age}')"
        else
          stale_entry="$(WALTER_STALE_PATH="$filepath" WALTER_STALE_AGE="$age" \
            python3 -c "import os,json; print(json.dumps({'path':os.environ['WALTER_STALE_PATH'],'age_days':int(os.environ['WALTER_STALE_AGE'])}))")"
        fi
        [[ -n "$stale_entry" ]] && stale_items+=("$stale_entry")
      fi
    fi
  done

  if [[ "${#stale_items[@]}" -gt 0 ]]; then
    stale_json="$(_json_array "${stale_items[@]}")"
    _log "Stale pages: ${#stale_items[@]}"
  fi

  # ---- Phase 3: Contradiction detection ----
  # For each pair of pages with similarity in [CONTRADICTION_THRESHOLD, SIMILARITY_THRESHOLD)
  # (semantically related but not dupes), ask LLM "do these contradict?"
  local contradictions_json="[]"
  if [[ "$_EMBED_AVAILABLE" -eq 1 && -n "$WIKI_LLM_CMD" ]]; then
    # Compute candidate pairs for contradiction: similar but below dupe threshold
    local tmp_embed2
    tmp_embed2="$(mktemp)"
    for filepath in "${pages[@]}"; do
      local excerpt
      excerpt="$(_page_excerpt "$filepath")"
      if [[ -n "$excerpt" ]]; then
        local embed
        embed="$(_lesson_embed "$excerpt" 2>/dev/null || echo "")"
        if [[ -n "$embed" ]]; then
          printf '%s\t%s\n' "$filepath" "$embed" >> "$tmp_embed2"
        fi
      fi
    done

    local contradiction_items=()
    if [[ -s "$tmp_embed2" ]]; then
      local contradiction_pairs
      contradiction_pairs="$(python3 - "$tmp_embed2" "$CONTRADICTION_THRESHOLD" "$SIMILARITY_THRESHOLD" 2>/dev/null <<'PYEOF'
import sys, json, math, itertools

low_thresh = float(sys.argv[2])
high_thresh = float(sys.argv[3])

def cosine(a, b):
    if not a or not b:
        return 0.0
    dot = sum(x*y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x*x for x in a))
    mag_b = math.sqrt(sum(x*x for x in b))
    if mag_a == 0 or mag_b == 0:
        return 0.0
    return dot / (mag_a * mag_b)

pages = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line or '\t' not in line:
            continue
        path, embed_json = line.split('\t', 1)
        try:
            vec = json.loads(embed_json)
            pages.append((path, vec))
        except:
            pass

pairs = []
for (p1, v1), (p2, v2) in itertools.combinations(pages, 2):
    sim = cosine(v1, v2)
    # Include pairs in the "similar but not dupe" zone
    if low_thresh <= sim < high_thresh:
        pairs.append({"page_a": p1, "page_b": p2, "similarity": round(sim, 4)})

# Top 10 by similarity
pairs.sort(key=lambda x: x["similarity"], reverse=True)
print(json.dumps(pairs[:10]))
PYEOF
)"
      if [[ -n "$contradiction_pairs" && "$contradiction_pairs" != "[]" ]]; then
        local n_pairs
        n_pairs="$(WALTER_PAIRS_JSON="$contradiction_pairs" python3 - <<'PYEOF' 2>/dev/null || echo 0
import os, json
print(len(json.loads(os.environ.get('WALTER_PAIRS_JSON', '[]'))))
PYEOF
)"
        _log "Checking $n_pairs pairs for contradiction"
        # For each pair, invoke LLM
        # Write pairs to a tmp file — never interpolate JSON into python source.
        local tmp_pairs_file
        tmp_pairs_file="$(mktemp -t walter-contra-pairs-XXXXXX)"
        printf '%s\n' "$contradiction_pairs" > "$tmp_pairs_file"
        while IFS= read -r pair_json; do
          local page_a page_b
          # Extract page_a/page_b via env var to avoid triple-quote injection.
          page_a="$(WALTER_PAIR_JSON="$pair_json" python3 - <<'PYEOF' 2>/dev/null || echo ""
import os, json
d = json.loads(os.environ.get('WALTER_PAIR_JSON', '{}'))
print(d.get('page_a', ''))
PYEOF
)"
          page_b="$(WALTER_PAIR_JSON="$pair_json" python3 - <<'PYEOF' 2>/dev/null || echo ""
import os, json
d = json.loads(os.environ.get('WALTER_PAIR_JSON', '{}'))
print(d.get('page_b', ''))
PYEOF
)"
          [[ -z "$page_a" || -z "$page_b" ]] && continue
          local content_a content_b
          content_a="$(cat "$page_a" 2>/dev/null | head -80)"
          content_b="$(cat "$page_b" 2>/dev/null | head -80)"
          local llm_prompt
          llm_prompt="$(printf '%s' "Do the following two wiki pages contradict each other? Answer YES or NO and 1 sentence why.

Page A (${page_a}):
${content_a}

Page B (${page_b}):
${content_b}")"
          local llm_response
          llm_response="$(printf '%s' "$llm_prompt" | "$WIKI_LLM_CMD" 2>/dev/null || echo "NO - LLM unavailable")"
          if printf '%s' "$llm_response" | grep -qi '^YES'; then
            local reason
            reason="$(printf '%s' "$llm_response" | head -1)"
            # Build contradiction item via env vars — no interpolation into python source.
            contradiction_items+=("$(WALTER_PAGE_A="$page_a" WALTER_PAGE_B="$page_b" WALTER_REASON="$reason" \
              python3 - <<'PYEOF' 2>/dev/null || printf '{"page_a":"%s","page_b":"%s"}' "$page_a" "$page_b"
import os, json
print(json.dumps({
    'page_a': os.environ['WALTER_PAGE_A'],
    'page_b': os.environ['WALTER_PAGE_B'],
    'reason': os.environ['WALTER_REASON'],
}))
PYEOF
)")
          fi
        done < <(python3 - "$tmp_pairs_file" <<'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    pairs = json.loads(f.read() or '[]')
for p in pairs:
    print(json.dumps(p))
PYEOF
)
        rm -f "$tmp_pairs_file"
      fi

      if [[ "${#contradiction_items[@]}" -gt 0 ]]; then
        contradictions_json="$(_json_array "${contradiction_items[@]}")"
      fi
    fi
    rm -f "$tmp_embed2"
    local _n_contradictions="${#contradiction_items[@]}"
    _log "Contradictions detected: ${_n_contradictions}"
  fi

  # ---- Phase 4: Write report ----
  mkdir -p "$(dirname "$REPORT_FILE")"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local tmp_cands tmp_stale tmp_contradictions
  tmp_cands="$(mktemp)"
  tmp_stale="$(mktemp)"
  tmp_contradictions="$(mktemp)"
  printf '%s\n' "$candidates_json" > "$tmp_cands"
  printf '%s\n' "$stale_json" > "$tmp_stale"
  printf '%s\n' "$contradictions_json" > "$tmp_contradictions"

  python3 - "$tmp_cands" "$tmp_stale" "$tmp_contradictions" "$ts" "$WIKI_DIR" "$total" "$SIMILARITY_THRESHOLD" "$REPORT_FILE" 2>/dev/null <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    candidates = json.loads(f.read() or '[]')
with open(sys.argv[2]) as f:
    stale = json.loads(f.read() or '[]')
with open(sys.argv[3]) as f:
    contradictions = json.loads(f.read() or '[]')

ts = sys.argv[4]
wiki_dir = sys.argv[5]
total = int(sys.argv[6])
threshold = float(sys.argv[7])
report_file = sys.argv[8]

report = {
    "generated_at": ts,
    "wiki_dir": wiki_dir,
    "total_pages": total,
    "similarity_threshold": threshold,
    "candidates": candidates,
    "stale_pages": stale,
    "contradictions": contradictions,
    "summary": {
        "duplicate_candidates": len(candidates),
        "stale_pages": len(stale),
        "contradictions": len(contradictions)
    }
}

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2)
print(f"Report written: {report_file}")
PYEOF
  local report_rc=$?
  rm -f "$tmp_cands" "$tmp_stale" "$tmp_contradictions"

  if [[ $report_rc -ne 0 || ! -f "$REPORT_FILE" ]]; then
    # Fallback minimal JSON if python failed
    printf '{"generated_at":"%s","candidates":[],"stale_pages":[],"contradictions":[],"total_pages":%d}\n' \
      "$ts" "$total" > "$REPORT_FILE"
  fi

  # ---- Phase 5: Output / Plane issue ----
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "=== Wiki Consolidation Report (dry-run) ==="
    python3 -c "
import json
with open('$REPORT_FILE') as f:
    data = json.load(f)
summ = data.get('summary', {})
print(f\"  Pages analyzed: {data.get('total_pages', 0)}\")
print(f\"  Duplicate candidates: {summ.get('duplicate_candidates', 0)}\")
print(f\"  Stale pages: {summ.get('stale_pages', 0)}\")
print(f\"  Contradictions detected: {summ.get('contradictions', 0)}\")
print(f\"  Report: $REPORT_FILE\")
" 2>/dev/null || echo "  Report: $REPORT_FILE"
  else
    echo "Report written to: $REPORT_FILE"
    # Plane issue creation (requires plane.sh + PLANE_* env vars)
    local plane_lib
    plane_lib="${SCRIPT_DIR}/../agents/lib/plane.sh"
    if [[ -f "$plane_lib" ]]; then
      # shellcheck disable=SC1090
      source "$plane_lib" 2>/dev/null || true
      if command -v plane_issue_create >/dev/null 2>&1; then
        local summary
        summary="$(python3 -c "
import json
with open('$REPORT_FILE') as f:
    data = json.load(f)
cands = data.get('candidates', [])
stale = data.get('stale_pages', [])
contradictions = data.get('contradictions', [])
lines = [f'Wiki consolidation {data.get(\"generated_at\",\"\")}',
         f'Pages: {data.get(\"total_pages\",0)}  |  Candidates: {len(cands)}  |  Stale: {len(stale)}  |  Contradictions: {len(contradictions)}']
if cands:
    lines.extend(['', 'Top candidates:'])
    for c in cands[:5]:
        a = c.get('page_a','?').split('/')[-1]
        b = c.get('page_b','?').split('/')[-1]
        s = c.get('similarity_score', 0)
        lines.append(f'  - {a} <-> {b} ({s})')
if contradictions:
    lines.extend(['', 'Contradictions detected:'])
    for c in contradictions[:5]:
        a = c.get('page_a','?').split('/')[-1]
        b = c.get('page_b','?').split('/')[-1]
        reason = c.get('reason', '')[:100]
        lines.append(f'  - {a} vs {b}: {reason}')
print('\n'.join(lines))
" 2>/dev/null || echo "Wiki consolidation report")"
        plane_issue_create "Wiki consolidation report $(date +%Y-%m-%d)" "$summary" "wiki:consolidation" \
          2>/dev/null || _log "Could not create Plane issue (PLANE_* env vars not set?)"
      fi
    fi
  fi

  _log "Consolidation complete"
  exit 0
}

main
