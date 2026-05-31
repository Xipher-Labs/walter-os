# Supply-chain hardening — planned SLSA Build L3 provenance + reproducible builds (OSS Trust C-1 + C-2) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: OSS Trust roadmap Layer C items C-1 + C-2 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83) (post-merge in-tree path: `docs/specs/oss-trust-roadmap.md`). This spec assumes the parent merges first or in the same release cycle.
**Target release**: v1.0
**Depends on**: existing `release.yml` (SBOM + cosign signing — already in `main`), `docs/security/verification.md` (cosign verification doc).

This is a **combined spec** for two layer-C items: both touch `release.yml`, both need the same set of artifact-naming and toolchain-pinning decisions, and shipping them independently would duplicate the threat-model + verification-doc work. They're sequenced inside the spec: C-1 lands first (cheap, GH Actions does most of the work), C-2 lands second (requires deterministic-build instrumentation). As of 2026-05-31, use SLSA v1.2 Build Track terminology: Walter-OS is targeting **Build L3**, not the retired generic "SLSA level 3" shorthand.

## Problem

Today `release.yml` ships **integrity**: SBOM (CycloneDX), SHA-256 checksums, cosign keyless OIDC signature on the checksums file. That's enough for "did this file change after the release was cut" but doesn't answer two questions a downstream forker has every right to ask:

1. **Where did this artifact come from?** Without a SLSA provenance attestation, all the operator can say is "trust GitHub Actions ran release.yml." There's no machine-verifiable record of `{tag, commit SHA, builder identity, build inputs, materials}` bound to the artifact. Pasted on top of cosign, SLSA Build L3 provenance gives `slsa-verifier` and any downstream the ability to independently validate `this tarball was built from THIS commit by THIS GH Actions workflow run`.
2. **Can I rebuild this exact tarball from source?** Today, no — two runs of `release.yml` for the same tag produce subtly different artifacts (timestamps in tar headers, mtime jitter, dependency lockfile drift). That breaks the "you can re-derive the artifact and compare hashes" trust path that reproducible-builds depends on.

C-1 closes question #1 (provenance). C-2 closes question #2 (reproducibility). Together they let an independent forker say: "I rebuilt walter-os v1.0 from source. My SHA-256 matches the release. The SLSA attestation matches the GH Actions runner that produced the official artifact. Therefore I trust this binary."

## Non-goals

