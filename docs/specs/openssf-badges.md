# OpenSSF Best Practices Badges (OSS Trust E-1 + E-2) — combined spec

**Status**: ready for `/write-plan` after operator approval
**Scope of this PR**: spec only. The implementation (new operational docs `docs/operational/openssf-badge-passing.md` and `.../openssf-badge-silver.md`, a `walter-os audit badge-prereqs` CLI subcommand, and the README badge update) ships in follow-up PRs once this spec is approved.
**Parent**: OSS Trust roadmap Layer E items E-1 + E-2 — umbrella spec is in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); once that merges the in-tree path is `docs/specs/oss-trust-roadmap.md`.
**Target releases**: v0.5.0 (Passing) → v0.6.0 (Silver)
**Depends on**: D-1 GitHub Security Advisories partner — spec'd in the small-batch [PR #89](https://github.com/Xipher-Labs/walter-os/pull/89) (post-merge file: `docs/specs/oss-trust-v0.5.0-small-batch.md`). Same release cycle as Passing.

## Problem

The OpenSSF Best Practices Badge program (formerly CII Badge) is the lingua franca for "this OSS project takes security seriously." Three tiers: **Passing**, **Silver**, **Gold**. Walter-OS today meets most Passing criteria but is unfiled. Filing the Passing badge is the gate to filing Silver (which adds policy controls Walter-OS will already have after the OSS-trust v0.5.0 batch).

Why this matters:
- Adoption-readiness signal for security-conscious operators.
- Pre-req for some downstream adoption (some corp procurement gates ask for OpenSSF Passing).
- Forcing function: the badge questionnaire catches gaps we'd otherwise miss.

## Non-goals

- Gold badge in v0.5.x. Gold requires SLSA L3 (C-1, target v1.0) + reproducible builds (C-2, v1.0+). Gold target = v1.0.
- Per-criterion auto-attestation tooling. Manual answer-in-questionnaire is acceptable for v0.5.0.
- Re-architecting Walter-OS to fit the rubric. We answer what we already have; gaps go to per-item specs.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **File Passing in v0.5.0**, immediately after the D-1 (GHSA) partner registration ships. Silver in v0.6.0. | GHSA is one of Passing's required answers. Sequencing is forced. |
| D-2 | **Maintain the answers in-repo** at `docs/operational/openssf-badge-passing.md` (Passing) and `docs/operational/openssf-badge-silver.md` (Silver). Each answer references the Walter-OS file / commit / PR that satisfies the criterion. | Answers stay diff-able; future operators can update without re-reading the rubric. |
| D-3 | **`walter-os audit badge-prereqs`** subcommand checks every Passing / Silver criterion that has a programmatic-testable answer (LICENSE present, CHANGELOG present, SECURITY.md present, etc.). Operator-facing — gives a per-criterion status report. | Replaces "run through the questionnaire manually every 6 months" with a one-command check. |
| D-4 | **OpenSSF Best Practices badge** rendered in README (after Passing is approved). Live link to the OpenSSF profile page. This is the OpenSSF-published image badge, NOT a CI status badge — the two coexist (CI badge stays as-is; the OpenSSF badge sits next to it). | Visible trust signal at the top of every README view. |

## Acceptance criteria

### AC-1 — Passing badge questionnaire pre-walk

