# OSS Trust v0.5.0 small-batch — combined spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: OSS Trust roadmap — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83) (post-merge in-tree path: `docs/specs/oss-trust-roadmap.md`).
**Items**: C-3 (pre-commit framework), D-1 (Security Advisories), E-3 (`@types/*` allowlist), E-4 (`walter-os justify revoke`)
**Target release**: v0.5.0
**Why batched**: each item is small (≤200 LOC, ≤4h), well-bounded, and lands in the same release. Bundling reduces PR noise.

---

## C-3 — Pre-commit framework integration for gitleaks

### Problem

Walter-OS ships a raw git hook for gitleaks at `.githooks/pre-commit` (activated by setting `core.hooksPath=.githooks` via `scripts/setup-githooks.sh`, with `scripts/install-pre-commit.sh` as an alternative installer that wires the same hook into `.git/hooks/`). Operators using the [pre-commit framework](https://pre-commit.com) for other repos have to choose between Walter-OS's raw hook OR their own framework setup — they conflict on the same git-hook path.

### Decision

Ship a `.pre-commit-config.yaml` ALONGSIDE the raw hook. Operator picks one. The raw hook stays the default (one less tool to install); the framework config is opt-in for operators already using pre-commit elsewhere.

### Acceptance criteria

- [ ] `.pre-commit-config.yaml` (new) at repo root:
  ```yaml
  # Walter-OS pre-commit framework config (opt-in alternative to the
  # raw hook activated via `core.hooksPath=.githooks` —
  # `.githooks/pre-commit` runs gitleaks today, see
  # scripts/setup-githooks.sh / scripts/install-pre-commit.sh).
  # Choose ONE path — running both runs gitleaks twice per commit.

  repos:
    - repo: https://github.com/gitleaks/gitleaks
      rev: <pinned-rev-here>   # commit SHA, NOT a movable tag
      hooks:
        - id: gitleaks
          name: gitleaks (pre-commit framework)
  ```
- [ ] `.gitleaks.toml` (already exists) is unchanged — both paths read it.
- [ ] `setup/Brewfile` ships `pre-commit` as optional (alongside the existing `gitleaks`).
- [ ] `docs/operational/pre-commit-setup.md` (new) compares the two paths + tells operators which to pick.
- [ ] `tests/oss/pre-commit-config.bats` (new) — asserts `.pre-commit-config.yaml` is valid YAML AND its `gitleaks` rev matches a pinned version.

---

## D-1 — GitHub Security Advisories partner registration

### Problem

Walter-OS has `SECURITY.md` with an email contact for disclosure, but no GitHub Security Advisories channel. Bug-bounty researchers and security teams prefer GHSAs because:
- Coordinated disclosure timeline tooling
- CVE assignment (GitHub is a CNA for any registered repo)
- Audit-trail visible to the operator

### Decision

Register Walter-OS for GitHub Security Advisories. Update `SECURITY.md` to direct disclosures via GitHub's private advisory flow. Keep the email as fallback.

### Acceptance criteria

- [ ] Operator (manual action, NOT code) enables GHSA in repo settings: `Settings → Security → Code security → Private vulnerability reporting → Enable`.
- [ ] `SECURITY.md` updated:
  - Primary disclosure: `https://github.com/Xipher-Labs/walter-os/security/advisories/new`
    (mixed-case `Xipher-Labs` — the canonical org-slug casing used by every
    other github.com URL in this repo, e.g. `docs/security/verification.md`'s
    `--certificate-identity-regexp` and the GitHub Actions release workflow).
    GitHub URLs are case-insensitive on the path but the rendered link
    text should match the org's canonical casing for readability and
    for tools that compare strings.
  - Secondary: existing email
  - Coordinated-disclosure timeline (90d default; faster for critical)
- [ ] `.github/SECURITY.md` is a **duplicate file** (NOT a symlink),
  kept in sync via a CI lint that fails if the two files diverge.
  Symlinks are fragile on Windows checkouts and ignored by some
  scanners; duplicating with a lint guard avoids both problems.
- [ ] `.github/ISSUE_TEMPLATE/security.md` (the existing "STOP →
  SECURITY.md" placeholder) is updated to point researchers at the
  GHSA URL instead of just SECURITY.md, since GHSA is the new
  primary channel. Public issue filing for security is still
  disallowed.
- [ ] CHANGELOG entry under `[Unreleased] → Security`.

### Out of scope

- Full CNA registration (separate from GHSA partnership). Post-v1.0.
- Bug-bounty program with money rewards. Operator decision; can be added later.

---

## E-3 — `@types/*` allowlist for `minimumReleaseAge`

### Problem

`skills/daily-supply-chain-audit/scripts/check-release-age.py` enforces a minimum-release-age gate (default 21 days) to avoid pulling freshly-published npm/PyPI packages that might be malicious. `@types/*` packages publish frequently (often hourly) because they auto-update with their upstream's API changes. Blocking every `@types/*` bump on the 21-day rule generates daily false positives.

Deferred from PR #60.

### Decision

Hardcoded allowlist of npm scopes that bypass the minimum-release-age check (with rationale documented):
- `@types/*` — TypeScript type stubs, published by community + DT bot
- `@walter-os/*` — internal scope (operator-owned packages, future)
- Any operator-extended scope via `WALTER_AUDIT_RELEASE_AGE_ALLOWLIST_SCOPES` env var

### Acceptance criteria

- [ ] `check-release-age.py` reads a hardcoded list + an env-var-extensible list.
- [ ] When a package's scope matches → release-age check is skipped; `ok: true, age_check_skipped: "allowlisted_scope"` returned.
- [ ] `tests/unit/test_check_release_age.py` extended with:
  - `@types/react@19.0.5` published 2 days ago → ok: true (allowlisted scope)
  - `@types/react@19.0.5` published 2 days ago, scope removed from allowlist → ok: false (normal min-age check applies)
  - Operator extends allowlist via env var → custom-scope package passes
- [ ] CHANGELOG entry under `[Unreleased] → Changed (supply-chain audit)`.

### Threat model

`@types/*` is a documented-safe scope (DefinitelyTyped curators + automated bot publishing). The allowlist applies per-SCOPE: skipping `check-release-age` for `@types/*` means a hypothetical `@types/malicious-package` published from a compromised DefinitelyTyped maintainer account would NOT trip the release-age gate. The remaining defenses on that path today are limited and worth stating accurately:

- Snyk `mcp-scan` IF the operator has it installed (`skills/daily-supply-chain-audit/scripts/audit.sh` calls it only when `command -v mcp-scan` succeeds — see line 136). Not present on every host.
- The static pinning + frontmatter + cross-reference lints (semgrep is wired into CI for the Walter-OS REPO itself, NOT for inspecting third-party `@types/*` payloads at audit time — `nosemgrep` comments in `check-release-age.py` are about the linter's view of Walter-OS source, not third-party-package scanning).
- Operator's own review of the diff when a `@types/*` change shows up in `pnpm install` output.

The risk delta is reduced-but-non-zero — we trade some bypass of the age gate for the practical ability to consume DefinitelyTyped patches the day they ship. Operators who want stricter posture can clear the allowlist via env var. Future Layer-A items (network-egress allowlist A-1, capability tokens A-2) tighten the runtime blast radius even when a malicious `@types/*` does land.

---

## E-4 — `walter-os justify revoke` CLI

### Problem

`walter-os justify` is **already specified** in `docs/specs/walter-os-protection-levels.md` (and its `.plan.md` companion) — the CLI surface and `justify-log.jsonl` format land there. `check-release-age.py` is the consumer that already reads the log when filtering audit findings. The walter-debt-tracker spec (#77) extends `justify` with a debt-report view but does NOT introduce the command itself.

The existing protection-levels plan stub-specs `walter-os justify revoke <pkg>@<ver>` as "adds expiry = now (soft revoke)" — one sentence, no detail on chain integrity. That stub works for the 90d-TTL use case but does NOT survive the Merkle-chain promise from OSS Trust Layer B (B-1 + B-2): editing an existing entry's `expires` field rewrites a JSONL row that's already been chained, which breaks the prev_hash → sig integrity.

E-4 in this spec REFINES the stub: instead of mutating the original `expires`, append a NEW entry with `kind: "revoke"` and a `supersedes` pointer. Audit + debt-report views filter out revoked items by walking the supersession chain. Merkle chain stays intact because each entry is append-only. Deferred from PR #60.

### Decision

`walter-os justify revoke <pkg>@<version> "<reason>"` appends a `kind: "revoke"` entry that supersedes the original (replaces the protection-levels stub's "edit `expires`" approach with an append-only superseding entry; rationale above). The audit + debt-report views filter out revoked items by walking the supersession chain. Merkle chain stays intact (revoke is a new entry, not an edit).

### Acceptance criteria

- [ ] `walter-os justify revoke <pkg>@<version> "<reason>"` CLI:
  - Reads `~/.config/walter-os/justify-log.jsonl`
  - Finds the most recent NON-REVOKED entry matching `pkg` + `version`
  - Appends a new entry: `{kind: "revoke", supersedes: "<original-ts>", pkg, version, reason, operator, ts}`
  - If no matching entry → exit 1 with "no active justify for <pkg>@<version>"
- [ ] `check-release-age.py` filters out revoked justifies BEFORE applying the suppression logic.
- [ ] `walter-os debt-report` (from #77) marks revoked items as `[x] revoked YYYY-MM-DD — <reason>` in the .walter-debt.md output.
- [ ] `tests/unit/test_check_release_age.py` extended:
  - Justify entry exists → suppresses the finding
  - Justify entry exists + revoke entry exists → does NOT suppress
  - Justify entry exists + revoke + new justify → does suppress (supersession order matters)
- [ ] CHANGELOG entry under `[Unreleased] → Added`.

---

## Recommended PR ordering (for the combined batch)

1. **E-4 first** — walter-os justify revoke (depends on #77 walter-debt-tracker spec being acked; small enough to ship right after #77's first impl PR)
2. **E-3** — `@types/*` allowlist (independent, smallest)
3. **C-3** — pre-commit framework config (independent, smallest)
4. **D-1** — Security Advisories registration (mostly operator action; doc-only PR for SECURITY.md update)

All four are ≤200 LOC each, ≤4h each. Estimated total: 1 working day for an operator following `/execute-plan`.

## Open questions for the operator

1. **C-3 pre-commit framework rev pinning**: pin the `rev:` of the `gitleaks/gitleaks` repo (the pre-commit hook source — NOT the same thing as the `gitleaks/gitleaks-action` GitHub Action used in CI) to a specific commit SHA (proposal — same supply-chain discipline as elsewhere)? Or use `pre-commit autoupdate` flow? Proposal: pin to commit SHA; autoupdate is opt-in via operator running it deliberately.
2. **D-1 disclosure timeline**: 90 days default (proposal — industry standard), or shorter (60) given Walter-OS's small surface? Proposal: 90; explicit operator-can-shorten note in SECURITY.md.
3. **E-3 allowlist scope**: `@types/*` only (proposal), or also `@walter-os/*` (internal future scope) and `@stryker-mutator/*` (operator-trusted)? Proposal: `@types/*` + `@walter-os/*` for v0.5.0; operator extends via env var.
4. **E-4 revoke supersession**: should revoke ALSO require an `--with-pin <exact-version>` flag so the operator can't leave the package un-pinned-and-un-justified (gap state)? Proposal: yes — a revoke without a replacement justify+pin is itself a debt-tracker entry.

## Refs

- Parent: OSS Trust roadmap Layer C C-3 + Layer D D-1 + Layer E E-3 + E-4 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); post-merge in-tree path is `docs/specs/oss-trust-roadmap.md`.
- **Existing `walter-os justify` spec**: `docs/specs/walter-os-protection-levels.md` (and `.plan.md` companion) — already on main, defines the CLI + log format that E-4 extends with `revoke`.
- Sibling: walter-debt-tracker — [PR #77](https://github.com/Xipher-Labs/walter-os/pull/77) (post-merge: `docs/specs/walter-debt-tracker.md`). E-4's revoke entries surface in walter-debt's debt-report view; the CLI itself is owned by protection-levels.
- `skills/daily-supply-chain-audit/scripts/check-release-age.py` (E-3 + E-4 modify this — already reads the justify log).
- `SECURITY.md` (D-1 updates this).
- Walter-OS [PR #60](https://github.com/Xipher-Labs/walter-os/pull/60) (where E-3 + E-4 were originally deferred from).
