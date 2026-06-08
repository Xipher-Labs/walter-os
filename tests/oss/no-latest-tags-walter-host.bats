#!/usr/bin/env bats
# tests/oss/no-latest-tags-walter-host.bats
#
# Audit P1-01 / P1-02 regression coverage: no service in
# `setup/walter-host/services/**` may pin a runtime dependency to
# `:latest`, `:stable`, or `@latest`. Each finding here would silently
# pull a new upstream version on the next `docker compose pull` /
# `docker compose up` / Dockerfile rebuild.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SERVICES_DIR="$REPO_ROOT/setup/walter-host/services"

# Filter helpers — strip lines that are obviously not pinned-dep refs.
#
# IMPORTANT: `grep -rn` prefixes every match with `path:line:`. The lines
# we filter look like
#     setup/walter-host/services/foo/compose.yml:42:    image: foo:latest
# so any anchor against the START of the line must match `path:line:`,
# NOT the source-code start. We strip the prefix before filtering instead.
#
# Filter rules (applied to the content portion of each match):
# - leading whitespace + '#'  : commented-out compose / Dockerfile lines
# - walter-control-tower:latest : LOCAL build image, not a registry pull;
#                                 tracked separately, low supply-chain risk
# - 'image: ghcr.io/xqdoo00o/chatgpt-to-api:latest' inside a comment block
#   in llm-proxies/compose.yml: opt-in alternative documented but not used.
#
# Any new exception MUST be exact-match scoped here and justified in
# the PR body that adds it. Do not add broad substring exclusions:
# `image: evil:latest # migration:latest` must still fail.
_filter_known_exceptions() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*image:[[:space:]]+walter-control-tower:latest([[:space:]]|$)/ { next }
    /^[[:space:]]*image:[[:space:]]+ghcr[.]io\/xqdoo00o\/chatgpt-to-api:latest([[:space:]]|$)/ { next }
    { print }
  '
}

# Token-boundary helper: we previously used `\b`, which grep BRE/ERE
# interprets as a backspace character, NOT a word boundary (Copilot R1).
# Instead we anchor on end-of-line OR a non-tag-character (`[^A-Za-z0-9_.-]`)
# right after the tag. Tag chars are letters / digits / `_` / `.` / `-`.
# Anything else (`"`, `'`, whitespace, end-of-line) is a real boundary.
TAG_BOUNDARY='($|[^A-Za-z0-9_.-])'
OPENCLAW_BARE_INSTALL_PATTERN='npm install -g openclaw($|[[:space:];#&|])'

# Strip the `path:line:` prefix from grep -rn output so NOISE_PATTERN's
# leading-`#` rule actually applies to the content of the matched line.
# Used by the three regression checks below.
_strip_grep_prefix() {
  # path:line:content → content (POSIX awk).
  awk -F: '{ for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF ? ":" : "\n") }'
}

# Run grep -rn AND treat exit 2 (I/O error, unsupported flag) as a
# hard FAIL, not as "no matches" — Copilot R1 flagged that the previous
# `if [ "$status" -eq 0 ]` arm silently passed on grep errors.
_assert_no_unfiltered_matches() {
  local label="$1"
  shift
  run grep -rn "$@"
  if [ "$status" -eq 1 ]; then
    # No matches — pass.
    return 0
  fi
  if [ "$status" -ne 0 ]; then
    echo "FAIL: grep returned unexpected exit status $status for $label" >&2
    echo "$output" >&2
    return 1
  fi
  # status == 0: matches found. Filter only exact known exceptions.
  filtered="$(printf '%s\n' "$output" | _strip_grep_prefix | _filter_known_exceptions)"
  if [ -n "$filtered" ]; then
    echo "FAIL: $label" >&2
    echo "$filtered" >&2
    return 1
  fi
  return 0
}

@test "latest-tag filter keeps real findings with exception text in comments" {
  filtered="$(printf '%s\n' '    image: registry.example/app:latest # migration:latest' | _filter_known_exceptions)"

  [[ "$filtered" == *'registry.example/app:latest'* ]]
}

@test "latest-tag filter drops exact local Control Tower image exception" {
  filtered="$(printf '%s\n' '    image: walter-control-tower:latest' | _filter_known_exceptions)"

  [[ -z "$filtered" ]]
}

@test "openclaw bare-install pattern catches end-of-line install" {
  printf '%s\n' 'npm install -g openclaw' | grep -Eq "$OPENCLAW_BARE_INSTALL_PATTERN"
  if printf '%s\n' 'npm install -g openclaw@2026.5.7' | grep -Eq "$OPENCLAW_BARE_INSTALL_PATTERN"; then
    return 1
  fi
}

@test "no compose service uses :latest tag (P1-02)" {
  _assert_no_unfiltered_matches \
    "unpinned :latest image tag(s) found" \
    -E "image:[^#]*:latest${TAG_BOUNDARY}" \
    "$SERVICES_DIR" --include='compose.yml' --include='compose.*.yml'
}

@test "no compose service uses :stable tag (P1-02)" {
  _assert_no_unfiltered_matches \
    "unpinned :stable image tag(s) found" \
    -E "image:[^#]*:stable${TAG_BOUNDARY}" \
    "$SERVICES_DIR" --include='compose.yml' --include='compose.*.yml'
}

@test "no Dockerfile uses @latest in npm install (P1-01)" {
  _assert_no_unfiltered_matches \
    "npm install @latest found in Dockerfile(s)" \
    -E "npm install[^#]*@latest${TAG_BOUNDARY}" \
    "$SERVICES_DIR" --include='Dockerfile*'
}

@test "openclaw compose pins openclaw npm package to a version (P1-01)" {
  local compose="$SERVICES_DIR/openclaw/compose.yml"
  [ -f "$compose" ]

  # Must reference openclaw@<version>, never openclaw@latest, never bare openclaw
  grep -q 'npm install -g openclaw@[0-9]' "$compose"
  if grep -qE "npm install -g openclaw@latest${TAG_BOUNDARY}" "$compose"; then
    return 1
  fi
  if grep -Eq "$OPENCLAW_BARE_INSTALL_PATTERN" "$compose"; then
    return 1
  fi
}
