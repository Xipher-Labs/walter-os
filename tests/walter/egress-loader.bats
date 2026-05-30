#!/usr/bin/env bats
# tests/walter/egress-loader.bats
#
# OSS Trust A-2 (network egress allowlist) — AC-1 coverage.
# Spec: docs/specs/network-egress-allowlist.md
# Parent: #122 OSS Trust epic
#
# The egress-loader is the parser-half of the gate: it owns the file
# format (one host per line, `*.subdomain.example` wildcards, comments,
# blanks) and exposes `walter_egress_host_allowed <host>` which the
# `hooks/network-gate.sh` PreToolUse hook consumes.
#
# This file pins the SECURITY surface of the loader:
#   - Default-deny (missing file → all hosts denied)
#   - String-only matching (NO eval, NO shell expansion, NO regex eval
#     of operator-supplied patterns — only literal + single-label `*`)
#   - Wildcard does NOT cross dots (per spec D-5)
#   - Comments + blank lines ignored
#
# Modeled on tests/hooks/env-allowlist.bats (sibling helper from P1-09).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOADER="$REPO_ROOT/scripts/walter/lib/egress-loader.sh"
  [[ -f "$LOADER" ]] || skip "egress-loader.sh not present"

  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_CFG"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

# ---------------------------------------------------------------------------
# Default-deny posture (spec D-3): without an allowlist file every host
# is denied. This is the safe floor for first-install operators.
# ---------------------------------------------------------------------------

@test "AC-1: missing allowlist file → every host is denied (default-deny)" {
  # No file at all.
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 1 ]
}

@test "AC-1: empty allowlist file → every host is denied" {
  : > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Exact match (spec AC-1)
# ---------------------------------------------------------------------------

@test "AC-1: exact host match → allowed" {
  echo 'api.github.com' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 0 ]
}

@test "AC-1: non-matching host → denied" {
  echo 'api.github.com' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed evil.example"
  [ "$status" -eq 1 ]
}

@test "AC-1: case-insensitive match (DNS is case-insensitive)" {
  echo 'api.github.com' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed API.GitHub.com"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Wildcard semantics (spec D-5): `*.openrouter.ai` matches
# `api.openrouter.ai` but NOT `openrouter.ai` (root) and NOT
# `a.b.openrouter.ai` (two-deep).
# ---------------------------------------------------------------------------

@test "AC-1: wildcard matches a single-label subdomain" {
  echo '*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.openrouter.ai"
  [ "$status" -eq 0 ]
}

@test "AC-1: wildcard matches another single-label subdomain" {
  echo '*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed auth.openrouter.ai"
  [ "$status" -eq 0 ]
}

@test "AC-1: wildcard does NOT match the root domain itself" {
  # `*.openrouter.ai` requires a label before the dot. Per spec D-5,
  # operator must add `openrouter.ai` explicitly to cover the apex.
  echo '*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed openrouter.ai"
  [ "$status" -eq 1 ]
}

@test "AC-1: wildcard does NOT cross dots (no two-level match)" {
  # `*.openrouter.ai` must NOT match `a.b.openrouter.ai`. This is the
  # whole point of spec D-5 (vs Python fnmatch which lets `*` cross dots).
  echo '*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed a.b.openrouter.ai"
  [ "$status" -eq 1 ]
}

@test "AC-1: two-level wildcard (operator-explicit) matches two-label depth" {
  # Operator who wants two levels writes the second pattern explicitly.
  echo '*.*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed a.b.openrouter.ai"
  [ "$status" -eq 0 ]
}

@test "AC-1: two-level wildcard does NOT match single-level (depth is exact)" {
  echo '*.*.openrouter.ai' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.openrouter.ai"
  [ "$status" -eq 1 ]
}

@test "AC-1: combining root + wildcard line covers both apex and subdomains" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
openrouter.ai
*.openrouter.ai
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed openrouter.ai"
  [ "$status" -eq 0 ]
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.openrouter.ai"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# File format hygiene
# ---------------------------------------------------------------------------

@test "AC-1: comment lines are ignored" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
# This is a comment
api.github.com
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 0 ]
}

@test "AC-1: a comment line is NOT itself an allowlist entry" {
  # The string `# api.github.com` must not be treated as a literal entry
  # that matches the host `# api.github.com`. This pins the simple-minded
  # bug where a parser strips `#` only at the start of the COMMENT detect
  # but keeps the literal in the allowlist.
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
# api.github.com
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 1 ]
}

