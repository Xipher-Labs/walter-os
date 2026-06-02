#!/usr/bin/env bats
# Coverage for the operator-facing reproducible release build path.
# shellcheck disable=SC2016

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/release/reproduce.sh"
  DOC="$REPO_ROOT/docs/security/reproducible-builds.md"
  VERIFY_DOC="$REPO_ROOT/docs/security/verification.md"
  WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
  MAKEFILE="$REPO_ROOT/Makefile"
  CI="$REPO_ROOT/.github/workflows/ci.yml"
}

@test "reproducible release script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "reproducible release script enforces tag checkout and clean tree" {
  grep -Fq 'git diff --quiet -- .' "$SCRIPT"
  grep -Fq 'git diff --cached --quiet -- .' "$SCRIPT"
  grep -Fq 'git rev-parse "${tag}^{commit}"' "$SCRIPT"
  grep -Fq '[[ "$head_commit" == "$tag_commit" ]]' "$SCRIPT"
}

@test "reproducible release script rebuilds deterministic source archive" {
  grep -Fq 'git archive --format=tar --prefix="walter-os-${tag}/" "$tag"' "$SCRIPT"
  grep -Fq 'gzip -n -9' "$SCRIPT"
  grep -Fq 'source tarball mismatch' "$SCRIPT"
}

@test "reproducible release script verifies downloaded source archive checksum" {
  grep -Fq 'published_tar="${asset_dir}/walter-os-${tag}.source.tar.gz"' "$SCRIPT"
  grep -Fq 'published_tar_hash="$(sha256sum "$published_tar" | awk' "$SCRIPT"
  grep -Fq 'published source tarball mismatch' "$SCRIPT"
}

@test "reproducible release script can compare canonical SBOM when tools exist" {
  grep -Fq 'command -v syft' "$SCRIPT"
  grep -Fq 'gh release download "$tag"' "$SCRIPT"
  grep -Fq 'git archive --format=tar --prefix="walter-os-${tag}/" "$tag"' "$SCRIPT"
  grep -Fq 'tar -x -C "$sbom_root"' "$SCRIPT"
  grep -Fq 'syft dir:"${sbom_root}/walter-os-${tag}"' "$SCRIPT"
  grep -Fq -e '--pattern "walter-os-${tag}.sbom.cdx.json"' "$SCRIPT"
  grep -Fq 'sort_by(.["bom-ref"] // .name // "")' "$SCRIPT"
  grep -Fq 'sort_by(.ref // "")' "$SCRIPT"
  grep -Fq 'SBOM mismatch' "$SCRIPT"
}

@test "reproducible release script downloads SBOM only when syft is available" {
  syft_line="$(grep -n 'if command -v syft' "$SCRIPT" | cut -d: -f1)"
  sbom_download_line="$(grep -n -- '--pattern "walter-os-${tag}.sbom.cdx.json"' "$SCRIPT" | cut -d: -f1)"

  [ -n "$syft_line" ]
  [ -n "$sbom_download_line" ]
  [ "$sbom_download_line" -gt "$syft_line" ]
}

@test "reproducible builds runbook documents scope and troubleshooting" {
  [ -f "$DOC" ]
  grep -Fq 'walter-os-<tag>.source.tar.gz' "$DOC"
  grep -Fq 'walter-os-<tag>.sbom.cdx.json' "$DOC"
  grep -Fq 'checksums.sha256.cosign.bundle' "$DOC"
  grep -Fq 'cosign verify-blob' "$DOC"
  grep -Fq 'treating the checksums as authoritative' "$DOC"
  grep -Fq 'What if my SHA' "$DOC" || grep -Fq 'Troubleshooting' "$DOC"
}

@test "verification doc links to reproducible builds runbook" {
  grep -Fq 'reproducible-builds.md' "$VERIFY_DOC"
}

@test "verification doc warns older releases lack source and provenance assets" {
  grep -Fq 'If you are verifying an older release' "$VERIFY_DOC"
  grep -Fq 'source archive and' "$VERIFY_DOC"
  grep -Fq 'SLSA provenance were not backfilled' "$VERIFY_DOC"
}

@test "release workflow keeps deterministic source and SLSA provenance" {
  grep -Fq 'git archive --format=tar --prefix="walter-os-${TAG}/" "${TAG}"' "$WORKFLOW"
  grep -Fq 'gzip -n -9' "$WORKFLOW"
  grep -Fq 'slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0' "$WORKFLOW"
}

@test "local and CI shellcheck include reproduce script" {
  grep -Fq 'scripts/release/reproduce.sh' "$MAKEFILE"
  grep -Fq 'scripts/release/reproduce.sh' "$CI"
}

@test "CI runs reproducible build regression tests" {
  grep -Fq 'tests/install/workflow-pins.bats' "$CI"
  grep -Fq 'tests/install/reproducible-builds.bats' "$CI"
}
