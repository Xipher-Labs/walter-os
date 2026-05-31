#!/usr/bin/env bats
# Regression tests for PR #55 Codex review (R2) HIGH-1 + HIGH-2.
#
# HIGH-1: checksum generation must NOT silently sign a placeholder file
#         when the SBOM download races/fails. Drop `|| true`, pre-create
#         the asset directory, and fail if the expected SBOM is absent.
# HIGH-2: only downloading `*.json` assets means archives/binaries from
#         the main release workflow are NOT covered by the signed
#         checksums. The signature must prove the FULL release payload.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
}

@test "release workflow exists" {
  [ -f "$WORKFLOW" ]
}

@test "release workflow has no \`|| true\` after asset operations" {
  # `|| true` after gh release download / sha256sum / cosign / sbom would
  # swallow the failure and let a placeholder be signed. Regression for HIGH-1.
  # Strip comment lines (lines starting with optional whitespace + #) before
  # checking, so the failure-semantics docstring doesn't trigger.
  local offending
  offending=$(grep -nE '\|\|\s*true' "$WORKFLOW" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  if [ -n "$offending" ]; then
    echo "Found '|| true' in release.yml (HIGH-1 regression):"
    echo "$offending"
    return 1
  fi
}

@test "release workflow downloads ALL assets (no \`--pattern\` filter)" {
  # `gh release download` must NOT be invoked with `--pattern` so archives
  # and binaries are pulled, not just JSON. Regression for HIGH-2.
  # We strip line continuations (\\\n) so multi-line gh invocations are
  # checked as single logical commands.
  local joined
  joined=$(awk 'BEGIN{RS=""} {gsub(/\\\n[[:space:]]*/, " "); print}' "$WORKFLOW")
  if echo "$joined" | grep -E 'gh release download[^|;&]*--pattern' >/dev/null 2>&1; then
    echo "gh release download is filtering with --pattern (HIGH-2 regression)"
    echo "$joined" | grep -E 'gh release download[^|;&]*--pattern'
    return 1
  fi
  # Positive assertion: there IS a gh release download invocation.
  grep -E 'gh release download' "$WORKFLOW" >/dev/null
}

@test "release workflow checks SBOM exists with \`test -s\` before signing" {
  # After SBOM generation, the workflow must assert the SBOM file is
  # present and non-empty BEFORE signing — otherwise a missing SBOM would
  # produce an empty/placeholder checksum that still gets signed. HIGH-1.
  # Match either a literal path containing 'sbom' or a variable named
  # like SBOM_FILE/SBOM_PATH.
  grep -iE 'test -s .*(sbom|\$\{?SBOM)' "$WORKFLOW" >/dev/null
}

@test "checksums step includes archives + binaries, not just *.json (regression against PR #55 HIGH-2)" {
  # The checksum command must NOT be `sha256sum ./*.json` or similar
  # JSON-only glob. A `find` over the asset dir (or `sha256sum ./*`
  # equivalent that catches all file types) is required.
  if grep -E 'sha256sum.*\*\.json' "$WORKFLOW" >/dev/null 2>&1; then
    echo "Checksum step is filtering to *.json only (HIGH-2 regression):"
    grep -nE 'sha256sum.*\*\.json' "$WORKFLOW"
    return 1
  fi
  # Positive assertion: there is a find-based or wildcard checksum step.
  # Strip line continuations so multi-line `find ... -exec sha256sum`
  # invocations are checked as one logical command.
  local joined
  joined=$(awk 'BEGIN{RS=""} {gsub(/\\\n[[:space:]]*/, " "); print}' "$WORKFLOW")
  echo "$joined" | grep -E '(find[[:space:]].*sha256sum|sha256sum[[:space:]].*\*)' >/dev/null
}

@test "every step that produces a signed artifact has a non-empty assertion before signing" {
  # `test -s checksums.sha256` (or equivalent for the checksums file the
  # workflow actually uses) must appear before the cosign sign-blob step
  # so we never sign an empty file. HIGH-1.
  # Match the literal name `checksums` or `CHECKSUMS_FILE` env-var ref.
  grep -iE 'test -s .*(checksums|\$\{?CHECKSUMS)' "$WORKFLOW" >/dev/null
}

@test "release workflow pre-creates the asset directory deterministically" {
  # mkdir -p for the asset directory must exist before any download /
  # sbom action that depends on it. HIGH-1. Accept either the literal
  # path `/tmp/release-assets` or an env-var reference like
  # `${ASSET_DIR}` / `"$ASSET_DIR"`.
  grep -E 'mkdir -p (.*/tmp/release-assets|.*ASSET_DIR)' "$WORKFLOW" >/dev/null
}

@test "release workflow sorts checksums with stable locale" {
  # Checksum manifests must not vary with runner locale.
  grep -E 'LC_ALL=C[[:space:]]+sort[[:space:]]*>[[:space:]]*"\$\{CHECKSUMS_FILE\}"' "$WORKFLOW" >/dev/null
}
