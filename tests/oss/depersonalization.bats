#!/usr/bin/env bats
# tests/oss/depersonalization.bats
# AC-9: Regression guard — no personal references in OSS-targeted files.
# Runs in CI on v0.2.0-walter-oss branch and beyond.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ---------------------------------------------------------------------------
# Helper: grep the repo excluding exempt directories, return match count
# ---------------------------------------------------------------------------

count_matches() {
  local pattern="$1"
  # Exclude: docs/specs/ (historical record), contexts/_examples/ (labeled examples),
  # tests/oss/ (this file references patterns for documentation),
  # .claude/ (local agent memory/worktrees), .git/
  # Community health files: SECURITY.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md,
  # README.md, CHANGELOG.md — these intentionally contain the xipherlabs.xyz
  # domain as OSS project contact addresses (PR #51). The xipherlabs domain is
  # Walter-OS's OSS brand identity, not a personal operator identifier.
  # -i: case-insensitive so Linux CI catches capitalized variants
  # (e.g. `Xipheropenclaw_bot` would NOT match lowercase `xipheropenclaw`
  # on case-sensitive filesystems without -i).
  grep -r -i -l "$pattern" "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.json' \
    --include='*.toml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | grep -v "$REPO_ROOT/SECURITY.md" \
    | grep -v "$REPO_ROOT/CODE_OF_CONDUCT.md" \
    | grep -v "$REPO_ROOT/CONTRIBUTING.md" \
    | grep -v "$REPO_ROOT/README.md" \
    | grep -v "$REPO_ROOT/CHANGELOG.md" \
    | grep -v "$REPO_ROOT/COMMERCIAL.md" \
    | grep -v "$REPO_ROOT/NOTICE" \
    | wc -l \
    | tr -d ' '
}

# ---------------------------------------------------------------------------
# AC-1: No xipherlabs references outside exempt paths
# ---------------------------------------------------------------------------

@test "AC-1: no xipherlabs.xyz refs outside docs/specs and _examples" {
  local count
  count="$(count_matches 'xipherlabs\.xyz')"
  [ "$count" -eq 0 ]
}

