# ADR 0017 — Ship a shrinkwrap alongside the OpenClaw runtime install

**Status**: Proposed (2026-05-21).
**Date**: 2026-05-21.
**Deciders**: operator (f0x1777) — pending approval.
**Related**: spec `docs/specs/openclaw-supply-chain-lockfile.md`, issue #132, ADR 0012, ADR 0016.

## Context

v0.4.4's PR #127 added top-level SHA512 integrity verification + `--ignore-scripts` to the OpenClaw runtime npm install. Codex R2 cross-review caught that transitive dependencies remain unverified beyond npm's own per-registry-entry integrity check, which doesn't survive a registry-side compromise of any single dep.

The repo already pins everything else by content hash (hooks via `hook-checksums.json` v2, container images via `@sha256:...` digests). OpenClaw's npm-dep tree is the last hash-less surface in the install path.

## Decision

Ship a hand-regenerated `npm-shrinkwrap.json` alongside the OpenClaw compose pinning. Install via `npm ci --ignore-scripts` against that shrinkwrap. Operator regenerates the shrinkwrap quarterly during the version bump; CI bats-tests that the shrinkwrap exists + matches the pinned `OC_VER`.

### Why a shrinkwrap rather than the other options

**Rejected alternative 1 — Bundle deps INTO the openclaw tarball via `npm pack` upstream.**

Pros: zero install-time network. Reproducibility by definition.
Cons: Requires changes to the openclaw publish pipeline (out of walter-os's control). Tarball size balloons (potentially 50-100MB vs current ~500KB). Operator-side trust still requires verifying the bundled tarball, which is what we already do for the top-level package — no leverage gained.

**Rejected alternative 2 — Pre-fetch every dep into an npm cache store + install offline.**

Pros: bit-exact reproducibility. No network at install time.
Cons: requires shipping the entire cache tree (~50MB+) in the walter-os repo. Doesn't fit "git-cloneable repo" model. The shrinkwrap approach gives the same determinism guarantee with a 10KB JSON file.

**Rejected alternative 3 — IPFS-pin every dep + resolve via IPFS gateway.**

Pros: content-addressed, registry-independent.
Cons: introduces IPFS as a new operational dependency on every install. Operator + walter-os trust surface grows substantially. Solves a problem the operator doesn't currently have.

**Rejected alternative 4 — `package-lock.json` instead of `npm-shrinkwrap.json`.**

The two formats are content-identical. `package-lock.json` is the npm-default for development; `npm-shrinkwrap.json` is the format intended to survive `npm publish` and is the canonical "this is a deterministic-install artifact" marker. Both work; shrinkwrap signals intent more clearly.

**Selected: ship `npm-shrinkwrap.json` + `npm ci`.**

### Why a shrinkwrap-honoring install (not the naive `npm install -g <tarball>`)

The current PR #127 flow (`npm install -g --ignore-scripts ./tarball`) does NOT consume an external shrinkwrap — npm's global-install path resolves deps fresh from the registry every time. To honor the shrinkwrap, we have to introduce one of three flows (spec §4.2 Candidates A/B/C). The exact choice is deferred to prototype evidence on `node:24-slim`; the recommendation is Candidate A (wrapper-package + `npm ci` + `npm link`) for its standard-npm-semantics + audit clarity.

Codex R1 on the initial draft of this ADR caught that the obvious `npm ci --prefix /workspace/.npm-global ./tarball` doesn't actually install globally — `npm ci` is project-install-oriented + only materializes `./node_modules/`, leaving `/workspace/.npm-global/bin/openclaw` (which the rest of compose relies on) missing. The corrected design routes through `npm link` after the deterministic dep install.

## Consequences

**Positive:**

- Closes issue #132's documented gap. Reproducible installs from the same commit always resolve to the same dep tree.
- Operator pins what they trust at version-bump time, blocking later registry compromises.
- Bats test (AC4/AC5) catches the "forgot to regenerate" case in CI.
- Pattern is reusable for other runtime npm consumers (F1 in the spec).

**Negative:**

- Quarterly version bump now involves a small extra step (regenerate shrinkwrap, ~30 sec of operator time).
- Shrinkwrap is ~10KB of JSON in the repo — adds noise to per-version diffs.
- If `openclaw` upstream bumps a transitive dep without a compatible semver bump on the top-level package, the operator's local shrinkwrap won't update on its own — quarterly cadence catches this; weekly Renovate-style automation could close the gap further (F3 in the spec).

**Reversible:**

Yes. Removing the shrinkwrap + reverting to `npm install` returns to v0.4.4 behavior. The operator can also opt into bypassing the shrinkwrap during incident response by overriding the compose `command:` block (documented in tier-3.md).

## Migration

1. This spec/plan/ADR PR lands (docs-only — no behavior change in v0.4.5).
2. Implementation PR (separately) generates the first shrinkwrap for the current `openclaw@2026.5.7`, updates both compose files, adds the bats coverage.
3. v0.4.6 ships with the shrinkwrap-based install. Operators upgrading from v0.4.5 see a clean install transition (the openclaw container restarts + npm ci replaces npm install — no state change in `/workspace/.openclaw/`).
4. Quarterly-upgrade-cadence skill is updated in the same impl PR (per spec AC6).

## References

- Spec: `docs/specs/openclaw-supply-chain-lockfile.md`
- Issue #132 (filed during the v0.4.4 cross-review cycle)
- PR #127 — the v0.4.4 partial mitigation
- ADR 0012 — OSS security hardening primitives (parent)
- ADR 0016 — hook-checksums v2 (similar lockfile-shipping pattern, different surface)