Before filing, walk through the [Passing criteria checklist](https://www.bestpractices.dev/en/criteria/0) and produce `docs/operational/openssf-badge-passing.md` with per-criterion `MET` / `NOT-MET` / `N/A` answers + references.

The Passing rubric has ~70 criteria. The high-confidence MET subset (already satisfied):

- **Basics**: project URL, project name, SPDX license (`AGPL-3.0-or-later`), README description — all present
- **Floss-License-OSI**: `AGPL-3.0-or-later` is OSI-approved
- **Documentation**: README has architecture overview, install steps, contributor guide → `CONTRIBUTING.md`
- **Other**: project tracks security-known vulnerabilities → audit ledger
- **Change-control**: public version-controlled repo, history, releases via tags
- **Reporting**: BUG_TRACKER URL = github issues, vulnerabilities → `SECURITY.md`
- **Quality**: working build (CI green), tests (bats + vitest), test policy in CONTRIBUTING
- **Security**: developer training (operator docs), application of secure design (`docs/operational/security-audit-*.md`), at least 1 hardening tool (gitleaks via `.githooks/pre-commit`, activated by `core.hooksPath=.githooks` — installer at `scripts/setup-githooks.sh` / `scripts/install-pre-commit.sh`; CI scan at `.github/workflows/gitleaks.yml`)

The gaps we likely need to address before filing (~5 criteria):

- `crypto_keylength` — Walter-OS doesn't ship custom crypto; relies on cosign/Sigstore for signing. **Action**: answer "N/A — we use battle-tested upstream cryptography (Ed25519 via PASETO v4 in OSS-trust A-2; cosign keyless OIDC for releases)".
- `static_analysis` — semgrep + shellcheck in CI. **MET** but reference the workflow.
- `dynamic_analysis` — bats + vitest. **MET** but reference the workflow.
- `vulnerability_response` — GHSA channel (depends on D-1 small-batch spec).
- `discussion` — community channel? Walter-OS has issues + Telegram bot for operator-private — public discussion via GitHub Discussions: **TODO enable**.

### AC-2 — Silver badge questionnaire pre-walk

Same shape as AC-1 for `docs/operational/openssf-badge-silver.md`. Silver adds ~30 additional criteria over Passing. Most v0.4.0 → v0.5.0 work already covers Silver's deltas:

- **Coding standards**: AGENTS.md / CONTRIBUTING.md
- **Build documentation**: README install + release.yml
- **Continuous integration**: ci.yml + release.yml + release-security workflow (folded into release.yml in PR #62)
- **Static analysis fix policy**: documented in AGENTS.md "Review loop"
- **Two-person review for releases**: walter-os branch-flow + 3-round-review policy already requires Copilot+Codex on every PR before merge (effectively two-reviewer minimum)
- **Memory-safety**: shell + python + JS — no C/C++ surface; answer N/A
- **Threat-model documentation**: `docs/operational/security-audit-2026-05-11.md`

Silver gaps:
- **Crypto provenance**: in v1.0 via SLSA L3 (C-1). Silver doesn't require Gold-level SLSA; answer "PASETO v4 + cosign + planned SLSA L3 for v1.0".
- **Reproducible builds**: same — defer to v1.0 (C-2).

### AC-3 — `walter-os audit badge-prereqs` CLI
- [ ] New subcommand checks every programmatic-testable criterion:
  - LICENSE present (Passing)
  - README ≥ 200 chars (Passing)
  - CONTRIBUTING.md present (Silver)
  - SECURITY.md present (Passing + Silver)
  - CHANGELOG.md present (Silver)
  - Any CI workflow file (Passing)
  - `gitleaks` or equivalent static-analysis hook (Passing)
  - At least 1 test workflow that runs on PR (Passing)
- [ ] Output: table with `criterion / target-tier / status / file-ref`.
- [ ] `walter-os audit badge-prereqs --tier passing|silver` filters output.
- [ ] bats coverage in `tests/cli/walter-os-badge-prereqs.bats`.

### AC-4 — Operator-action checklist
- [ ] `docs/operational/openssf-badge-filing-runbook.md` (new): step-by-step operator instructions:
  1. Run `walter-os audit badge-prereqs --tier passing` and resolve any `NOT-MET`
  2. Enable GitHub Discussions (settings → features) — closes the `discussion` gap
  3. Confirm GHSA partner registration (from D-1)
  4. Go to <https://www.bestpractices.dev/en/projects/new>, paste the repo URL
  5. Walk through the questionnaire using `docs/operational/openssf-badge-passing.md` as the answer source
  6. Submit; takes ~24h for approval
  7. Once approved: add the badge image to `README.md` (`[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/<ID>/badge)](https://www.bestpractices.dev/projects/<ID>)`)

### AC-5 — Silver filing follow-up
- [ ] After Passing is approved + v0.5.0 ships (with A-1 / A-2 / A-4 / D-1 / B-1 / B-2): file Silver.
- [ ] Same runbook; `--tier silver` flag for the prereq check.

### AC-6 — Docs + CHANGELOG
- [ ] `README.md` Status section adds a row to the "What's new since v0.X" list: "OpenSSF Passing badge filed (≈YYYY-MM-DD); Silver targeted for v0.6.0".
- [ ] CHANGELOG entry under `[Unreleased] → Added (community signals)`.

## Out of scope

- Gold badge (target v1.0; depends on SLSA L3 + reproducible builds).
- Auto-filling the OpenSSF web form. Manual operator action; this spec gives them the answers, not a robot.
- Maintaining the badge ↔ Walter-OS criteria mapping in a machine-parseable schema. Markdown is enough.
- Other OSS-trust signals (Scorecard, CHAOSS metrics). Future work.

## Recommended PR ordering

1. AC-1 — `docs/operational/openssf-badge-passing.md` with per-criterion answers
2. AC-3 — `walter-os audit badge-prereqs` CLI + bats
3. AC-4 — `docs/operational/openssf-badge-filing-runbook.md` (operator-facing)
4. **Operator action**: enable GitHub Discussions; file Passing; await approval
5. AC-2 — `docs/operational/openssf-badge-silver.md` (after Passing approved)
6. **Operator action**: file Silver
7. AC-6 — README badge image + CHANGELOG (closing PR)

## Open questions for the operator

1. **GitHub Discussions on/off**: the Passing rubric prefers a public discussion channel. Enable? Proposal: yes — adds a low-effort community-engagement surface that's already part of GitHub.
2. **Badge image location in README**: top header (above status badges) or new dedicated section? Proposal: top header next to version + audit badges, after Passing is approved.
3. **Re-walk cadence**: every release (v0.5.0, v0.6.0, ...) or once a year? Proposal: every major release, since each release adds criteria-satisfying changes that should be re-cited.

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` E-1 + E-2
- Sibling: `docs/specs/oss-trust-v0.5.0-small-batch.md` (D-1 GHSA — pre-req for Passing `vulnerability_response`)
- OpenSSF Best Practices Badge: <https://www.bestpractices.dev/>
- Passing criteria: <https://www.bestpractices.dev/en/criteria/0>
- Silver criteria: <https://www.bestpractices.dev/en/criteria/1>
- Gold criteria (reference only, target v1.0): <https://www.bestpractices.dev/en/criteria/2>
