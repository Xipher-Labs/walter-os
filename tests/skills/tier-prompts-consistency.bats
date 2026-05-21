#!/usr/bin/env bats
# tests/skills/tier-prompts-consistency.bats
#
# Covers AC11 of docs/specs/agent-install-tier-completion.md:
#   AC11: Plane project naming in tier-4.md matches the canonical form
#         used in docs/specs/multi-agent-autonomy.md.
#
# docs/specs/multi-agent-autonomy.md defines context labels as:
#   context:{work,projects-personal,personal,medical}
#
# Therefore the prompt must reference 'projects-personal', not
# 'personal-projects'.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
TIER4_MD="${REPO_ROOT}/setup/agent-install/tier-4.md"
CANON_SPEC="${REPO_ROOT}/docs/specs/multi-agent-autonomy.md"

setup() {
  [ -f "$TIER4_MD" ] || skip "tier-4.md not present"
  [ -f "$CANON_SPEC" ] || skip "multi-agent-autonomy.md spec not present"
}

# -----------------------------------------------------------------------
# AC11: positive — canonical form present
# -----------------------------------------------------------------------
@test "AC11: tier-4.md uses canonical 'projects-personal'" {
  grep -q "projects-personal" "$TIER4_MD"
}

# -----------------------------------------------------------------------
# AC11: negative — incorrect form NOT present in any USE context.
# Educational mentions documenting the wrong-form pitfall (lines that
# say "NOT 'personal-projects'") are allowed; bare uses are not.
# Strip educational lines first, then assert no remaining matches.
# -----------------------------------------------------------------------
@test "AC11: tier-4.md does NOT use 'personal-projects' (except in NOT-prefixed callout)" {
  # Find lines that mention 'personal-projects' but NOT preceded by NOT.
  bad_lines=$(grep -n "personal-projects" "$TIER4_MD" | grep -v 'NOT "personal-projects"' | grep -v "NOT 'personal-projects'" || true)
  if [ -n "$bad_lines" ]; then
    printf "tier-4.md uses 'personal-projects' outside a NOT-prefixed callout:\n%s\n" "$bad_lines" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# Cross-spec consistency: the canonical spec must also use this form.
# If multi-agent-autonomy.md ever shifts to a different name, this test
# catches the drift before tier-4.md silently goes out of date.
# -----------------------------------------------------------------------
@test "AC11: canonical spec multi-agent-autonomy.md uses 'projects-personal'" {
  grep -q "projects-personal" "$CANON_SPEC"
}
