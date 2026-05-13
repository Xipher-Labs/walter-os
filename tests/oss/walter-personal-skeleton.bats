#!/usr/bin/env bats
# tests/oss/walter-personal-skeleton.bats
# Assertions for walter-personal-skeleton (PR #49, v0.2.0 OSS launch chain).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SKELETON="$REPO_ROOT/contexts/_examples/walter-personal-skeleton"
  SCRIPT="$REPO_ROOT/setup/personal-overlay-init.sh"
}

# ---------------------------------------------------------------------------
# AC-1: Skeleton directory contains all required files
# ---------------------------------------------------------------------------

@test "AC-1: skeleton directory exists" {
  [ -d "$SKELETON" ]
}

@test "AC-1: skeleton contains README.md" {
  [ -f "$SKELETON/README.md" ]
}

@test "AC-1: skeleton contains INSTALL.md" {
  [ -f "$SKELETON/INSTALL.md" ]
}

@test "AC-1: skeleton contains .gitignore" {
  [ -f "$SKELETON/.gitignore" ]
}

@test "AC-1: skeleton contains personal.env.template" {
  [ -f "$SKELETON/personal.env.template" ]
}

@test "AC-1: skeleton contains contexts/work/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/work/AGENTS.md.template" ]
}

@test "AC-1: skeleton contains contexts/projects-personal/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/projects-personal/AGENTS.md.template" ]
}

@test "AC-1: skeleton contains contexts/personal/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/personal/AGENTS.md.template" ]
}

# ---------------------------------------------------------------------------
# AC-2/AC-3: personal-overlay-init.sh --help mentions new flags
# ---------------------------------------------------------------------------

@test "AC-2: --help output mentions --from-skeleton" {
  "$SCRIPT" --help | grep -q '\-\-from-skeleton'
}

@test "AC-3: --help output mentions --git-clone" {
  "$SCRIPT" --help | grep -q '\-\-git-clone'
}

# ---------------------------------------------------------------------------
# AC-2: --from-skeleton --dry-run creates no files
# ---------------------------------------------------------------------------

@test "AC-2: --from-skeleton --dry-run creates no files" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOME="$tmpdir" "$SCRIPT" --from-skeleton --dry-run >/dev/null 2>&1 || true
  local count
  count="$(find "$tmpdir" -mindepth 1 | wc -l | tr -d ' ')"
  rm -rf "$tmpdir"
  [ "$count" -eq 0 ]
}

@test "AC-2: --from-skeleton --dry-run prints copy plan" {
  local output
  output="$(HOME="$(mktemp -d)" "$SCRIPT" --from-skeleton --dry-run 2>&1 || true)"
  echo "$output" | grep -qi 'dry'
}

# ---------------------------------------------------------------------------
# AC-3: --git-clone --dry-run creates no files and prints clone command
# ---------------------------------------------------------------------------

@test "AC-3: --git-clone URL --dry-run creates no files" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOME="$tmpdir" "$SCRIPT" --git-clone https://example.com/foo.git --dry-run \
    >/dev/null 2>&1 || true
  local count
  count="$(find "$tmpdir" -mindepth 1 | wc -l | tr -d ' ')"
  rm -rf "$tmpdir"
  [ "$count" -eq 0 ]
}

@test "AC-3: --git-clone URL --dry-run mentions the clone command" {
  local output
  tmpdir="$(mktemp -d)"
  output="$(HOME="$tmpdir" "$SCRIPT" \
    --git-clone https://example.com/foo.git --dry-run 2>&1 || true)"
  rm -rf "$tmpdir"
  echo "$output" | grep -qi 'clone'
}

# ---------------------------------------------------------------------------
# AC-4: docs updated
# ---------------------------------------------------------------------------

@test "AC-4: universal-vs-personal-config.md contains 'Operator-private git repo' section" {
  grep -q 'Operator-private git repo' \
    "$REPO_ROOT/docs/operational/universal-vs-personal-config.md"
}

# ---------------------------------------------------------------------------
# AC-5: skeleton .gitignore excludes .env and secrets/
# ---------------------------------------------------------------------------

@test "AC-5: .gitignore excludes '.env'" {
  grep -q '^\.env$' "$SKELETON/.gitignore"
}

@test "AC-5: .gitignore excludes 'secrets/'" {
  grep -q '^secrets/$' "$SKELETON/.gitignore"
}

# ---------------------------------------------------------------------------
# AC-6: No operator-specific values in skeleton files
# ---------------------------------------------------------------------------

@test "AC-6: skeleton contains no xipherlabs references" {
  local count
  count="$(grep -rl 'xipherlabs' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-6: skeleton contains no nicofernandez references" {
  local count
  count="$(grep -rl 'nicofernandez' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-6: skeleton contains no f0x1777 references" {
  local count
  count="$(grep -rl 'f0x1777' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
