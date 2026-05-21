#!/usr/bin/env bats
# tests/oss/external-review-minors.bats
#
# Issue #123 — three MINORs from the 2026-05-21 external review:
#   F5: pin semgrep container by digest
#   F8: doctor secrets.env check reclassified (3-state: ok/warn/fail)
#   F10: observability stack host privileges documented

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# -----------------------------------------------------------------------
# F5: semgrep workflow pinned by digest
# -----------------------------------------------------------------------
@test "F5: semgrep workflow uses @sha256: digest pin, not tag" {
  local f="$REPO_ROOT/.github/workflows/semgrep.yml"
  [[ -f "$f" ]] || { echo "semgrep.yml missing"; return 1; }
  # The container image line must reference @sha256:<64 hex chars>.
  grep -qE 'image: semgrep/semgrep@sha256:[0-9a-f]{64}' "$f"
}

@test "F5: semgrep image NOT tag-pinned at top level (only via comment annotation)" {
  local f="$REPO_ROOT/.github/workflows/semgrep.yml"
  # Active `image:` line must not be tag-pinned; the `tag: ...` comment
  # annotation (for Renovate) is allowed.
  ! grep -qE '^\s*image:\s+semgrep/semgrep:[0-9]+\.[0-9]+\.[0-9]+\s*$' "$f"
}

# -----------------------------------------------------------------------
# F8: doctor secrets.env is now a 3-state probe
# -----------------------------------------------------------------------
@test "F8: bin/walter-os defines a 3-state check helper" {
  local f="$REPO_ROOT/bin/walter-os"
  [[ -f "$f" ]] || { echo "bin/walter-os missing"; return 1; }
  grep -qE '^[[:space:]]+check_three_state\(\)' "$f"
}

@test "F8: bin/walter-os defines _secrets_runtime_probe" {
  local f="$REPO_ROOT/bin/walter-os"
  grep -qE '^[[:space:]]+_secrets_runtime_probe\(\)' "$f"
}

@test "F8: _secrets_runtime_probe returns ok|warn|fail" {
  local f="$REPO_ROOT/bin/walter-os"
  # All three return values must be reachable in the probe body.
  grep -qE 'echo "ok"'   "$f"
  grep -qE 'echo "warn"' "$f"
  grep -qE 'echo "fail"' "$f"
}

@test "F8: doctor no longer hard-FAILs on missing secrets.env" {
  local f="$REPO_ROOT/bin/walter-os"
  # The old line `tier_check 1 "secrets template present" test -f \"\${WALTER_CONFIG}/secrets.env\"`
  # must be gone — it was the source of the false ✗ on clean Infisical-runtime installs.
  ! grep -qE 'secrets template present.*test -f.*secrets\.env' "$f"
}

# -----------------------------------------------------------------------
# F10: observability docs exist with the required table
# -----------------------------------------------------------------------
@test "F10: docs/operational/observability.md exists" {
  [[ -f "$REPO_ROOT/docs/operational/observability.md" ]]
}

@test "F10: observability doc has a 'Host privileges' table" {
  local f="$REPO_ROOT/docs/operational/observability.md"
  grep -qE '^## Host privileges granted to the observability profile' "$f"
  # The table must include every observability service per the compose file.
  for svc in prometheus loki promtail node-exporter cadvisor grafana; do
    grep -qiE "^\| \*\*${svc}\*\*" "$f" || { echo "service $svc missing from privileges table"; return 1; }
  done
}

@test "F10: observability doc names privileged: true for cadvisor explicitly" {
  local f="$REPO_ROOT/docs/operational/observability.md"
  grep -qiE 'privileged.*true.*cadvisor|cadvisor.*privileged.*true' "$f"
}
