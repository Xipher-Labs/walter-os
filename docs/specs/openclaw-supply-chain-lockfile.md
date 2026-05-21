# SPEC: OpenClaw runtime install — transitive-dep lockfile shipping

**Status:** Draft (2026-05-21). Awaiting operator approval.
**Triggered by:** Codex R2 cross-review on PR #127 (filed as issue #132). The SHA512 integrity check shipped in v0.4.4 verifies only the top-level `openclaw` tarball; transitive dependencies are still resolved live from the npm registry at install time, and each dependency's `package.json` semver range may resolve to a different physical artifact across installs.
**Related:** PR #127 (v0.4.4 mitigation: `--ignore-scripts` + `--registry=https://registry.npmjs.org/`), issue #132 (this work's tracking issue), ADR 0012 (OSS security hardening primitives).
**Rigor classification:** MAJOR (touches `setup/walter-host/services/openclaw/compose.yml` + `compose.yml`, both security-relevant first-boot install paths; introduces a new artifact distribution flow).

---

## 1. Problem

PR #127 (merged in v0.4.4) closed two-thirds of the OpenClaw npm-install supply-chain gap:

- ✅ SHA512 integrity check on the `openclaw` tarball itself (via a node one-liner that decodes the SRI from the operator-pinned hash and compares it to the actual file hash).
- ✅ `--ignore-scripts` to prevent `preinstall` / `install` / `postinstall` lifecycle scripts from executing — eliminates the immediate code-execution vector if any dep gets compromised.
- ✅ Explicit `--registry=https://registry.npmjs.org/` to defeat `/workspace/.npmrc` redirection.