- **SLSA L4** (two-person review, hermetic builds with no network). Out of scope until v2.0+.
- **Reproducible builds for user-runnable build outputs** (control-tower Next.js bundle, walter-host service images). Each has its own reproducibility roadmap; the OSS Trust roadmap (see Parent above — umbrella `DEC-4` cross-cutting decision on reproducibility scope) scopes us to `release.yml` artifacts only. (The umbrella roadmap uses the `DEC-N` prefix for cross-cutting decisions to disambiguate from per-layer `D-N` decisions like Layer D's D-1 GitHub Security Advisories item — referencing "D-4" alone would be ambiguous.)
- **Building our own SLSA generator.** We use the upstream SLSA generic
  generator reusable workflow. No bespoke provenance plumbing.
- **Self-hosted runners.** GitHub-hosted runners qualify as SLSA L3 builders out of the box. Self-hosting would force us to re-prove builder isolation and is a hard regression for solo-operator setups.
- **Reproducibility across operating systems.** This spec implements C-2 by pinning the runner image to `ubuntu-24.04` (replacing the current `ubuntu-latest` in `release.yml` — AC-4 below makes the pin an explicit acceptance criterion). The pinning IS one of this spec's outputs, not an external invariant the spec is relying on. Cross-OS reproducibility (running the recipe on macOS or Windows runners) is a v2.0+ stretch goal.
- **Python reproducibility** in C-2 (the roadmap's open question #4). Scoped here to **bash + the source tarball + SBOM + checksums**. Python deferred to a v1.x sub-issue. Control-tower JS bundles also deferred to their own roadmap.

## Decisions (proposed)

### C-1 — SLSA Build L3 provenance

| # | Decision | Why |
|---|---|---|
| C1-D-1 | **Generator**: `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0`. This is the one explicit exception to the repo's SHA-only workflow pin rule. | The SLSA generic generator is a reusable workflow builder, not a normal action. Upstream requires referencing it by release tag so `slsa-verifier` can validate the trusted builder identity embedded in provenance. The workflow-pin test allowlists only this exact ref and documents the exception. |
| C1-D-2 | **Subject set**: every artifact attached to the GH Release that this workflow produces. That's: source tarball (`.tar.gz` — the `.zip` GitHub auto-attaches to every tag is NOT in the SLSA subject set because the rest of this spec — C2-D-2 deterministic recipe, AC-4 — only defines a reproducible-build recipe for the tarball; the auto-zip is built by GitHub at download time from the same commit and isn't run-to-run reproducible under our control), SBOM (`walter-os-<tag>.sbom.cdx.json`), the checksums file (`checksums.sha256` — name comes from the existing `release.yml`), and the cosign bundle (`checksums.sha256.cosign.bundle`). Note: as of v0.4.1, `release.yml` produces ONLY the bundle — standalone `.sig` + `.pem` files are no longer emitted because cosign v3+ forces bundle-only output ([PR #108](https://github.com/Xipher-Labs/walter-os/pull/108), merged before v0.4.1 — the corresponding doc update in `docs/security/verification.md` is the source of truth). The bundle carries the signature + Fulcio cert internally. | "Sign everything we publish AND can reproduce" — a forker shouldn't have to wonder whether the SBOM has a different provenance than the tarball. Artifact names match what `release.yml` actually emits as of v0.4.1 (verified against the current workflow). |
| C1-D-3 | **Attestation storage**: one release-level `walter-os-<tag>.intoto.jsonl` attached to the GitHub Release. | The SLSA generic generator consumes the base64 subject digest list and uploads a single provenance file covering all release artifacts. |
| C1-D-4 | **Verification path**: documented in `docs/security/verification.md` with `slsa-verifier verify-artifact <file> --provenance-path walter-os-<tag>.intoto.jsonl --source-uri github.com/Xipher-Labs/walter-os --source-tag <tag>` run once per artifact. | The SLSA generic generator emits one release-level provenance file covering all release-artifact subjects. `slsa-verifier` is the ecosystem-compatible verification path for that builder. |
| C1-D-5 | **CI enforcement**: the provenance job depends on the release-artifact and security-artifact jobs. If the generator cannot validate the subject list, produce provenance, or upload it to the release, the workflow fails. | Catch provenance regressions at release time, not when a downstream user complains weeks later. |
| C1-D-6 | **Backfill policy**: releases cut before this workflow change do NOT get retroactive provenance. | Backfilling would require re-running release pipelines against archived tags with potentially-drifted toolchains; the integrity gain doesn't justify the regression risk. Document the cutoff in `docs/security/verification.md`. |

### C-2 — Reproducible builds

| # | Decision | Why |
|---|---|---|
| C2-D-1 | **Scope**: source tarball + SBOM + checksums file. Cosign signature is NON-reproducible by design (timestamp + nonce), and that's fine — provenance covers it. | Matches roadmap D-4. Bigger scope is a v1.x problem. |
| C2-D-2 | **Determinism technique for tarball**: pipe `git archive --format=tar <tag>` into `gzip -n` (drops mtime + filename headers). Do NOT use `git archive --format=tar.gz`, which double-gzips when piped to gzip AND can embed a gzip-header timestamp that varies run-to-run. Don't run `tar c` on a working copy either — file mtimes vary. | Two runs of `git archive --format=tar <tag> \| gzip -n` produce byte-identical output. This is the canonical "reproducible source tarball" recipe; see reproducible-builds.org `archives` page. |
| C2-D-3 | **Determinism technique for SBOM**: anchore/sbom-action already produces deterministic CycloneDX given a deterministic source. Pin `anchore/sbom-action` AND the underlying `syft` version. Sort `components` and `dependencies` arrays by `bom-ref` before write. | CycloneDX without sorted arrays differs run-to-run because syft walks the FS in inode order. Sorting is the documented fix; bash one-liner with jq. |
| C2-D-4 | **Determinism technique for checksums**: sort the `find` output before hashing. Already partially done — the "Generate SHA-256 checksums for full release payload" step in `release.yml` pipes `find` through `sort > checksums.sha256` with a comment that calls out reproducibility intent; verify the sort is locale-stable (`LC_ALL=C sort`, not the runner default which can vary) and tighten the test coverage. | `find` is not deterministic across reruns even on the same FS. `find ... | LC_ALL=C sort` is the standard pattern. Referencing the step by its `name:` instead of a line number so this spec doesn't drift when `release.yml` grows. |
| C2-D-5 | **Verification job**: a new `reproducibility-check` job in `release.yml` re-builds the source tarball + SBOM + checksums in a fresh runner, compares SHA-256s to the published artifacts. Mismatch fails the workflow. | Same philosophy as C1-D-5: don't ship something whose reproducibility we haven't actually verified. |
| C2-D-6 | **Toolchain pinning**: every tool in the reproducible path (`git`, `tar`, `gzip`, `jq`, `syft`, `bash`) MUST be pinned to a specific version inside `release.yml`. Drift in `runs-on: ubuntu-24.04` toolchain updates would break reproducibility silently. Pin via `apt-get install -y <pkg>=<exact-version>` for system tools; pin `syft` via the action SHA. | The hardest reproducibility regression is "GitHub updated their runner image; now tar 1.34.1 → 1.34.2 produces a one-byte-different archive." Pinning catches this. |
| C2-D-7 | **Operator-reproducibility doc**: `docs/security/reproducible-builds.md` walks a forker through `git clone && git checkout <tag> && ./scripts/release/reproduce.sh <tag>` and asserts byte-identical output. | Reproducibility is worthless if the operator doesn't know how to run it. The doc is part of the AC. |

## Acceptance criteria

### AC-1 — SLSA Build L3 attestation in `release.yml` (C-1)
- [ ] `release.yml` gains a SLSA provenance job that calls `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0` with a base64 subject list covering tarball + SBOM + `checksums.sha256` + its bundle.
- [ ] The generator emits one release-level `.intoto.jsonl` covering every subject digest.
- [ ] The release uploads ALSO include the `.intoto.jsonl` files as release assets (operator-friendly: one place to download).

### AC-2 — Provenance generation enforcement (C-1)
- [ ] New provenance job depends on the existing `release` job + the existing `security` job.
- [ ] The job receives the exact base64 subject list emitted by the security job.
- [ ] Generator failure marks the workflow failed.
- [ ] Bats coverage verifies the job dependency, subject wiring, and generator ref.

### AC-3 — Verification docs (C-1)
- [ ] `docs/security/verification.md` gains a "SLSA provenance verification" section with `slsa-verifier` examples.
- [ ] Section states that releases cut before this workflow change have no retroactive provenance.
- [ ] Cross-link from `README.md` "Security" section to the verification doc.

### AC-4 — Reproducible source tarball + SBOM + checksums (C-2)
- [ ] `release.yml` jobs' `runs-on:` field pinned to `ubuntu-24.04` (replaces the current `ubuntu-latest`, which floats and would silently break reproducibility on GH's next runner-image rotation). Both `release` and `security` jobs use the same pin.
- [ ] `release.yml` source-archive step uses `git archive --format=tar <tag> | gzip -n` (NOT `--format=tar.gz`, which double-gzips when piped — see C2-D-2). Replaces any timestamp-bearing tar invocation.
- [ ] SBOM step pipes through `jq 'sort_by_components_and_dependencies'` (canonical bash one-liner spelled out in the spec; the plan refines it).
- [ ] Checksums step pre-sorts the `find` output.

### AC-5 — Toolchain pinning audit (C-2)
- [ ] Every command in the reproducible path has an explicit version. Documented as a table in `docs/security/reproducible-builds.md`.
- [ ] CI fails fast if the toolchain version drifts (a smoke step `tar --version | grep -q "1.34"` style check, one per pinned tool).

### AC-6 — Reproducibility check job (C-2)
- [ ] New job `reproducibility-check` (depends on the existing `security` job — same job AC-2 corrects, formerly drafted as `sbom-and-sign`) re-runs the deterministic steps on a fresh runner.
- [ ] Computes SHA-256 of re-built tarball, SBOM, checksums.
- [ ] Asserts each matches the published artifact's SHA-256 from `checksums.sha256`.
- [ ] Job failure marks the workflow failed AND publishes a failure marker for operator visibility — GitHub Releases don't support a comment thread (unlike Issues/PRs), so the failure marker is one of: (a) `gh release edit <tag> --notes "<existing-notes>\n\n## ⚠️ Reproducibility check FAILED for <artifact>"` appended to the release body, OR (b) `gh release edit <tag> --draft=true` to demote the release back to draft until investigated, OR (c) a new Issue filed via `gh issue create` with the release context (preferred — gives a discussion thread that's actually threaded). Plan picks at implementation time; (c) is the default proposal.
- [ ] bats coverage in `tests/release/reproducibility.bats`.

### AC-7 — Operator-reproducibility runbook (C-2)
- [ ] `docs/security/reproducible-builds.md` (new):
  - Why reproducibility matters (1 paragraph)
  - Per-artifact reproduction recipe (tarball, SBOM, checksums)
  - Pinned toolchain table (from AC-5)
  - "What if my SHA doesn't match" troubleshooting
- [ ] `scripts/release/reproduce.sh <tag>` — one-shot operator script that re-runs the deterministic steps locally and diffs against the published checksums.
- [ ] CHANGELOG entry under `[Unreleased] → Added (security)`.

## Threat model

| Attack | Mitigation | Layer |
|---|---|---|
| **Compromised maintainer publishes a malicious release** | SLSA provenance proves the artifact came from THIS workflow on THIS commit. A maintainer with repo-write but no workflow-edit access can't forge it. | C-1 |
| **GH Actions runner compromise injects backdoor at build time** | Reproducible build: an independent forker rebuilds from source and compares hashes. Mismatch → public detection. | C-2 |
| **Tampered SBOM (false-clean dependency report)** | SBOM is in the attestation subject set; signature covers it. Also, reproducibility check would catch any tampering that produced a different SBOM hash. | C-1 + C-2 |
| **Replay attack: attacker presents old, valid provenance for a new malicious artifact** | `slsa-verifier verify-artifact` checks the subject digest; presenting provenance for file A while serving file B fails verification. | C-1 |
| **Sigstore Rekor tampering** | Rekor is append-only and itself audited; we trust Rekor at the level of Sigstore's threat model. Documented as such. | C-1 |
| **Reproducibility gaps from toolchain drift (GH runner image update)** | Pinned tool versions + CI smoke check. If the runner image bumps a pinned tool, CI fails before release. | C-2 |
| **Operator runs `reproduce.sh` against an off-tag working tree → false mismatch** | Script first does `git status` (refuses to proceed on dirty tree) AND `git rev-parse <tag>^{commit}` vs `git rev-parse HEAD` (refuses to proceed if HEAD ≠ the named tag's commit). The previous draft referenced `git verify-tag <tag>` — that's intentionally NOT required, because Walter-OS release tags are annotated but NOT GPG/SSH-signed today (the integrity floor comes from cosign attestation on the published artifacts, not from tag signatures). Re-introducing `git verify-tag` as a required check would either always fail (unsigned tags) or force an out-of-scope tag-signing migration. If/when we adopt signed tags, the verify step gets added then. | C-2 |

## Out of scope

- **C-2 for control-tower bundles** (Next.js webpack output). Tracked in a follow-up roadmap.
- **C-2 for Python scripts** (`scripts/walter/lib/*.py`). Deferred to v1.x.
- **SLSA L4** (two-person review, hermetic). v2.0+.
- **Distributed reproducibility witness** (multiple independent builders re-running the build and publishing their hashes). Future work; v1.x at earliest.

## Recommended PR ordering

C-1 first (faster, lower risk, unblocks the "we have SLSA Build L3" claim for v1.0 marketing). C-2 second (depends on `release.yml` already cleaned up by C-1).

**C-1 PRs (≤200 LOC each, 3-round review):**
1. AC-1 — SLSA generic generator job + release-asset upload
2. AC-2 — provenance generation enforcement + bats
3. AC-3 — verification docs + cross-links

**C-2 PRs (≤200 LOC each, 3-round review):**
4. AC-4 — deterministic tarball + SBOM + checksums steps
5. AC-5 — toolchain pinning audit
6. AC-6 — reproducibility-check job + bats
7. AC-7 — operator runbook + `reproduce.sh`

## Open questions for the operator

1. **C-2 language scope**: bash + source tarball + SBOM + checksums only (proposal — matches roadmap D-4), or also include JS bundles (`apps/control-tower` Next.js output)? Proposal: bash + source ONLY for v1.0; JS bundle reproducibility in its own roadmap.
2. **Provenance file naming**: release-level `walter-os-<tag>.intoto.jsonl`
   (proposal — matches the SLSA generic generator output) or per-artifact
   provenance names? Proposal: one release-level `.intoto.jsonl`.
3. **`reproducibility-check` failure handling**: hard-fail the workflow + delete the release (proposal — strict, matches AC-6) or soft-fail with a warning + open a tracking issue? Proposal: hard-fail. Reproducibility is binary; "mostly reproducible" is worthless.
4. **Workflow-change cutoff vs partial backfill**: leave releases cut before
   this workflow change without provenance (proposal — too risky to backfill),
   or backfill recent releases with provenance built from `git archive` + a
   fresh attestation? Proposal: no backfill. Document the cutoff.

## Refs

- Parent: OSS Trust roadmap Layer C C-1 + C-2 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); post-merge in-tree: `docs/specs/oss-trust-roadmap.md`.
- Existing: `.github/workflows/release.yml` (SBOM + cosign already wired)
- Existing: `docs/security/verification.md` (cosign verification — C-1 extends)
- SLSA spec: <https://slsa.dev/spec/v1.2/>
- SLSA Build Track basics: <https://slsa.dev/spec/v1.2/build-track-basics>
- SLSA Build L3 requirements: <https://slsa.dev/spec/v1.2/build-requirements>
- SLSA GitHub generator: <https://github.com/slsa-framework/slsa-github-generator>
- `slsa-verifier`: <https://github.com/slsa-framework/slsa-verifier>
- Reproducible Builds project: <https://reproducible-builds.org/>
- `git archive` reproducibility: <https://reproducible-builds.org/docs/archives/>
