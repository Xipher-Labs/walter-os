# OpenSSF Best Practices Silver Badge — Walter-OS Self-Assessment

> Status: **draft / WIP**. Initial mapping created 2026-05-12.
> Source of truth for criteria: <https://www.bestpractices.dev/criteria/1#silver>
> Walter-OS does not yet hold a Passing badge — that is a prerequisite for
> Silver. This document tracks the gap from current state to Silver-ready.

Legend:

- ✅ — criterion met today, evidence linked.
- ⚠️ — partially met; gap noted.
- ❌ — not met; TODO noted.
- 🚧 — N/A or deferred (with reason).

---

## Basics

### Prerequisites

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `achieve_passing` | MUST hold a Passing-level badge first. | ❌ | TODO: complete the Passing checklist (separate doc). Silver work blocked until Passing is filed. |

### Basic project website content

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `contribution_requirements` | Acceptable contribution requirements, incl. coding standards. | ⚠️ | `AGENTS.md` describes the contribution + branch flow. Missing dedicated `CONTRIBUTING.md` at repo root. TODO: extract from AGENTS. |

### Project oversight

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `dco` | DCO, CLA, or equivalent legal mechanism. | ❌ | TODO: enable DCO via `.github/workflows/dco.yml` and document in CONTRIBUTING. |
| `governance` | Documented decision-making model. | ❌ | TODO: write `GOVERNANCE.md`. Current de-facto model: BDFL (operator). |
| `code_of_conduct` | Public Code of Conduct. | ❌ | TODO: adopt Contributor Covenant v2.1 at `CODE_OF_CONDUCT.md`. |
| `roles_responsibilities` | Documented roles + assignments. | ❌ | TODO: `MAINTAINERS.md` listing reviewer rotation. |
| `access_continuity` | Continuity of critical functions if a person disappears for ≥1 week. | ⚠️ | Secrets via Vaultwarden on local LLM node (recoverable). No documented dead-man procedure. TODO: runbook. |
| `bus_factor` | Bus factor ≥ 2. | ❌ | Single-operator project today. Inherent gap until external contributors join. |

### Documentation

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `documentation_roadmap` | Roadmap covering ≥1 year. | ⚠️ | `README.md` documents Phase 1 + Phase 2 (local LLM node). Not labelled "roadmap". TODO: extract to `ROADMAP.md`. |
| `documentation_architecture` | Architecture + high-level design documented. | ⚠️ | Spread across `AGENTS.md` and `docs/decisions/`. No single `ARCHITECTURE.md`. TODO: consolidate. |
| `documentation_security` | Security expectations + limitations documented. | ✅ | Root `SECURITY.md`, duplicate `.github/SECURITY.md` for GitHub discoverability, `docs/security/`, and `daily-supply-chain-audit` skill. |
| `documentation_quick_start` | Quick-start for new users. | ✅ | `README.md` contains an install / setup section + `install.sh --upgrade` flow. |
| `documentation_current` | Docs in sync with code. | ⚠️ | AGENTS.md / README updated per phase. No automated check. Renovate keeps deps fresh. |
| `documentation_achievements` | Link to recognition within 48h. | 🚧 | N/A until first external recognition. |

### Accessibility and internationalization

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `accessibility_best_practices` | A11y best practices. | 🚧 | CLI tool — limited surface. Control Tower UI follows `frontend-quality` skill (WCAG 2.2 AA). |
| `internationalization` | Supports localization. | 🚧 | CLI tool, English-only by design for repo output. Casual chat can follow operator preference. |

### Other

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `sites_password_security` | Iterated hashing + per-user salt for stored passwords. | 🚧 | No first-party auth surface. Secrets delegated to Vaultwarden. |

---

## Change Control

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `maintenance_or_update` | Maintain older versions OR document upgrade path. | ⚠️ | `install.sh --upgrade` is the documented path. No N-1 maintenance branch. Acceptable for pre-1.0. |

---

## Reporting

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `report_tracker` | Issue tracker in use. | ✅ | GitHub Issues + Plane (self-hosted). |
| `vulnerability_report_credit` | Credit reporters unless they ask to be anonymous. | ✅ | `SECURITY.md` says responsible reporters are acknowledged in release notes. |
| `vulnerability_response_process` | Documented procedure for handling vulnerability reports. | ✅ | `SECURITY.md` documents private advisory/email channels, report contents, 48-hour acknowledgement, 7-day update, and 90-day disclosure window. |

---

## Quality

### Coding standards

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `coding_standards` | Identified style guide(s). | ✅ | `AGENTS.md` § Commit hygiene + § Output format. Conventional commits. |
| `coding_standards_enforced` | Enforced where FLOSS tools exist. | ✅ | shellcheck in `.github/workflows/ci.yml`, prettier/eslint in `apps/control-tower/`, this PR adds semgrep. |

### Working build system

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `build_standard_variables` | Honor CC/CFLAGS/LDFLAGS. | 🚧 | No compiled artifacts at this level (shell + TypeScript). |
| `build_preserve_debug` | Preserve debug info. | 🚧 | Same — N/A for shell. |
| `build_non_recursive` | No recursive interdependent build. | 🚧 | N/A. |
| `build_repeatable` | Bit-for-bit reproducible. | ⚠️ | `install.sh` is idempotent; deterministic install not yet proven. `pnpm-lock.yaml` pinned. |