@test "AC-1: blank lines are ignored" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'

api.github.com


EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 0 ]
}

@test "AC-1: leading/trailing whitespace on entries is tolerated" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
   api.github.com
  pypi.org
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 0 ]
  run bash -c "source '$LOADER'; walter_egress_host_allowed pypi.org"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Anti-eval guarantees (the whole point of doing this in shell + literal
# string match is to avoid running operator-controlled data as code).
# ---------------------------------------------------------------------------

@test "AC-1: allowlist line with command-substitution is parsed LITERALLY (no exec)" {
  # If the loader were doing `source` or `eval` on the file, this would
  # execute `id` and capture its output. We must treat the line as a
  # literal string that won't match any real host.
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
$(id).example
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed 'uid-0.example'"
  [ "$status" -eq 1 ]
  # And the literal must also NOT match a real lookup of `$(id).example`
  # (in case bash expansion sneaks in somewhere).
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 1 ]
}

@test "AC-1: backtick-substitution entry is parsed literally" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
`whoami`.example
EOF
  run bash -c "source '$LOADER'; walter_egress_host_allowed root.example"
  [ "$status" -eq 1 ]
}

@test "AC-1: wildcard star alone is NOT a catch-all (multi-label host)" {
  # A bare `*` line must not match any host. Operators who genuinely want
  # to disable the gate set WALTER_EGRESS_ALLOW_OVERRIDE=1 instead.
  echo '*' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed api.github.com"
  [ "$status" -eq 1 ]
}

@test "AC-1 (R2): bare * does NOT match single-label hosts like 'localhost' either" {
  # R2 finding: under per-label semantics, a 1-label `*` would otherwise
  # match every 1-label hostname (`localhost`, any private hostname).
  # The loader must explicitly reject the 1-label `*` case.
  echo '*' > "$TMP_CFG/egress-allowlist.txt"
  for h in localhost myserver vm intranet-host; do
    run bash -c "source '$LOADER'; walter_egress_host_allowed '$h'"
    [ "$status" -eq 1 ] || { echo "expected DENY for '$h', got $status"; return 1; }
  done
}

@test "AC-1 (R2): mid-label '*' is treated as LITERAL string, not fnmatch glob" {
  # Pattern `a*b.example.com` matches the LITERAL host whose first label
  # is `a*b` (rare but valid), NOT `axb.example.com` (which would only
  # match under fnmatch-style semantics). Pins per-label whole-token
  # `*`-vs-literal compare so a future refactor that adds fnmatch fails
  # this test.
  echo 'a*b.example.com' > "$TMP_CFG/egress-allowlist.txt"
  # Literal `a*b` host → match (the pattern matches its own literal).
  run bash -c "source '$LOADER'; walter_egress_host_allowed 'a*b.example.com'"
  [ "$status" -eq 0 ]
  # fnmatch-style `axb` → DENY (no expansion).
  run bash -c "source '$LOADER'; walter_egress_host_allowed 'axb.example.com'"
  [ "$status" -eq 1 ]
  run bash -c "source '$LOADER'; walter_egress_host_allowed 'ab.example.com'"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Multi-entry sanity
# ---------------------------------------------------------------------------

@test "AC-1: realistic multi-entry allowlist allows the entries + denies others" {
  cat > "$TMP_CFG/egress-allowlist.txt" <<'EOF'
# Walter-OS bootstrap allowlist
api.github.com
github.com
*.githubusercontent.com
registry.npmjs.org
pypi.org
EOF
  for host in api.github.com github.com objects.githubusercontent.com raw.githubusercontent.com registry.npmjs.org pypi.org; do
    run bash -c "source '$LOADER'; walter_egress_host_allowed '$host'"
    [ "$status" -eq 0 ] || { echo "expected allow for $host, got $status"; return 1; }
  done
  for host in evil.example attacker.io fooobar.net; do
    run bash -c "source '$LOADER'; walter_egress_host_allowed '$host'"
    [ "$status" -eq 1 ] || { echo "expected deny for $host, got $status"; return 1; }
  done
}

@test "AC-1: empty host argument is denied (defensive)" {
  echo 'api.github.com' > "$TMP_CFG/egress-allowlist.txt"
  run bash -c "source '$LOADER'; walter_egress_host_allowed ''"
  [ "$status" -eq 1 ]
}