What remains (issue #132 / Codex R2 BLOCKER from the v0.4.4 cycle):

- ❌ **Transitive dependencies** — when `npm install -g /tmp/openclaw-<ver>.tgz` runs, npm reads `openclaw`'s `package.json`, resolves the dependency tree against the registry's current "best match" for each semver range, and downloads each transitive tarball. Each transitive tarball IS individually verified by npm against the registry-published integrity field, but:
  1. **Registry compromise**: a maliciously-republished dep would have an updated integrity field, and npm would happily accept it. The SHA512 we pin only covers the top-level openclaw tarball.
  2. **Semver drift**: `^1.2.3` resolves to whatever's latest-compatible AT install time. A fresh install today vs in 90 days can pull different transitive versions even with `--ignore-scripts`.

The current state is "no execution risk on install, but the deployed code may not be byte-identical to what the operator intended". For a self-hostable framework where operators expect deterministic installs + supply-chain integrity, that's a gap worth closing.

## 2. Goals

- **G1.** Make the OpenClaw runtime install reproducible — given the same `OC_VER` + `OC_INTEGRITY`, every install on every machine resolves to the exact same dependency tree.
- **G2.** Block registry-compromise of any transitive dependency — the operator pins what they trust at the moment they pin `OC_VER`, and a later upstream republish does NOT silently change what installs.
- **G3.** No new tooling on the operator's host. The install path runs in the `node:24-slim` container; we already require `node` + `npm`. The fix must work within that constraint.
- **G4.** No new write capability granted to the openclaw container. The lockfile travels as a read-only artifact, just like the tarball.
- **G5.** Compatible with the quarterly upgrade cadence — the operator regenerates the lockfile + tarball-SHA512 together as one atomic version-bump.
- **G6.** Operator-side cost: the version bump now involves regenerating one extra file (a small `npm-shrinkwrap.json`-style artifact) + committing it. Acceptable trade for closing the supply-chain gap.

## 3. Non-goals

- **NG1.** Not pinning peer-dependency conflicts that openclaw might inherit. If `openclaw` ships with a broken peer-dep range, we surface the error; we don't silently work around it.
- **NG2.** Not auditing dep licenses or vulnerability status at install time — `walter-os audit` already covers the daily supply-chain scan layer; this spec is about deterministic install only.
- **NG3.** Not extending this approach to every npm install in the repo (litellm, node-exporter sidecars, etc.). OpenClaw is the precedent; if it works, follow-up specs can apply the same pattern to other runtime npm consumers.
- **NG4.** Not bundling the deps INTO the openclaw tarball itself — that's a `npm pack` upstream change we don't control and would balloon the artifact.

## 4. Design (proposed, awaiting locked decisions)

### 4.1 Artifact shape

Ship a **`npm-shrinkwrap.json`** file alongside the compose pinning. The operator generates it once per version bump via `npm install --ignore-scripts --package-lock-only --registry=https://registry.npmjs.org/` against either a wrapper package.json (Candidate A) or the extracted openclaw tarball (Candidate B), then renames the resulting `package-lock.json` to `npm-shrinkwrap.json`. (`--package-lock-only` skips actually-installing — we only need the lock metadata. The two filenames are content-identical; `npm-shrinkwrap.json` is the canonical "deterministic install artifact" marker.) The file lists every transitive package + version + integrity hash, locking the tree to exactly what the operator audited.

File location: `setup/walter-host/services/openclaw/npm-shrinkwrap.json`. Same dir as the standalone openclaw compose; ships through `git` with the rest of the repo.

### 4.2 Install-path change — candidates (PROTOTYPE-PENDING)

**Codex R1 caught (BLOCKER) that the obvious-sounding `npm ci --prefix ...` against a tarball doesn't actually install globally** — `npm ci` is project-install-oriented and only materializes a `node_modules/` tree, not the `/workspace/.npm-global/bin/openclaw` binary the rest of the compose `command:` block relies on. The naive flow would break first-boot.

Three candidate install flows are under evaluation; the implementation PR (separate from this spec) will pick one after a working prototype on `node:24-slim`. Each candidate preserves the current contract: produce `/workspace/.npm-global/bin/openclaw` AND verify every transitive dep against the shipped shrinkwrap.

**Candidate A — wrapper-package + npm ci + npm link.**

A tiny wrapper `package.json` has one dependency: `openclaw@<exact-OC_VER>`. The wrapper IS NOT a tracked file in the repo — it's generated in-container at install time via `printf` (single line, OC_VER + the wrapper-name are the only variables). The container does `npm ci --ignore-scripts` against the wrapper + the shipped shrinkwrap (deterministic deps), then `npm link openclaw` to expose the bin globally. Pros: standard npm flow; only one new tracked artifact (the shrinkwrap). Cons: introduces a wrapper-package concept the operator must understand.

Why generate, not track: a hand-tracked wrapper would have to be bumped in lockstep with OC_VER (operator gets it wrong half the time). Generating from OC_VER eliminates the drift surface. The wrapper has no security signal beyond "depend on openclaw@OC_VER" — that's already pinned by OC_VER + the shrinkwrap; the wrapper file itself is a re-declaration, not a trust anchor.

**Candidate B — extract tarball, install in-place with shrinkwrap.**

`tar -xzf openclaw-<ver>.tgz` into a fixed dir, copy the shipped shrinkwrap into the extracted `package/` dir, `cd package/ && npm ci --omit=dev --ignore-scripts`, then `npm link` (creates the global bin link). Pros: no wrapper. Cons: needs `tar` in the container (`node:24-slim` ships busybox-tar; verify).

**~~Candidate C — install-then-compare~~ (REJECTED, Codex R2 BLOCKER)**

A first draft considered `npm install -g --ignore-scripts ./tarball` (today's PR #127 flow) followed by a post-install node-script that walks the resolved tree and compares each `package.json` version against the shipped shrinkwrap. Codex R2 caught the fatal gap: by the time the drift check runs, the unverified deps are already on disk. The check would surface registry-side replacements AFTER the tampered code landed in the container's filesystem; lifecycle scripts are blocked but other classes of malicious-on-disk attacks (build-time code injection, transitive-dep-aware exploits) would still have a write surface. This violates G2 (block registry compromise), so Candidate C is rejected. The implementation PR must pick A or B.

**Recommendation pending prototype**: Candidate A — cleanest contract, standard npm semantics, easiest to reason about in audit. Candidate B if the wrapper feels heavier than the dual-step extract+link.

The shrinkwrap is mounted into the container via the compose volume layer (read-only). The host-side path differs between the two compose files because they have different working-dirs:

```yaml
# Root compose.yml (working-dir = repo root):
volumes:
  - ./setup/walter-host/services/openclaw/npm-shrinkwrap.json:/workspace/openclaw/npm-shrinkwrap.json:ro

# Standalone setup/walter-host/services/openclaw/compose.yml (working-dir = same dir):
volumes:
  - ./npm-shrinkwrap.json:/workspace/openclaw/npm-shrinkwrap.json:ro
```

Both resolve to the same in-container path; bats AC4 (extended) verifies both compose files mount it correctly.

### 4.3 Operator workflow on version bump (quarterly)

1. Bump `OC_VER` in both compose files (root + standalone).
2. Regenerate `OC_INTEGRITY` from the new tarball (same flow as today).
3. **NEW**: regenerate the shrinkwrap in a sandbox that mirrors the production install context — explicitly with `--ignore-scripts` so the generation step doesn't execute upstream lifecycle code on the operator's machine (closes Codex R1 #132 MAJOR — `no flags` would have implicitly run lifecycle scripts during generation, defeating part of the security model).

   **CRITICAL**: pass `--registry=https://registry.npmjs.org/` on the
   generation command too (Copilot R1 #140 catch). A lockfile records
   `resolved` URLs from whatever registry the operator's local npmrc
   currently points at — if that's a mirror, a private proxy, or a
   user-level npmrc override, the shipped shrinkwrap would lock the
   container to URLs the production environment can't (or shouldn't)
   reach. Pinning the registry at generation matches what the
   container's `npm ci` will use.

   For Candidate A (wrapper-package):
   ```sh
   mkdir /tmp/openclaw-shrinkwrap && cd /tmp/openclaw-shrinkwrap
   printf '{"name":"openclaw-wrapper","version":"1.0.0","dependencies":{"openclaw":"%s"}}\n' "$NEW_OC_VER" > package.json
   npm install --ignore-scripts --package-lock-only \
     --registry=https://registry.npmjs.org/
   mv package-lock.json $REPO/setup/walter-host/services/openclaw/npm-shrinkwrap.json
   # (rename: package-lock.json + npm-shrinkwrap.json are content-identical;
   #  we use the shrinkwrap name as the deterministic-install marker)
   ```

   For Candidate B (extract-in-place):
   ```sh
   npm pack openclaw@$NEW_OC_VER --registry=https://registry.npmjs.org/
   tar -xzf openclaw-$NEW_OC_VER.tgz
   cd package && npm install --ignore-scripts --package-lock-only \
     --registry=https://registry.npmjs.org/
   mv package-lock.json $REPO/setup/walter-host/services/openclaw/npm-shrinkwrap.json
   ```

4. Commit all three changes (compose × 2 + shrinkwrap) in one PR. The walter-os audit baseline reflects the new dep set.

The quarterly-upgrade-cadence skill gets an OpenClaw-specific section documenting this workflow.

### 4.4 Failure modes + guard rails

- **Lockfile / tarball mismatch (intentional)**: `npm ci` exits non-zero with a clear message. Compose container exits, operator sees the diff in `docker logs`. No partial install.
- **Lockfile compromise (e.g. supply-chain attack on the operator's local generation step)**: out of scope — the operator is the trust anchor for the lockfile, same as they're the trust anchor for `OC_INTEGRITY`. Documented in the operator workflow as "regenerate in a clean sandbox; cross-check against npm's metadata before committing".
- **Registry blocks during install (npm.com outage)**: `npm ci` fails. Operator can't install during the outage. Acceptable — the current behavior on outage is "indeterminate dep tree resolution" which is worse.
- **Operator forgets to regenerate the lockfile after bumping OC_VER**: `npm ci` fails because package.json (from the new tarball) doesn't match the stale shrinkwrap. Audit-day surfaces this — the version mismatch shows up in the `mcp-server-drift`-equivalent for npm packages (a follow-up to add).

## 5. Acceptance criteria

- [ ] **AC1.** `setup/walter-host/services/openclaw/npm-shrinkwrap.json` exists in the repo + matches the SHA512-pinned `openclaw@2026.5.7` resolution.
- [ ] **AC2.** Both compose files (`compose.yml` + standalone) use a deterministic install flow that honors the shrinkwrap + preserves `/workspace/.npm-global/bin/openclaw`. Exact flow chosen during implementation from §4.2 Candidates A/B (Candidate C is REJECTED — install-then-compare lets unverified deps land on disk first, violating G2); whichever lands, the install must:
    - hard-fail when shrinkwrap and pinned `OC_VER` disagree **before any dep tarball is written to /workspace**,
    - never run lifecycle scripts (`--ignore-scripts`),
    - produce the same dep tree on a re-run.
- [ ] **AC3.** Root compose.yml mounts the shrinkwrap as `./setup/walter-host/services/openclaw/npm-shrinkwrap.json` (repo-root-relative). Standalone compose mounts it as `./npm-shrinkwrap.json` (same-dir). Both resolve to the same in-container path.
- [ ] **AC4.** A bats test verifies BOTH compose files reference the shrinkwrap with the correct host-side path (one assertion per file, distinct paths).
- [ ] **AC5.** A bats test verifies `OC_VER` in compose matches the `version` recorded in the shrinkwrap's `openclaw` ENTRY (NOT the root of the lockfile — Codex R2 catch). The exact JSONPath depends on the chosen candidate:
    - Candidate A (wrapper-package): `.packages."node_modules/openclaw".version` (the wrapper root is `openclaw-wrapper@1.0.0`, irrelevant to OC_VER).
    - Candidate B (extract-in-place): `.name == "openclaw"` AND `.version == OC_VER` (the lockfile root IS openclaw).
    Implementation PR picks the assertion based on chosen candidate.
- [ ] **AC6.** `skills/quarterly-upgrade-cadence/SKILL.md` (the actual location — Copilot R1 #140 catch; the file is under skills/, not docs/operational/) documents the regenerate-shrinkwrap step with `--ignore-scripts` AND `--registry=https://registry.npmjs.org/` mandatory in the operator's sandbox-generation command (#132 Codex R1 catch — naive `npm install` runs upstream lifecycle code on the operator's machine; #140 Copilot R1 catch — without an explicit registry, the generated lockfile records URLs from whatever registry the operator's local npmrc points at).
- [ ] **AC7.** v0.4.4's R3 comment block in both compose files is updated to drop the "residual gap" note + replace with the new closed-state.
- [ ] **AC8.** Smoke test on a fresh `node:24-slim` container: `OC_VER=2026.5.7 OC_INTEGRITY=... docker compose up openclaw` produces an identical `/workspace/.npm-global` tree as a second run (same lockfile = same artifacts).
- [ ] **AC9.** ADR 0017 documents the design choice + rejected alternatives (ship-deps-in-tarball / npm-cache-store offline mode / IPFS pinning / `package-lock.json` instead of shrinkwrap).
- [ ] **AC10.** Prototype evidence in the implementation PR description: which of §4.2 Candidates A/B/C was chosen + why, with the working install-path snippet captured from a real `node:24-slim` run.

## 6. Out-of-scope follow-ups

- **F1.** Same shrinkwrap pattern applied to other runtime npm consumers (e.g. claude-code-router, mcp-* npm-published servers). Spec only sets the precedent here.
- **F2.** Audit-time drift detection — extend `audit.sh` to diff the current shrinkwrap against what `npm ci --dry-run` would resolve today (catches dep yanks).
- **F3.** Automated quarterly regeneration via a workflow + PR-bot (operator just reviews + merges the PR).

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Operator forgets to regenerate shrinkwrap on OC_VER bump | High | Medium | `npm ci` fails loud; bats test (AC5) catches it in CI before merge |
| Lockfile-shipping operator step gets skipped (out-of-band install bypasses compose) | Low | Medium | Document in tier-3.md install prompt; no compose-bypass install path is supported |
| Lockfile generation itself introduces a backdoor (compromised dev machine) | Low | High | Same threat model as today's `OC_INTEGRITY` generation; operator regenerates in a clean sandbox + cross-checks |
| npm registry deprecates / changes integrity format | Low | Medium | npm-shrinkwrap.json format is stable (npm 7+); upgrade path is well-documented |

## 8. Open questions for operator

- **Q1.** `npm-shrinkwrap.json` vs `package-lock.json`? Both have the same content; shrinkwrap is the only one that survives `npm publish` (which doesn't apply here — we're not publishing). package-lock is the npm-default name. Recommendation: `npm-shrinkwrap.json` for explicit "this is a deterministic-install artifact, not a dev-time convenience" signaling.
- **Q2.** Mount the shrinkwrap into the container vs bake it into a custom image? Mount is simpler + matches the current compose-only deploy story. Bake is faster install (no extract step) but requires a CI step to publish the image. Recommendation: **mount** for v1; revisit if install latency becomes a problem.
- **Q3.** Apply this same pattern proactively to litellm + other npm-installing services in this PR, or hold to scope and do them as F1 follow-ups? Recommendation: **hold to scope**, file F1 with the same design template ready to clone.

## 9. References

- PR #127 — v0.4.4 mitigation (top-level SHA512 + `--ignore-scripts` + `--registry`)
- Codex R2 review on PR #127 (2026-05-21) — caught this gap
- Issue #132 — this work's tracking issue
- ADR 0012 — OSS security hardening primitives (parent design)
- `docs/specs/openclaw.md` — base OpenClaw deployment spec
- `skills/quarterly-upgrade-cadence` — operator workflow gets an OpenClaw-specific entry per AC6
