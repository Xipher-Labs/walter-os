# Reproducible release builds

Walter-OS release reproducibility lets an operator rebuild the published source
archive from the tagged source and compare its digest against the signed release
checksums. This complements cosign and SLSA provenance: signatures prove who
published the checksums, provenance proves which workflow produced the artifacts,
and reproducibility lets a third party detect build-time drift.

## Scope

The reproducible release path covers:

- `walter-os-<tag>.source.tar.gz`
- `walter-os-<tag>.sbom.cdx.json` when `syft` and `jq` are installed locally
- `checksums.sha256` as the signed digest source of truth

`checksums.sha256.cosign.bundle` is not reproducible by design because cosign
keyless signing includes timestamped, transparency-log-backed material.

## Toolchain

| Tool | Release workflow source | Local reproduction requirement |
|---|---|---|
| Git | `ubuntu-24.04` runner, checked by release tests | `git` on PATH |
| gzip | `ubuntu-24.04` runner, deterministic `gzip -n -9` | `gzip` on PATH |
| sha256sum | GNU coreutils on `ubuntu-24.04` | `sha256sum` on PATH |
| gh | GitHub-hosted runner image | `gh` authenticated for release downloads |
| syft | `anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610` | Optional `syft` for SBOM reproduction |
| jq | `ubuntu-24.04` runner | Optional `jq` for SBOM canonicalization |

The release workflow pins the runner to `ubuntu-24.04`, pins third-party actions
by commit SHA except for the SLSA generator's required release tag, and uses
deterministic archive and checksum commands.

## Reproduce A Release

From a clean clone:

```bash
git fetch --tags origin
git checkout <tag>
scripts/release/reproduce.sh <tag>
```

The script refuses to run unless `HEAD` equals the named tag and the working tree
is clean. It downloads the release checksums and artifacts with `gh`, rebuilds
the deterministic source archive with:

```bash
git archive --format=tar --prefix="walter-os-<tag>/" <tag> | gzip -n -9
```

Then it compares the rebuilt SHA-256 digest with `checksums.sha256`.

If `syft` and `jq` are available, the script also exports the tag into a
temporary tree with `git archive`, rebuilds and canonicalizes the CycloneDX SBOM
from that exported tree, then compares that digest with the release checksums.
Using the archive export keeps local submodule checkouts and untracked files out
of SBOM reproduction, matching the release workflow's tag checkout.

## Troubleshooting

If the source archive digest does not match:

- Confirm the checkout is exactly the release tag: `git rev-parse HEAD` and
  `git rev-parse <tag>^{commit}` must match.
- Confirm the release assets are from the same tag you checked out.
- Confirm `gzip` supports `-n`; without it, gzip embeds timestamp/name metadata.

If the SBOM digest does not match:

- Confirm `syft` is installed and close to the version used by
  `anchore/sbom-action` in the release workflow.
- Re-run from a clean checkout with no local modifications. Untracked files and
  initialized submodules are intentionally excluded from SBOM reproduction.
- Treat persistent mismatches as security-relevant and open an issue with the
  tag, local tool versions, and the mismatching digest.
