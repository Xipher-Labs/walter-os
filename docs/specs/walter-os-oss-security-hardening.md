# Walter-OS OSS Security Hardening v0.1

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-12
**Linear/Plane**: (no ticket yet — assign before implementation starts)

---

## Problem

Walter-OS is preparing for a public OSS release as v0.2.0. The release
scaffolding (CHANGELOG, LICENSE, NOTICE, release workflow, SECURITY.md,
CONTRIBUTING.md) is being handled by PRs #47, #48, and #49. However, those PRs
leave several security-hardening primitives completely absent:

- The release workflow in PR #47 produces no SBOM, no cosign signatures, and no
  checksums. A downstream consumer who wants to verify that the artifact they
  downloaded matches what was built in CI has no mechanism to do so.
- There is no supply-chain scanner in CI (no SBOM differencing, no OSV or
  CodeQL scanning). An OSS project with no dependency vulnerability CI is a
  liability signal to potential contributors and organizations that evaluate
  projects for adoption.
- The existing hook chain (`approval-gate.sh`, `branch-flow-guard.sh`,
  `pre-commit-tests.sh`, `daily-audit-gate.sh`) enforces process guardrails on
  agent-spawned Bash commands, but does not deny the most dangerous shell
  injection patterns that agent-authored commands can produce: `curl | bash`,
  `wget | sh`, `eval "$UNTRUSTED"`. These patterns have caused real incidents in
  agentic CI environments and are explicitly called out in the AGENTS.md "Supply
  chain" section as a concern.
- There is no ongoing OpenSSF signal (Scorecard, best-practices badge) that
  would give potential adopters or contributors a standard-format trust
  assessment.

Walter-OS will be used as a base for other operators' personal AI OS
deployments. Its hook chain will run with elevated trust in Claude Code sessions.
Shipping a v0.2.0 without these primitives sets a bad precedent and makes the
project harder to audit.

---

## Proposed Solution

