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

## Future Hardening

The router Dockerfile exception is intentionally narrow. A stronger future flow
would generate a wrapper-package lockfile or vendored tarball plus integrity
metadata for each globally installed CLI, then install from that artifact during
image build. That work should be done as a dedicated supply-chain hardening PR
because it changes image build mechanics and upgrade cadence.
