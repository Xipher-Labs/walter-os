#!/usr/bin/env bats
# tests/skills/readme-craft-recommended-tools.bats
#
# Validates skills/readme-craft/recommended-tools.md — the curated list
# of 8 upstream tools the skill recommends.
#
# Two test layers:
#  1) Static — file exists, has the expected structure, no broken
#     internal references. Runs in every CI job.
#  2) Liveness — every upstream URL responds with HTTP 200 via HEAD.
#     Gated by RECOMMENDED_TOOLS_LIVENESS=1 so default CI doesn't fail
#     on transient upstream outages. Run weekly + on quarterly upgrade
#     cadence.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SKILL_DIR="${REPO_ROOT}/skills/readme-craft"
SKILL_MD="${SKILL_DIR}/SKILL.md"
RECOMMENDED_MD="${SKILL_DIR}/recommended-tools.md"

# -----------------------------------------------------------------------
# AC-1: recommended-tools.md exists and is non-empty
# -----------------------------------------------------------------------
@test "AC-1: recommended-tools.md exists and is non-empty" {
  [ -s "${RECOMMENDED_MD}" ]
}

# -----------------------------------------------------------------------
# AC-2: file has the expected 8 tool sections
# -----------------------------------------------------------------------
@test "AC-2: file lists exactly 8 tool entries" {
  count=$(grep -cE '^## [0-9]+\. ' "${RECOMMENDED_MD}")
  [ "${count}" -eq 8 ]
}

# -----------------------------------------------------------------------
# AC-3: each entry has the three required structured subsections
# (Use-when / Avoid-when / Supply-chain notes). The "Why this not X"
# narrative subsection that some entries carry is free-form and not
# enforced here.
# -----------------------------------------------------------------------
@test "AC-3: every entry has Use-when, Avoid-when, and Supply-chain notes" {
  use_when=$(grep -cE '^\*\*Use when\*\*' "${RECOMMENDED_MD}")
  avoid_when=$(grep -cE '^\*\*Avoid when\*\*' "${RECOMMENDED_MD}")
  supply=$(grep -cE '^\*\*Supply-chain notes\*\*' "${RECOMMENDED_MD}")
  [ "${use_when}" -eq 8 ]
  [ "${avoid_when}" -eq 8 ]
  [ "${supply}" -eq 8 ]
}

# -----------------------------------------------------------------------
# AC-4: the upstream catalog is linked at least twice (once as the
# anchor / preamble link, again in the re-audit checklist or footer).
# `grep -qc` was a bug — `-q` suppresses output but `-c` only counts,
# and short-circuits at first match, so the assertion was effectively
# "linked at least once". Use a proper count + threshold instead.
# -----------------------------------------------------------------------
@test "AC-4: upstream catalog is referenced at least twice" {
  count=$(grep -cE "dhyeythumar/awesome-readme-tools" "${RECOMMENDED_MD}")
  [ "${count}" -ge 2 ]
}

# -----------------------------------------------------------------------
# AC-5: file has a 'What we explicitly skipped' transparency table
# -----------------------------------------------------------------------
@test "AC-5: file documents what was skipped and why" {
  grep -q "## What we explicitly skipped" "${RECOMMENDED_MD}"
}

# -----------------------------------------------------------------------
# AC-6: file has a quarterly re-audit checklist
# -----------------------------------------------------------------------
@test "AC-6: file has a re-audit checklist" {
  grep -q "## Re-audit checklist" "${RECOMMENDED_MD}"
}

# -----------------------------------------------------------------------
# AC-7: SKILL.md links to recommended-tools.md
# -----------------------------------------------------------------------
@test "AC-7: SKILL.md links to recommended-tools.md" {
  grep -q "recommended-tools.md" "${SKILL_MD}"
}

# -----------------------------------------------------------------------
# AC-8: 'Last reviewed' date in recommended-tools.md is not older than
# 120 days (90-day quarterly cadence + 30-day grace period).
# This catches stale curation before downstream consumers do.
# The "0 < age_days <= 120" range (inclusive upper bound, strictly
# non-future lower bound) closes two regressions Copilot flagged:
#   1. A future "Last reviewed" date made age_days negative, which
#      satisfied `-lt 120` and bypassed the freshness gate. Reject
#      future-dated reviews.
#   2. `-lt 120` strictly excluded exactly-120-day-old reviews, even
#      though the comment promised "not older than 120 days". Switch
#      to `-le 120` so the boundary case passes as documented.
# -----------------------------------------------------------------------
@test "AC-8: Last reviewed date is within 120 days" {
  reviewed=$(grep -oE 'Last reviewed\*\*: [0-9]{4}-[0-9]{2}-[0-9]{2}' "${RECOMMENDED_MD}" \
    | head -1 \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
  [ -n "${reviewed}" ]

  # Compute days since reviewed using portable date math.
  if date --version 2>/dev/null | grep -q GNU; then
    reviewed_epoch=$(date -d "${reviewed}" +%s)
  else
    # BSD/macOS date
    reviewed_epoch=$(date -j -f "%Y-%m-%d" "${reviewed}" +%s)
  fi
  now_epoch=$(date +%s)
  age_days=$(( (now_epoch - reviewed_epoch) / 86400 ))

  # Reject future-dated reviews (negative age_days bypasses the upper
  # bound). 0 is acceptable — same-day review.
  [ "${age_days}" -ge 0 ]
  [ "${age_days}" -le 120 ]
}

# -----------------------------------------------------------------------
# AC-9 (gated): every upstream URL returns HTTP 200 via HEAD.
# Enable with: RECOMMENDED_TOOLS_LIVENESS=1 bats tests/skills/readme-craft-recommended-tools.bats
# Default-skipped to keep CI deterministic — upstream outages are not
# this PR's fault. Scheduled CI flips the flag on.
# -----------------------------------------------------------------------
@test "AC-9: every upstream URL responds with HTTP 200" {
  if [ -z "${RECOMMENDED_TOOLS_LIVENESS:-}" ]; then
    skip "set RECOMMENDED_TOOLS_LIVENESS=1 to enable network checks"
  fi

  # Extract every Upstream entry / Service URL / Source row.
  urls=$(grep -hE '^\| (Upstream entry|Service URL|Source) \|' "${RECOMMENDED_MD}" \
    | grep -oE 'https?://[^ )|]+' \
    | sort -u)

  [ -n "${urls}" ]

  failed=""
  while IFS= read -r url; do
    # Try HEAD first (cheap), GET as fallback. `-sSL` follows redirects,
    # so 301/302 should resolve to 200 here — but some servers respond
    # to HEAD with 405/403 even when GET succeeds (Vercel, some CDNs),
    # so any non-200 from HEAD also triggers the GET retry. Previously
    # 301/302 were treated as terminal-success along with 200; that
    # masked hosts that redirect on HEAD but succeed on GET.
    code=$(curl -sSL -o /dev/null -w '%{http_code}' -A "walter-os-readme-craft-tools-audit/1.0" -m 10 -I "${url}" || echo "000")
    if [ "${code}" != "200" ]; then
      # Retry with GET — covers HEAD-hostile hosts AND any final-state
      # check that HEAD's -sSL might have missed.
      code=$(curl -sSL -o /dev/null -w '%{http_code}' -A "walter-os-readme-craft-tools-audit/1.0" -m 10 "${url}" || echo "000")
    fi
    if [ "${code}" != "200" ]; then
      failed="${failed}\n  ✗ ${code} ${url}"
    fi
  done <<< "${urls}"

  if [ -n "${failed}" ]; then
    printf "URL liveness check failed for:%b\n" "${failed}" >&2
    return 1
  fi
}