Add a layered set of security-hardening primitives that integrate cleanly with
the existing release workflow (PR #47) and hook chain, without duplicating any
files those PRs introduce.

**Artifact integrity layer**: Extend the release workflow with syft-generated
CycloneDX SBOMs, cosign keyless OIDC signatures, and SHA-256 checksums — all
attached as release assets. This gives downstream consumers a complete,
verifiable chain of custody from source to binary.

**CI scanning layer**: Add three purpose-specific GitHub Actions workflows —
OSV-scanner (Google's official action, dependency CVE scanning), CodeQL
(semantic analysis for shell/JS/TypeScript patterns), and OpenSSF Scorecard
(weekly aggregate trust score). Add gitleaks as both a pre-commit hook
integration and a CI workflow to block secrets from reaching the repo. Each
workflow runs on its own schedule appropriate to its cost/latency tradeoff.

**Local audit target**: Add a `Makefile` with an `audit` target that runs all
scanning tools locally in the same sequence CI does. A `docs/audits/` directory
stores self-audit snapshots committed before each release tag, giving reviewers
a human-readable record of the project's security posture at every version.

**Hook-level denylist**: Add a `hooks/bash-denylist.sh` script that extends the
existing hook chain with a targeted pattern list for the shell injection
categories that the current hooks do not cover. The new hook is registered in
the same `PreToolUse` slot as the existing guards.

**Stretch (deferred)**: Custom semgrep rules for Walter-OS-specific injection
patterns, and an OpenSSF Silver Badge checklist file that maps each Silver
requirement to where it is satisfied in the repo.

---

## Acceptance Criteria

- [AC-1] `gitleaks` runs on every `git commit` attempt (via hook integration)
  and on every push/PR via CI, blocking if any secret pattern is detected.
  Verified by a bats test that feeds a fixture file containing a fake secret and
  asserts the hook blocks the commit.

- [AC-2] An OpenSSF Scorecard workflow runs on a weekly schedule and on every
  push to `main`. A badge URL referencing the Scorecard API is added to
  `README.md`. Verified by confirming the workflow file exists at
  `.github/workflows/scorecard.yml` and the README contains the badge markdown.

- [AC-3] Every GitHub Release produced by the existing release workflow
  (PR #47's `release.yml`) includes three additional assets: a CycloneDX SBOM
  (`walter-os-<version>-sbom.json`), a SHA-256 checksums file
  (`walter-os-<version>-checksums.txt`), and a cosign transparency log bundle
  (`walter-os-<version>-cosign.bundle`). Verified by inspecting the workflow
  file's job steps for syft, checksum generation, and `cosign sign-blob` calls.

- [AC-4] The cosign verification command is documented in both `README.md` and
  `SECURITY.md` (the latter is being added by PR #49; the implementer must add
  the verification section after that PR lands, or design the addition as a
  clean append). Verified by grepping for `cosign verify-blob` in both files.

- [AC-5] An OSV-scanner workflow runs on push to `main` and on PRs targeting
  `main`, `dev`, or `staging`. The workflow fails the CI check if any
  vulnerability with CVSS >= 7.0 is found. Verified by confirming the workflow
  file exists at `.github/workflows/osv-scanner.yml`.

- [AC-6] A CodeQL workflow runs on push to `main` and on PRs, scanning at
  minimum the `javascript-typescript` query suite (for the Control Tower Next.js
  app) and the `bash` queries (for shell scripts). Verified by confirming the
  workflow file exists at `.github/workflows/codeql.yml` and the language matrix
  includes both suites.

- [AC-7] `hooks/bash-denylist.sh` blocks commands matching any of the following
  patterns: `curl | bash`, `curl | sh`, `wget | bash`, `wget | sh`,
  `python -c '$VAR'` (untrusted variable interpolation into `-c`),
  `eval "$UNTRUSTED_VAR"` (eval of a variable), `bash <(curl ...)` (process
  substitution with remote fetch), and `rm -rf /` (root deletion, distinct from
  the path-scoped rm patterns in `approval-gate.sh`). The hook is registered in
  `~/.claude/settings.json` (install.sh integration) and tested via bats with at
  least one passing and one blocking fixture per pattern family. Verified by the
  bats test suite at `tests/hooks/bash-denylist.bats`.

- [AC-8] A `Makefile` exists at the repo root with at minimum an `audit` target.
  Running `make audit` locally executes: gitleaks, osv-scanner (if installed),
  syft (if installed), and shellcheck on the hooks directory. Targets
  `make audit-ci` documents that CI-only tools (cosign signing, scorecard) are
  skipped locally. Verified by a bats test `tests/install/makefile-audit.bats`
  that calls `make --dry-run audit` and asserts the expected tool invocations
  appear in the dry-run output.

- [AC-9] A `docs/audits/` directory structure exists with at minimum a
  `docs/audits/README.md` explaining the convention: each release pre-tags a
  subdirectory `docs/audits/<version>/self/` with the raw output of `make audit`.
  Verified by confirming the README exists and the directory structure is present.

- [AC-10] All pinned tool versions in the new workflow files use action-hash
  form for GitHub Actions steps (e.g., `actions/checkout@<sha>`) and
  version-tagged forms for tool binaries (e.g., `anchore/syft@v1.x.y`).
  Verified by `grep -E 'uses:.*@[0-9a-f]{40}'` matching every `uses:` line in
  the new workflow files.

- [AC-11] (Stretch — deferred) A `.semgrep/rules/` directory contains at least
  two custom rules: one detecting unquoted variable interpolation in `python -c`
  invocations and one detecting bare `eval` with a variable argument in shell
  scripts. Rules include test cases (valid `.semgrep/rules/tests/` directory).
  Verified by running `semgrep --config .semgrep/rules/ .` and confirming the
  rules produce at least one finding in the provided test fixtures.

- [AC-12] (Stretch — deferred) `docs/security/openssf-silver-checklist.md`
  exists and maps every OpenSSF Best Practices Silver-level requirement to the
  repo location where that requirement is satisfied, with an explicit "NOT YET"
  for requirements not yet met. Verified by confirming the file exists and
  contains the string "Silver" and at least one "NOT YET" entry (ensuring it is
  not a trivially empty checklist).

---

## Non-goals

- This spec does not introduce Trivy or Grype (image scanning). Walter-OS ships
  no container images as release artifacts. OSV-scanner covers dependency
  scanning; Trivy image scanning is out of scope for v0.1.
- This spec does not add Dependabot or Renovate automatic PR creation for
  dependency updates (`.github/renovate.json` is managed separately). The OSV-
  scanner workflow is detection-only, not auto-update.
- This spec does not change the existing `approval-gate.sh` BLOCK_BASH_PATTERNS
  array. The new `bash-denylist.sh` is an additive hook, not a replacement.
- This spec does not generate or manage GPG/PGP keys. Cosign keyless (OIDC)
  signing is used throughout. The placeholder PGP key in `SECURITY.md` (PR #49)
  is out of scope here.
- This spec does not add mutation testing, property-based testing, or load
  testing to the CI pipeline.
- The OpenSSF Silver Badge application process (submitting the form to the
  badging program) is not automated. AC-12 produces the checklist file only.
  Submission is an operator action.

---

## Open Questions

1. **gitleaks config placement**: Should `.gitleaks.toml` live at the repo root
   or under `.github/`? The pre-commit hook integration (using
   `gitleaks protect`) reads the root by convention; CI uses `gitleaks detect`.
   Both need the same config file. Recommend root; confirm before implementation.

2. **cosign bundle format**: cosign 2.x changed the `--bundle` flag semantics
   relative to 1.x. The release workflow in PR #47 pins `cosign-installer` to a
   version — confirm that version before writing the signing step. If PR #47
   is not yet merged when implementation begins, the implementer must coordinate
   to avoid conflict on `release.yml`.

3. **OSV-scanner CVSS threshold**: The acceptance criterion says CVSS >= 7.0.
   The `google/osv-scanner-action` does not natively filter by CVSS score in its
   default mode — it fails on any finding. Should the workflow use
   `--fail-on-vuln-with-cvss-score=7.0` (requires checking the action's flags),
   or should the workflow use the `osv-scanner` binary directly with a severity
   filter? Confirm the action version and flag availability before implementation.

4. **CodeQL language suite for shell**: GitHub's CodeQL does not have a
   first-class `bash` query suite the same way it does for JavaScript. The
   correct approach is to use `github/codeql-action/analyze` with
   `language: javascript` for the TS/Next.js code and rely on gitleaks + semgrep
   for shell-specific patterns. Confirm whether a separate CodeQL pass for shell
   is worth the CI cost, or whether gitleaks + shellcheck already covers it
   adequately.

5. **`make audit` tool installation**: The `Makefile` audit target needs to
   detect missing tools gracefully and print install instructions rather than
   failing silently. Confirm the preferred failure mode: hard-fail (exit 1) when
   a required tool is absent, or soft-warn and skip? Recommend hard-fail for
   required tools (gitleaks, shellcheck) and soft-warn for optional tools (syft,
   osv-scanner CLI) that are only required in CI.

---

## References

- PR #47 (`v0.2.0-walter-oss`): release workflow, CHANGELOG, LICENSE, NOTICE, VERSION
- PR #48: AGPLv3 + Xipher Labs branding
- PR #49 (`feature/oss-ready-docs`): SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md
- PR #54: gitleaks pin fix in `daily-supply-chain-audit`, elevenlabs-mcp pin
- `hooks/approval-gate.sh` — existing BLOCK_BASH_PATTERNS array (§ "analyze" function)
- `AGENTS.md` — "Supply chain" section defining the daily audit expectations
- `docs/decisions/0009-agent-trust-tiers.md` — trust tier model (hook chain context)
- OpenSSF Scorecard: https://github.com/ossf/scorecard
- syft (SBOM generation): https://github.com/anchore/syft
- cosign (keyless signing): https://github.com/sigstore/cosign
- OSV-scanner: https://github.com/google/osv-scanner
- gitleaks: https://github.com/gitleaks/gitleaks
- CodeQL action: https://github.com/github/codeql-action
- OpenSSF Best Practices Silver Badge: https://www.bestpractices.dev/en/criteria/1
