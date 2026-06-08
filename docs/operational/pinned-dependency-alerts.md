# Pinned Dependency Alert Decisions

This page records OpenSSF Scorecard `PinnedDependenciesID` findings that need a
code change, a repository setting, or a documented dismissal.

## Intentional Dismissals

| Alert | Location | Decision |
|---|---|---|
| `#41`-`#43` | `tests/semgrep/fixtures/positive/curl-pipe-shell.sh` | Dismiss as `used in tests`. The file is a positive fixture that must contain unsafe `curl`/`wget` pipe-to-shell examples so the Semgrep deny rule can prove it fires. |
| `#52` | `.github/workflows/release.yml` | Dismiss as `false positive`. The SLSA generic generator is intentionally pinned to the exact upstream release tag `v2.1.0`; `tests/install/workflow-pins.bats` allow-lists only that exact tag because `slsa-verifier` expects the trusted builder identity from the release-tagged reusable workflow. |
| `#57`-`#59` | `setup/walter-host/services/*-router/Dockerfile` | Dismiss as `false positive` for this release. The router images install globally executed AI CLIs from npm, but each command is pinned to an explicit package version and guarded by `tests/oss/no-latest-tags-walter-host.bats`. A stronger shrinkwrap/tarball workflow is future hardening, not a reason to keep mutable `@latest` installs. |

## Code Changes

| Alert | Location | Fix |
|---|---|---|
| `#54` | `.github/workflows/readme-lint.yml` | Replaced floating `npm install -g markdownlint-cli` with `npx --yes markdownlint-cli@0.48.0`. `tests/install/workflow-pins.bats` now verifies the workflow keeps a versioned markdownlint invocation. |

## Node 24 Release Warnings

The v0.6.1 release workflow emitted GitHub Actions Node.js 20 deprecation
warnings from two places:

- Walter-OS-owned release jobs. These use direct `actions/checkout` calls and
  should stay pinned to a commit whose action metadata declares
  `runs.using: node24`.
- The upstream SLSA reusable workflow
  `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0`.
  Walter-OS intentionally uses the upstream semver tag for verifier identity
  compatibility. As of the v0.6.1 audit, `v2.1.0` is the latest upstream
  release, and its internal helper actions still emit Node.js 20 warnings.

Do not fork the SLSA generator just to silence this warning. Re-check upstream
SLSA releases during the next release hardening pass and bump only when the
verifier-compatible reusable workflow publishes a Node 24-ready release.

## Future Hardening

The router Dockerfile exception is intentionally narrow. A stronger future flow
would generate a wrapper-package lockfile or vendored tarball plus integrity
metadata for each globally installed CLI, then install from that artifact during
image build. That work should be done as a dedicated supply-chain hardening PR
because it changes image build mechanics and upgrade cadence.