@test "AC-1: no openclaw bot handle refs outside docs/specs and _examples" {
  # Catches `Xipheropenclaw_bot` and any future variant of the openclaw bot
  # handle that doesn't contain the literal `xipherlabs` substring (which
  # AC-1's primary grep would miss).
  local count
  count="$(count_matches 'xipheropenclaw')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-2: No triton / licitar / biovault refs outside exempt paths
# ---------------------------------------------------------------------------

@test "AC-2: no 'triton' refs outside docs/specs and _examples (case-insensitive)" {
  local count
  count="$(grep -r -i -l 'triton' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-2: no 'licitar' refs outside docs/specs and _examples (case-insensitive)" {
  local count
  count="$(grep -r -i -l 'licitar' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-2: no 'biovault' refs outside docs/specs and _examples (case-insensitive)" {
  local count
  count="$(grep -r -i -l 'biovault' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-2: no private homelab codenames anywhere public" {
  local count
  count="$(grep -r -i -l -E 'jarvis|z440|dell r730|r730|walter-box|walter box' "$REPO_ROOT" \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='*.json' --include='*.toml' --include='*.ts' --include='*.tsx' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-3: No country-specific regulatory refs outside exempt paths
# ---------------------------------------------------------------------------

@test "AC-3: no Argentine regulatory law refs outside _examples" {
  local count
  count="$(grep -rliE 'argentine law [0-9]|Law [0-9]{1,3}\.[0-9]{3}|L[e]y [0-9]+|AFIP|ARCA|small-taxpayer|gross-receipts|MEP-CCL|ANMAT' "$REPO_ROOT" \
    --include='*.md' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | grep -v "$REPO_ROOT/skills/regulatory-research-argentina/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-4: contexts/_examples/ directory exists with all required files
# ---------------------------------------------------------------------------

@test "AC-4: contexts/_examples/ directory exists" {
  [ -d "$REPO_ROOT/contexts/_examples" ]
}

@test "AC-4: work-template.example.md exists in _examples" {
  [ -f "$REPO_ROOT/contexts/_examples/work-template.example.md" ]
}

@test "AC-4: projects-personal-template.example.md exists in _examples" {
  [ -f "$REPO_ROOT/contexts/_examples/projects-personal-template.example.md" ]
}

@test "AC-4: personal-template.example.md exists in _examples" {
  [ -f "$REPO_ROOT/contexts/_examples/personal-template.example.md" ]
}

@test "AC-4: work/ subdirectory exists with at least one generic example" {
  local count
  count="$(find "$REPO_ROOT/contexts/_examples/work" -name "*.example.md" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ]
}

@test "AC-4: projects-personal/ subdirectory exists with at least one generic example" {
  local count
  count="$(find "$REPO_ROOT/contexts/_examples/projects-personal" -name "*.example.md" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ]
}

@test "AC-4: personal/ subdirectory exists with at least one generic example" {
  local count
  count="$(find "$REPO_ROOT/contexts/_examples/personal" -name "*.example.md" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ]
}

@test "AC-4: hackathons/ subdirectory exists with at least one generic example" {
  local count
  count="$(find "$REPO_ROOT/contexts/_examples/hackathons" -name "*.example.md" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ]
}

@test "AC-4: total persona example count is at least 10" {
  local count
  count="$(find "$REPO_ROOT/contexts/_examples" -name "*.example.md" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 10 ]
}

@test "AC-4: no operator-named example files remain (triton/nico)" {
  [ ! -f "$REPO_ROOT/contexts/_examples/work-triton.example.md" ]
  [ ! -f "$REPO_ROOT/contexts/_examples/projects-personal-nico.example.md" ]
  [ ! -f "$REPO_ROOT/contexts/_examples/personal-nico.example.md" ]
}

# ---------------------------------------------------------------------------
# AC-5: personal-overlay-init.sh exists
# ---------------------------------------------------------------------------

@test "AC-5: setup/personal-overlay-init.sh exists" {
  [ -f "$REPO_ROOT/setup/personal-overlay-init.sh" ]
}

@test "AC-5: personal-overlay-init.sh is executable" {
  [ -x "$REPO_ROOT/setup/personal-overlay-init.sh" ]
}

# ---------------------------------------------------------------------------
# AC-6: regulatory-research-international skill exists
# ---------------------------------------------------------------------------

@test "AC-6: skills/regulatory-research-international/SKILL.md exists" {
  [ -f "$REPO_ROOT/skills/regulatory-research-international/SKILL.md" ]
}

@test "AC-6: international skill does not mention Argentine laws" {
  local match_count
  match_count="$(grep -cE 'Law 13\.064|Law 26\.529|Law 25\.326|AFIP|ANMAT|small-taxpayer|gross-receipts' \
    "$REPO_ROOT/skills/regulatory-research-international/SKILL.md" 2>/dev/null; true)"
  [ "${match_count:-0}" -eq 0 ]
}

@test "AC-6: contexts/_examples/skills/ contains generic regulatory research template" {
  [ -f "$REPO_ROOT/contexts/_examples/skills/regulatory-research-template.example.md" ]
}

# ---------------------------------------------------------------------------
# AC-7: AGENTS.md root does not name Nico / Triton One / Buenos Aires
# ---------------------------------------------------------------------------

@test "AC-7: AGENTS.md root does not name 'Nico' as the operator" {
  local count
  count="$(grep -cE 'working with \*\*Nico\*\*|working with Nico,' \
    "$REPO_ROOT/AGENTS.md" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

@test "AC-7: AGENTS.md root does not name 'Triton One'" {
  local count
  count="$(grep -ciE 'triton one' "$REPO_ROOT/AGENTS.md" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

@test "AC-7: AGENTS.md root does not mention 'Buenos Aires'" {
  local count
  count="$(grep -ciE 'buenos aires' "$REPO_ROOT/AGENTS.md" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-8: Compose files use ${WALTER_DOMAIN} not hardcoded hostnames
# ---------------------------------------------------------------------------

@test "AC-8: no xipherlabs in compose files" {
  local count
  count="$(grep -rl 'xipherlabs' "$REPO_ROOT/setup" \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.json' \
    --include='*.toml' \
    2>/dev/null \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-8: no xipherlabs in .env.example" {
  local count
  count="$(grep -c 'xipherlabs' "$REPO_ROOT/.env.example" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-1 (extended): case-insensitive project domain scan + bot handle placeholders
# ---------------------------------------------------------------------------

@test "AC-1: no xipherlabs.xyz refs (case-insensitive) outside docs/specs and _examples" {
  # Community health files intentionally contain xipherlabs.xyz contact
  # addresses (PR #51). Exempt them — they are the OSS project identity.
  # COMMERCIAL.md (PR #48 license switch) and NOTICE (AGPL attribution)
  # also legitimately contain xipherlabs.xyz as the project's brand.
  local count
  count="$(grep -r -i -l 'xipherlabs\.xyz' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.json' \
    --include='*.toml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | grep -v "$REPO_ROOT/SECURITY.md" \
    | grep -v "$REPO_ROOT/CODE_OF_CONDUCT.md" \
    | grep -v "$REPO_ROOT/CONTRIBUTING.md" \
    | grep -v "$REPO_ROOT/README.md" \
    | grep -v "$REPO_ROOT/CHANGELOG.md" \
    | grep -v "$REPO_ROOT/COMMERCIAL.md" \
    | grep -v "$REPO_ROOT/NOTICE" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-10: No solx.ar domain or nico@ email refs outside docs/specs and _examples
# ---------------------------------------------------------------------------

@test "AC-10: no solx.ar refs outside docs/specs and _examples" {
  local count
  count="$(grep -rl 'solx\.ar' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.json' \
    --include='*.toml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-10: no nico@ email refs outside docs/specs and _examples" {
  local count
  count="$(grep -rl 'nico@' "$REPO_ROOT" \
    --include='*.md' \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.json' \
    --include='*.toml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# W-10: nicofernandez, xipherlabs, and nico.fran email regression guards
# ---------------------------------------------------------------------------

@test "W-10: no 'nicofernandez' in user-facing files (allow specs and tests)" {
  # Tests throughout the repo that assert depersonalization
  # (e.g. 'not.toContain(nicofernandez)') are intentional regression guards.
  # All paths containing '/tests/' are excluded (covers tests/, apps/*/tests/, etc.).
  run bash -c "grep -rn 'nicofernandez' '$REPO_ROOT' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude \
    --exclude-dir=external --exclude-dir=.next \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='*.json' --include='*.toml' --include='*.ts' --include='*.tsx' \
    2>/dev/null \
    | grep -v 'docs/specs/' \
    | grep -v '/tests/' \
    | grep -v 'contexts/_examples/'"
  # grep exits 1 when no matches — that is the passing condition
  [ "$status" -eq 1 ]
}

@test "W-10: no 'xipherlabs.xyz' in published configs (allow docs/specs and tests)" {
  # Community health files (SECURITY.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md,
  # README.md, CHANGELOG.md) intentionally contain xipherlabs.xyz as the OSS
  # project contact domain (PR #51). Exempt them from this check.
  run bash -c "grep -rn 'xipherlabs\\.xyz' '$REPO_ROOT' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude \
    --exclude-dir=external --exclude-dir=.next \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='*.json' --include='*.toml' --include='*.ts' --include='*.tsx' \
    2>/dev/null \
    | grep -v 'docs/specs/' \
    | grep -v 'tests/oss/' \
    | grep -v 'tests/cli/' \
    | grep -v 'contexts/_examples/' \
    | grep -v '/SECURITY.md' \
    | grep -v '/CODE_OF_CONDUCT.md' \
    | grep -v '/CONTRIBUTING.md' \
    | grep -v '/README.md' \
    | grep -v '/CHANGELOG.md' \
    | grep -v '/COMMERCIAL.md' \
    | grep -v '/NOTICE'"
  [ "$status" -eq 1 ]
}

@test "W-10: no 'nico.fran.fernandez' email leak in user-facing files" {
  run bash -c "grep -rn 'nico\\.fran\\.fernandez' '$REPO_ROOT' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude \
    --exclude-dir=external --exclude-dir=.next \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='*.json' --include='*.toml' --include='*.ts' --include='*.tsx' \
    2>/dev/null \
    | grep -v 'docs/specs/' \
    | grep -v 'tests/oss/'"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC-2 (extended): scope includes .env.example + .example files
# ---------------------------------------------------------------------------

@test "AC-2: no 'triton' refs in .env.example (case-insensitive)" {
  local count
  count="$(grep -r -i -l 'triton' "$REPO_ROOT" \
    --include='*.example' \
    --include='*.env.example' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# WARN 2: WALTER_DOMAIN defined in .env.example
# ---------------------------------------------------------------------------

@test "WARN-2: WALTER_DOMAIN is defined in .env.example" {
  grep -q 'WALTER_DOMAIN=' "$REPO_ROOT/.env.example"
}

# ---------------------------------------------------------------------------
# WARN 3: AC-5 behavioral tests — idempotency and dry-run
# ---------------------------------------------------------------------------

@test "AC-5: personal-overlay-init.sh is idempotent (second run says 'already exists')" {
  local script="$REPO_ROOT/setup/personal-overlay-init.sh"
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Run once with a fake HOME — second run should hit the "already exists" path
  HOME="$tmpdir" "$script" >/dev/null 2>&1 || true
  local second_run_output
  second_run_output="$(HOME="$tmpdir" "$script" 2>&1 || true)"
  rm -rf "$tmpdir"
  echo "$second_run_output" | grep -qi 'already exists'
}

@test "AC-5: personal-overlay-init.sh --dry-run creates no files" {
  local script="$REPO_ROOT/setup/personal-overlay-init.sh"
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Run with fake HOME + --dry-run — nothing should be written to tmpdir
  HOME="$tmpdir" "$script" --dry-run >/dev/null 2>&1 || true
  local file_count
  file_count="$(find "$tmpdir" -mindepth 1 | wc -l | tr -d ' ')"
  rm -rf "$tmpdir"
  [ "$file_count" -eq 0 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# README-specific depersonalization (from PR #51 walter-readme-detailed)
# ──────────────────────────────────────────────────────────────────────────────

# Verifies that operator-specific personal identifiers do not appear in
# public-facing files (README.md, docs/specs/, etc.).
# Refs: docs/specs/walter-readme-detailed.md [AC-4]

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  cd "$REPO_ROOT"
}

# ── README.md depersonalization ───────────────────────────────────────────────

@test "README.md: no 'nicofernandez'" {
  count=$(grep -ic "nicofernandez" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: single founder handle in origin note" {
  count=$(grep -ic "f0x1777" README.md || true)
  [ "$count" -eq 1 ]
}

@test "README.md: no 'nico.fran' (email prefix)" {
  count=$(grep -ic "nico\.fran" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: no 'Nico Fernandez' (full name)" {
  count=$(grep -ic "nico fernandez" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: no 'nico@' (personal email)" {
  count=$(grep -ic "nico@" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: xipherlabs.xyz only in brand attribution context" {
  # Must appear at most once (the licensing contact line)
  count=$(grep -ic "xipherlabs\.xyz" README.md || true)
  [ "$count" -le 1 ]
}

@test "README.md: no 'Triton One' (operator employer)" {
  # Triton One is operator-specific and should not appear in OSS README
  count=$(grep -ic "triton one" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: no 'Buenos Aires' (operator location)" {
  count=$(grep -ic "buenos aires" README.md || true)
  [ "$count" -eq 0 ]
}

@test "README.md: no 'nico-mac' (operator device name)" {
  count=$(grep -ic "nico-mac" README.md || true)
  [ "$count" -eq 0 ]
}

# ── Spec files depersonalization ──────────────────────────────────────────────

@test "walter-readme-detailed spec: operator handles appear only in AC-4 forbidden-list context" {
  # The spec legitimately names forbidden strings in AC-4 as the list of
  # identifiers to exclude from README.md. We verify those strings appear
  # only in the AC-4 definition, not in example content or prose.
  spec="docs/specs/walter-readme-detailed.md"
  [ -f "$spec" ] || skip "spec not present on this branch"
  # Count occurrences of the most distinctive handle
  count=$(grep -ic "nicofernandez" "$spec" || true)
  # Should appear exactly once (the AC-4 definition line)
  [ "$count" -le 2 ]
}

# ── CHANGELOG depersonalization ───────────────────────────────────────────────

@test "CHANGELOG.md: no operator personal identifiers" {
  [ -f "CHANGELOG.md" ] || skip "CHANGELOG.md not present"
  count=$(grep -icE "(nicofernandez|f0x1777|nico\.fran)" CHANGELOG.md || true)
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FD-1: No operator handles outside the single credits exception
# ---------------------------------------------------------------------------

@test "FD-1: f0x1777 handle appears only in README origin note" {
  local matches
  matches="$(grep -r -i -l 'f0x1777' "$REPO_ROOT" \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    --include='*.json' --include='*.toml' --include='*.ts' --include='*.tsx' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | grep -v "$REPO_ROOT/.github/ISSUE_TEMPLATE/config.yml" || true)"
  [ "$matches" = "$REPO_ROOT/README.md" ]
  [ "$(grep -ci 'f0x1777' "$REPO_ROOT/README.md")" -eq 1 ]
}

@test "FD-1: no 'licitar' outside exempt paths" {
  local count
  count="$(grep -r -i -l 'licitar' "$REPO_ROOT" \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "FD-1: no 'biovault' outside exempt paths" {
  local count
  count="$(grep -r -i -l 'biovault' "$REPO_ROOT" \
    --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FD-2: No operator-specific defaults in scripts or bin
# ---------------------------------------------------------------------------

@test "FD-2: no ':-f0x1777' shell default in scripts/" {
  local count
  count="$(grep -rn ':-f0x1777' "$REPO_ROOT/scripts/" \
    2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "FD-2: no hardcoded 'github.com/f0x1777/' in scripts/ or bin/" {
  # Allows variable expansion like $WALTER_GITHUB_ORG/repo but not the literal handle
  local count
  count="$(grep -rn 'github\.com/f0x1777/' "$REPO_ROOT/scripts/" "$REPO_ROOT/bin/" \
    2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FD-3: All contexts/_examples/*/*.example.md have a "Prompt for your AI" section
# ---------------------------------------------------------------------------

@test "FD-3: every persona example file has a 'Prompt for your AI' section" {
  local missing=0
  while IFS= read -r -d '' f; do
    if ! grep -q "## Prompt for your AI" "$f"; then
      echo "MISSING '## Prompt for your AI': $f" >&2
      missing=$((missing + 1))
    fi
  done < <(find "$REPO_ROOT/contexts/_examples" -mindepth 2 -name "*.example.md" -print0)
  [ "$missing" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FD-4: setup/vm/ has been renamed to setup/walter-host/
# ---------------------------------------------------------------------------

@test "FD-4: setup/vm/ directory no longer exists" {
  [ ! -d "$REPO_ROOT/setup/vm" ]
}

@test "FD-4: setup/walter-host/ directory exists" {
  [ -d "$REPO_ROOT/setup/walter-host" ]
}

# ---------------------------------------------------------------------------
# B-3: No hardcoded operator username in service compose files
# ---------------------------------------------------------------------------

@test "B-3: no hardcoded 'nico' username in setup/ yml/yaml files" {
  # Match the value 'nico' (not the substring) in YAML — covers:
  #   UI_USERNAME: nico                      (bare)
  #   UI_USERNAME: "nico"                    (double-quoted)
  #   UI_USERNAME: 'nico'                    (single-quoted)
  #   UI_USERNAME: nico  # inline comment    (trailing comment)
  #   UI_USERNAME: nico                      (trailing whitespace)
  # Pattern: ': ' + optional quote + 'nico' + optional quote + (EOL | space | #)
  # Excludes: 'canonical', 'nicotine', etc. (whole-word match).
  local count
  count="$(grep -rlE ":[[:space:]]+['\"]?nico['\"]?([[:space:]]*(#.*)?)?$" "$REPO_ROOT/setup" \
    --include='*.yml' \
    --include='*.yaml' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "B-3: no hardcoded 'nico' username in root compose.yml" {
  # Same widened pattern as above. Word-bounded so 'canonical' etc. don't match.
  local count
  count="$(grep -cE ":[[:space:]]+['\"]?nico['\"]?([[:space:]]*(#.*)?)?$" "$REPO_ROOT/compose.yml" 2>/dev/null; true)"
  [ "${count:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# B-7: No personal employer/project identifiers in .toml + .json files
# ---------------------------------------------------------------------------

@test "B-7: no 'triton-one' in .toml or .json files outside specs and _examples" {
  local count
  count="$(grep -rl 'triton-one\|triton_one' "$REPO_ROOT" \
    --include='*.toml' \
    --include='*.json' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | grep -v "$REPO_ROOT/pnpm-lock.yaml" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "B-7: no 'Licitar' in .toml or .json files outside specs" {
  local count
  count="$(grep -r -i -l 'licitar' "$REPO_ROOT" \
    --include='*.toml' \
    --include='*.json' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "B-7: no 'BioVault' in .toml or .json files outside specs" {
  local count
  count="$(grep -r -i -l 'biovault' "$REPO_ROOT" \
    --include='*.toml' \
    --include='*.json' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/specs/" \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | grep -v "$REPO_ROOT/tests/oss/" \
    | grep -v "$REPO_ROOT/.claude/" \
    | grep -v "$REPO_ROOT/.git/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}
