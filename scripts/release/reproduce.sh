#!/usr/bin/env bash
# Reproduce Walter-OS release artifacts for a checked-out tag.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/release/reproduce.sh <tag> [asset-dir]

Rebuilds the deterministic source archive and, when syft is installed, the
CycloneDX SBOM for <tag>, then compares their SHA-256 digests against the
release's checksums.sha256.

The working tree must be clean and HEAD must equal <tag>.
USAGE
}

die() {
  echo "reproduce: ERROR: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

tag="${1:-}"
asset_dir="${2:-}"
[[ -n "$tag" && "$tag" != "-h" && "$tag" != "--help" ]] || {
  usage
  exit 0
}

need git
need gzip
need sha256sum
need gh

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git diff --quiet -- . || die "working tree has unstaged changes"
git diff --cached --quiet -- . || die "working tree has staged changes"

tag_commit="$(git rev-parse "${tag}^{commit}")" || die "tag not found: $tag"
head_commit="$(git rev-parse HEAD)"
[[ "$head_commit" == "$tag_commit" ]] || die "HEAD must equal ${tag} (${tag_commit})"

if [[ -z "$asset_dir" ]]; then
  asset_dir="$(mktemp -d "${TMPDIR:-/tmp}/walter-os-release-assets.XXXXXX")"
  cleanup_asset_dir=1
else
  cleanup_asset_dir=0
  mkdir -p "$asset_dir"
fi
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/walter-os-reproduce.XXXXXX")"
trap 'rm -rf "$work_dir"; if [[ "${cleanup_asset_dir:-0}" == "1" ]]; then rm -rf "$asset_dir"; fi' EXIT

echo "Downloading release assets for ${tag}..."
gh release download "$tag" \
  --pattern "checksums.sha256" \
  --pattern "walter-os-${tag}.source.tar.gz" \
  --pattern "walter-os-${tag}.sbom.cdx.json" \
  --dir "$asset_dir"

checksums="${asset_dir}/checksums.sha256"
[[ -s "$checksums" ]] || die "missing checksums.sha256"

rebuilt_tar="${work_dir}/walter-os-${tag}.source.tar.gz"
git archive --format=tar --prefix="walter-os-${tag}/" "$tag" \
  | gzip -n -9 > "$rebuilt_tar"

expected_tar_hash="$(awk -v file="./walter-os-${tag}.source.tar.gz" '$2 == file { print $1 }' "$checksums")"
[[ -n "$expected_tar_hash" ]] || die "checksums.sha256 has no source tarball entry"
actual_tar_hash="$(sha256sum "$rebuilt_tar" | awk '{ print $1 }')"
[[ "$actual_tar_hash" == "$expected_tar_hash" ]] \
  || die "source tarball mismatch: expected ${expected_tar_hash}, got ${actual_tar_hash}"

echo "source tarball: OK"

if command -v syft >/dev/null 2>&1; then
  need jq
  rebuilt_sbom="${work_dir}/walter-os-${tag}.sbom.cdx.json"
  syft dir:. -o cyclonedx-json="${rebuilt_sbom}.raw" >/dev/null
  jq '
    if (.components | type) == "array" then
      .components |= sort_by(.["bom-ref"] // .name // "")
    else . end
    | if (.dependencies | type) == "array" then
      .dependencies |= sort_by(.ref // "")
    else . end
  ' "${rebuilt_sbom}.raw" > "$rebuilt_sbom"
  expected_sbom_hash="$(awk -v file="./walter-os-${tag}.sbom.cdx.json" '$2 == file { print $1 }' "$checksums")"
  [[ -n "$expected_sbom_hash" ]] || die "checksums.sha256 has no SBOM entry"
  actual_sbom_hash="$(sha256sum "$rebuilt_sbom" | awk '{ print $1 }')"
  [[ "$actual_sbom_hash" == "$expected_sbom_hash" ]] \
    || die "SBOM mismatch: expected ${expected_sbom_hash}, got ${actual_sbom_hash}"
  echo "SBOM: OK"
else
  echo "SBOM: skipped (install syft + jq for SBOM reproduction)"
fi

echo "Reproducibility check passed for ${tag}."