### Installation system

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `installation_common` | Standard install/uninstall. | ✅ | `install.sh` and `install.sh --uninstall` (verify present). |
| `installation_standard_variables` | Honor DESTDIR etc. | ⚠️ | `WALTER_OS_HOME` honored. Not all standards. |
| `installation_development_quick` | Quick dev environment + tests. | ✅ | `pnpm install && bats tests/` after clone. |

### Externally-maintained components

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `external_dependencies` | Machine-readable dep list. | ✅ | `pnpm-lock.yaml`, `mcp/servers.json`, `.gitmodules`, soon: `cargo audit` lockfiles for any Rust additions. |
| `dependency_monitoring` | Monitor for known vulns. | ✅ | Renovate (`hooks/renovate.json` — verify), `daily-supply-chain-audit` skill, Dependabot via GitHub. |
| `updateable_reused_components` | Easy to identify + update. | ✅ | Renovate dashboard + quarterly cadence skill. |
| `interfaces_current` | Avoid deprecated APIs. | ⚠️ | Spot-checks only. No automated linter for deprecated calls in shell scripts. |

### Automated test suite

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `automated_integration_testing` | Run on every check-in. | ✅ | `.github/workflows/ci.yml` runs on push/PR; this PR adds `semgrep.yml`. |
| `regression_tests_added50` | Add regression tests for ≥50% of fixed bugs within 6 months. | ⚠️ | Done case-by-case (P0-04 `doctor-eval-injection.bats`, lessons.sh `load-lessons-json-safety.bats`). No formal tracking. TODO: tag commits, audit quarterly. |
| `test_statement_coverage80` | ≥80% statement coverage. | ❌ | No coverage measurement today for shell scripts (kcov not wired). `apps/control-tower/` has vitest but no enforced threshold. TODO. |

### New functionality testing

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `test_policy_mandated` | Formal test policy for major features. | ✅ | `AGENTS.md` § Brainstorm → Plan → Test → Code → Review → Verify + § Task rigor levels mandate TDD. |
| `tests_documented_added` | Change proposal instructions reference test policy. | ✅ | Same section; `definition-of-done-validator` skill enforces. |

### Warning flags

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `warnings_strict` | Maximize warnings where practical. | ⚠️ | shellcheck strict mode in `ci.yml`. TypeScript: confirm `strict: true` in `apps/control-tower/tsconfig.json`. |

---

## Security

### Secure development knowledge

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `implement_secure_design` | Apply secure design principles. | ⚠️ | `agents/security-auditor.md` reviews changes; `daily-supply-chain-audit` skill; this PR adds semgrep rules. No documented threat model. TODO: link to architecture doc once written. |

### Basic good cryptographic practices

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `crypto_weaknesses` | No known-weak default crypto. | 🚧 | No first-party crypto. |
| `crypto_algorithm_agility` | Multiple algorithms supported. | 🚧 | N/A. |
| `crypto_credential_agility` | Credentials separate from config. | ✅ | `.env.local` (gitignored) + Vaultwarden. |
| `crypto_used_network` | TLS by default, insecure disabled. | 🚧 | Inherited from underlying tools (curl, gh, etc.). |
| `crypto_tls12` | TLS ≥ 1.2. | 🚧 | Inherited. |
| `crypto_certificate_verification` | Verify certs by default + subresources. | 🚧 | Inherited. |
| `crypto_verification_private` | Verify before sending private headers. | 🚧 | Inherited. |

### Secure release

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `signed_releases` | Cryptographically sign releases + document verify procedure. | ❌ | No releases yet. TODO: sigstore/cosign workflow when v0.1 ships. |
| `version_tags_signed` | Sign major/minor tags. | ❌ | TODO: same. Operator's GPG key already in use for commits. |

### Other security issues

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `input_validation` | Allowlist-based input validation. | ⚠️ | Several hooks validate (`wiki-validator.sh`, `branch-flow-guard.sh`). Not uniform across all entry points. |
| `hardening` | Hardening mechanisms applied. | ✅ | Trust tiers, gate locks, secret redactor, daily audit, semgrep rules (this PR). |
| `assurance_case` | Justification for security requirements incl. threat model. | ❌ | TODO: write `docs/security/threat-model.md`. |

---

## Analysis

| ID | Description | Status | Evidence / TODO |
|---|---|---|---|
| `static_analysis_common_vulnerabilities` | Use ≥1 static analysis tool. | ✅ | shellcheck + semgrep custom rules (this PR). Future: cargo clippy + rust deny when Rust is added. |
| `dynamic_analysis_unsafe` | Dynamic analysis for memory-unsafe languages. | 🚧 | No memory-unsafe code today. Will apply when Rust/C land. |

---

## Summary

Total Silver criteria mapped: **55**

- ✅ met: **18**
- ⚠️ partial: **13**
- ❌ unmet: **10**
- 🚧 N/A / deferred: **14**

Headline gaps blocking Silver:

1. `achieve_passing` — prerequisite Passing badge not yet filed.
2. Repo hygiene files missing or incomplete: `CODE_OF_CONDUCT.md`,
   `CONTRIBUTING.md`, `GOVERNANCE.md`, `MAINTAINERS.md`.
3. `signed_releases` / `version_tags_signed` — no release process yet.
4. `assurance_case` — threat model not written.
5. `test_statement_coverage80` — no coverage measurement wired.

Suggested next work order (smallest first):

1. Add `CODE_OF_CONDUCT.md` (small PR).
2. Extract `CONTRIBUTING.md` from `AGENTS.md`.
3. Wire kcov for shell-script coverage; set 50% floor, ratchet up.
4. Write `docs/security/threat-model.md`.
5. File the Passing badge application, then this Silver checklist
   becomes actionable.
