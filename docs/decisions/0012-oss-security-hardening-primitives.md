# 0012. OSS Security Hardening Primitives — v0.1

**Date**: 2026-05-12
**Status**: Proposed

## Context

Walter-OS v0.2.0 is being released as OSS under AGPLv3. The release scaffolding
(CHANGELOG, LICENSE, NOTICE, release workflow, SECURITY.md, CONTRIBUTING.md) is
handled by PRs #47–#49. Those PRs leave four gaps:

1. No artifact integrity chain (no SBOM, no signatures, no checksums).
2. No dependency or semantic vulnerability scanning in CI.
3. No secret scanning in CI or as a local hook.
4. The existing hook chain does not block `curl | bash` and similar
   remote-code-execution patterns, which are the primary injection vector in
   agentic CI environments.

The project needs to close these gaps before the v0.2.0 tag.

## Decision

We adopt a layered OSS security hardening approach consisting of seven distinct
primitives, each independently verifiable:

1. **gitleaks** for secret scanning (pre-commit hook integration + CI workflow).
2. **OpenSSF Scorecard** GitHub Action (weekly + on push to main) with README badge.
3. **syft CycloneDX SBOM** generated on every GitHub Release via `anchore/sbom-action`.
4. **cosign keyless OIDC signing** of the checksums file; bundle attached as a
   release asset. No long-lived private key. Verification command documented in
   README and SECURITY.md.
5. **SHA-256 checksums file** generated from all release assets, uploaded as a
   release asset, signed by cosign.
6. **OSV-scanner** GitHub Action (push + PR) for dependency CVE scanning.
7. **CodeQL** GitHub Action (push to main + PR) for semantic analysis of the
   JavaScript/TypeScript Control Tower code.
8. **`hooks/bash-denylist.sh`** — new PreToolUse hook that blocks pipe-to-shell
   and eval-of-variable patterns not covered by the existing `approval-gate.sh`.
9. **`Makefile` with `audit` target** — local reproducibility of CI scanning.
10. **`docs/audits/<version>/`** — committed snapshots of pre-release audit output.

Two items (semgrep custom rules, OpenSSF Silver checklist) are scaffolded but
deferred to v0.2.x.

All tool versions are pinned: GitHub Actions steps use 40-char commit SHAs;
tool binaries use semver tags.

## Consequences

**Easier**:
- Downstream consumers can verify every release artifact cryptographically
  without trusting the distribution channel.
- CI blocks secret commits before they reach the repo history.
- A Scorecard badge gives potential adopters a standard-format trust signal
  without reading the entire codebase.
- The bash-denylist hook closes the specific injection vector pattern (`curl |
  bash`) that existing hooks do not cover, reducing the blast radius of a
  compromised agent session.
- `make audit` lets contributors reproduce CI security checks locally without
  knowing the specific tool invocations.

**Harder**:
- The release job becomes longer (SBOM + checksum + cosign steps add ~2–3
  minutes). This is acceptable for a release workflow that runs infrequently.
- PRs that introduce new lockfiles must update the OSV-scanner workflow to
  include the new lockfile path. This is a low-friction maintenance burden.
- The bash-denylist hook adds one more hook to the PreToolUse chain. Agents
  that legitimately use patterns matching the denylist must use the explicit
  `--allow-denylist-pattern` bypass flag.

**Risks accepted**:
- Cosign keyless signing ties the release signature to the GitHub Actions OIDC
  issuer. If GitHub's OIDC service changes, existing verification commands for
  old releases may need updating. This is an accepted tradeoff for eliminating
  a long-lived signing key.
- The OSV-scanner CVSS threshold behavior depends on the version of the action
  pinned; if the flag is not available, the workflow fails on any finding
  (conservative). This is acceptable.

## Alternatives considered

- **Trivy instead of OSV-scanner**: Trivy is better known for image scanning;
  OSV-scanner is Google's official action and directly queries the OSV database,
  which is broader for ecosystem packages. OSV-scanner rejected for image
  scanning; Trivy rejected for dependency scanning (OSS package coverage is
  narrower than OSV). OSV-scanner wins.
- **GPG signing instead of cosign keyless**: GPG requires managing a long-lived
  private key, storing it as a GitHub secret, and distributing the public key.
  Cosign keyless ties the signing identity to the GitHub Actions OIDC token,
  which is ephemeral and auditable via Rekor. Keyless is strictly easier to
  operate and harder to lose.
- **Extend `approval-gate.sh` instead of a new denylist hook**: The
  `approval-gate.sh` BLOCK_BASH_PATTERNS array already covers destructive ops
  (rm, dd, force push, DROP TABLE). Adding injection patterns there would make
  the file larger and blur the conceptual boundary between "destructive
  operations" and "RCE injection patterns". A separate hook is cleaner, easier
  to test in isolation, and follows the single-responsibility principle of the
  existing hook chain.
- **Dependabot instead of OSV-scanner**: Dependabot creates PRs automatically.
  Walter-OS already has `.github/renovate.json` for dependency management.
  Adding Dependabot would create duplicate PR noise. OSV-scanner provides
  detection-only scanning that integrates with the Security tab, which is the
  right role division.
