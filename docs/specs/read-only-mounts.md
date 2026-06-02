# Invisible secret-bearing mounts during runs (OSS Trust A-5) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: OSS Trust roadmap Layer A item A-5 — umbrella spec is in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83) (post-merge in-tree path: `docs/specs/oss-trust-roadmap.md`).
**Target release**: v0.5.x (after A-3 sandbox lands; this is a refinement layer above A-3)
**Depends on**: A-3 process-isolation sandbox — [PR #92](https://github.com/Xipher-Labs/walter-os/pull/92) (post-merge in-tree path: `docs/specs/process-isolation-sandbox.md`) — provides the bind-mount mechanism. A-3 must merge before A-5 implements.

## Problem

A-3 sandbox profiles already restrict filesystem access. But the existing profiles allow READ on operator-overlay + walter-os-state directories because hooks need to read config. That's fine, but READ-during-allowed-window is enough to exfiltrate secrets via a successfully-allowed Bash call (e.g. operator approves `cat config.txt` for a legitimate reason; that allow happens to also approve `cat ~/.config/walter-os/state/session-<uuid>.key`).

A-5 adds a finer scope: ALL secret-bearing paths are bind-mounted as EMPTY placeholders during high-tier sandbox runs, so even a successful exfil attempt returns empty / missing-file.

**Terminology** (operator note — there are two distinct properties to nail down before reading the rest):

- **Invisibility**: on Linux/nsjail, the path looks not-secret-bearing. A read returns an empty dir (or empty placeholder file). The directory entry / path itself still exists, so tools that probe for parent-directory existence (e.g. `mkdir -p ~/.ssh/x`) succeed at the directory level. On macOS/sandbox-exec, Walter-OS cannot bind-mount user-space placeholders; the provider uses content-read denial as a fail-closed approximation instead of promising empty-directory semantics.
- **Read-only-ness**: a separate axis. A write attempt against a path either succeeds (mount is rw) or fails (mount is ro).

A-5 mandates INVISIBILITY for the configured secret paths. The placeholder mount is read-only by DEFAULT (so a stray write doesn't accidentally pollute the operator's view of the placeholder dir between sandbox runs), but the **read-only flag is an implementation hardening choice, not the security boundary**. The threat A-5 mitigates is "an allowed Bash call also reads `~/.ssh/id_rsa`" — read-only-ness alone wouldn't help that, only invisibility does.

The historical file name `read-only-mounts.md` precedes this clarification. Renaming the spec file is impractical mid-flight; future readers should read it as shorthand for the invisibility pattern, with read-only being a default but not the load-bearing property.

This is the difference between "you can read config" and "config is not at this path right now."

## Non-goals

- Hiding everything from every run. Most ops legitimately need access to most files; we only invisible-mount during HIGH-tier ops.
- Replacing operator's host disk encryption. We hide; we don't encrypt.
- Restricting Walter-OS's own infrastructure access. Walter-OS hooks run with the per-hook-default profile (A-3) which already restricts; A-5 is the additional layer for SKILL invocations.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Apply A-5 only to high-tier sandbox runs** (skill profile, when the corresponding tool call is classified `high` by `approval-gate.sh CATEGORY_MIN_TIER`). This layers additional configured invisible mounts on top of A-3; it does not weaken A-3 baseline masks that already hide sensitive homes such as `~/.ssh`, `~/.aws`, and `~/.gnupg` for all skill runs. | Low-tier ops legitimately need wider read than high-tier ops, but the A-3 baseline still blocks the highest-risk homes. |
| D-2 | **Invisible-mount strategy**: on Linux/nsjail, bind-mount an empty PLACEHOLDER over each protected path. The TYPE of the placeholder must match the type of the protected path: for DIRECTORY targets (`~/.ssh/`, `~/.aws/`, `~/.gnupg/`, etc.) use an empty directory; for FILE targets (`~/.docker/config.json`, `~/.config/walter-os/overlay/personal.env`) use an empty file. Linux `mount --bind` rejects dir→file mounts, so the implementation MUST stat the source and pick the matching empty placeholder. The path APPEARS to exist (existence checks pass) but is empty / has no real content. Mounted read-only by default so a write to the placeholder doesn't pollute the temp dir. macOS/sandbox-exec cannot provide bind placeholders; it emits `file-read-data` denies for protected paths. | Linux tools that test "does ~/.ssh exist?" → yes, dir exists, contents empty. Tools that test "is ~/.ssh/id_rsa readable?" → fail. Tools that test "does ~/.docker/config.json exist?" → yes, file exists, contents empty. macOS fails closed on content reads rather than returning empty placeholder content. |
| D-3 | **Protected paths (default)** — categorized by type so AC-1 can pick the right placeholder:<br>**Directories**: `~/.ssh/`, `~/.aws/`, `~/.gnupg/`, `~/.config/walter-os/state/`, `~/.config/op/` (1Password CLI), `~/.local/share/keyrings/`.<br>**Files**: `~/.config/walter-os/overlay/personal.env`, `~/.docker/config.json`.<br>Categorization is explicit at policy-load time. If a target's tagged type does not match the path on disk, the loader fails closed instead of guessing. | Common secret-bearing locations. Operator extends per overlay. |
| D-4 | **Operator extension via `~/.config/walter-os/overlay/sandbox-invisible-paths.txt`** — one path per line. Comments allowed. | Same shape as env-allowlist.txt + egress-allowlist.txt. |
| D-5 | **`walter-skill-default` profile (from A-3) gains an inheritance hook**: when invoking via `walter_sandbox_run walter-skill-default --high-tier`, the wrapper layers the invisible mounts on top. | Single shim entry point; A-5 is a flag, not a separate profile. |
| D-6 | **Bypass: same two-factor pattern**. `WALTER_SANDBOX_INVISIBLE_BYPASS=1` + `--allow-secret-read` in the command. Logged. | Operator can override for a one-off legitimate cross-secret task. |

## Acceptance criteria

### AC-1 — Invisible-mount mechanism
- [ ] `scripts/walter/lib/sandbox.sh` `walter_sandbox_run` gains a `--high-tier` flag that adds invisible mounts.
- [ ] **Per-target type**: D-3's protected-paths list contains BOTH directories (`~/.ssh/`, `~/.aws/`) AND single files (`~/.docker/config.json`, `~/.config/walter-os/overlay/personal.env`). The mechanism creates an EMPTY DIR placeholder for dir targets and an EMPTY FILE placeholder for file targets — bind-mounting a dir over a file (or vice-versa) errors out at sandbox start. **Each protected-paths entry is explicitly tagged**: D-3 lists entries as `~/.ssh/:dir`, `~/.docker/config.json:file`, etc. The loader requires the `:dir` / `:file` suffix; entries without it are rejected with a hard error at config-load time so an ambiguous "doesn't exist yet" target never silently defaults to a dir placeholder (which would then over-mount a real file if the operator later creates one). The loader also asserts type-vs-existence consistency: if an entry is tagged `:file` but the path resolves to a directory (or vice versa), config-load fails loudly.
- [ ] Linux (nsjail): each protected DIR adds `mount { dst: ... is_bind: true src: <empty-dir> }`; each protected FILE adds `mount { dst: ... is_bind: true src: <empty-file> }` (nsjail bind-mounts work on regular files too).
- [ ] macOS (sandbox-exec): each protected path adds a `(deny file-read-data (subpath "..."))` clause (NOT `file-read*`, which also blocks metadata — a `file-read*` deny would make the path itself return "operation not permitted" on `stat`, breaking parent-directory existence probes; `file-read-data` lets metadata probes succeed while blocking content reads. On macOS we cannot bind-mount in user space, so this is a fail-closed approximation rather than exact empty-placeholder semantics.)
- [ ] Empty placeholders (dirs and files) created on first use under `${WALTER_RUNTIME_DIR}/sandbox/invisible/`. **Dirs are mode `0700`** (operator-only rwx — needed so the dir itself can be listed). **Files are mode `0600`** (operator-only read/write, NO execute — `0700` on a regular file would set the execute bit, which is wrong for a config-file placeholder and could surface as a security finding from a code scanner). Re-used across sandbox starts; recreated if the operator deletes them.
- [ ] bats coverage in `tests/walter/sandbox-invisible-mounts.bats`:
  - With `--high-tier`: `ls ~/.ssh` → empty (no `id_rsa` visible)
  - Without `--high-tier`: no A-5 dynamic invisible mounts are added; the A-3 baseline may still mask sensitive homes such as `~/.ssh`
  - Operator overlay file `~/.config/walter-os/overlay/personal.env` → invisible at high-tier
  - Operator overlay file `~/.config/walter-os/overlay/work/AGENTS.md` (NOT in protected list) → visible

### AC-2 — Default protected-paths list + overlay extension
- [ ] `setup/sandbox-profiles/invisible-paths.default.txt` ships with the D-3 list.
- [ ] `scripts/walter/lib/sandbox.sh` reads BOTH the default file AND `~/.config/walter-os/overlay/sandbox-invisible-paths.txt` (if present); union becomes the active list.
- [ ] Operator can REMOVE a default-listed path via the prefix `!` (e.g. `!~/.docker/config.json` in the overlay disables that protection).
- [ ] bats coverage in `tests/walter/sandbox-invisible-paths-overlay.bats`:
  - Default list applied
  - Operator add: extra path becomes invisible
  - Operator `!`-remove: defaults path becomes visible

### AC-3 — High-tier classification integration
- [ ] `approval-gate.sh` classifies category → tier (existing). When `tier == high`, the eventual skill invocation is wrapped with `walter_sandbox_run walter-skill-default --high-tier`.
- [ ] When `tier != high`, no `--high-tier` flag; A-3 default policy applies without invisible mounts.
- [ ] bats coverage in `tests/hooks/sandbox-high-tier-invisible.bats`:
  - Bash `rm -rf /var/lib/postgres` → high-tier → invisible mounts active
  - Bash `cat README.md` → low-tier → invisible mounts NOT active

### AC-4 — Bypass + audit-chain integration
- [ ] Bypass: `WALTER_SANDBOX_INVISIBLE_BYPASS=1 walter ... --allow-secret-read` runs without invisible mounts; emits WARN; audit-chain row `decision_source: "operator-invisible-bypass"`.
- [ ] bats coverage in `tests/walter/sandbox-invisible-bypass.bats`.

### AC-5 — Daily-audit integration
- [ ] `daily-supply-chain-audit` adds `check_invisible_mount_paths()`:
  - Verifies the default protected paths exist (so the invisible-mount makes sense)
  - Operator overlay extensions parse cleanly
  - Counts how many "invisible-bypass" decisions happened in the last 24h; emits `info` if > 3 (operator may want to widen the protected list or harden a workflow)

### AC-6 — Docs + CHANGELOG
- [ ] `docs/operational/sandbox-invisible-mounts.md` (new):
  - Threat model (allowed-but-secret-reading exfil)
  - Default protected paths + rationale
  - How to extend / disable per-overlay
  - Bypass mechanics + when to use them
  - Performance note: bind-mount cost is negligible (microseconds per invocation)
- [ ] CHANGELOG entry under `[Unreleased] → Added (runtime sandboxing)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Approved Bash call legitimately reads config; same call also reads `~/.ssh/id_rsa` | At high-tier, `~/.ssh/` is bind-mounted to an empty dir; the secondary read fails. |
| Operator overlay personal.env contains LITELLM_MASTER_KEY etc.; high-tier op reads it | personal.env is in the default protected list; high-tier read fails. |
| Operator EXPLICITLY needs to read a secret for a one-off task | Two-factor bypass + audit-chain entry. |
| Attacker tries to whitelist their own path via overlay | Overlay file is operator-controlled. P1-09's `env-allowlist` parser is NOT the right integrity control here (P1-09 covers `${WALTER_CONFIG}/env` sourcing semantics, not arbitrary overlay-config integrity). The actual control is the daily audit's `check_skill_scripts()` extension which checksum-baselines every file under `~/.config/walter-os/overlay/` (same pattern as P1-07 external-hook integrity); a malicious overlay edit between sessions fires a `medium` finding on the next audit run. Operator-controllable filesystem is still out of scope for A-5 itself, but the audit-side baseline IS in scope and documented here. |
| Empty-dir mount confuses tools that need parent directory existence | The path itself remains present (so `mkdir -p ~/.ssh/x` succeeds at the dir level); only the CONTENTS are hidden. |

## Out of scope

- Encrypted overlay mounts. We bind-mount empty dirs; we don't encrypt.
- Per-tool selective invisibility (e.g. "make ~/.ssh visible to `git clone` but not to `cat`"). Future fine-grained scope.
- Auto-extending the protected list based on operator's installed CLIs (1Password, Bitwarden, etc.). Operator declares.

## Recommended PR ordering

1. AC-1 — invisible-mount mechanism in `sandbox.sh` + per-OS bind logic + bats
2. AC-2 — default + overlay path list + bats
3. AC-3 — high-tier classification integration + bats
4. AC-4 — bypass + audit-chain integration
5. AC-5 — daily-audit `check_invisible_mount_paths()`
6. AC-6 — docs + CHANGELOG (closing PR)

Each ≤200 LOC. 3-round review.

## Open questions for the operator

1. **`~/.docker/config.json` in the default list**: it contains registry credentials in many setups. Include (proposal) or skip (some tooling reads it)? Proposal: include; operator can remove via `!~/.docker/config.json` in overlay.
2. **macOS `sandbox-exec` deny-subpath syntax**: should we also block via `(deny file-write* (subpath ...))` even though A-5 is about reads? Proposal: read-only deny; write is already covered by A-3 default deny outside the workspace scope.
3. **`!`-prefix syntax for overlay removal**: clear enough? Or use a separate `invisible-paths-exclude.txt`? Proposal: `!`-prefix; same-file is simpler.

## Refs

- Parent: OSS Trust roadmap Layer A item A-5 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); post-merge in-tree: `docs/specs/oss-trust-roadmap.md`.
- Sibling: A-3 process-isolation sandbox — [PR #92](https://github.com/Xipher-Labs/walter-os/pull/92); post-merge in-tree: `docs/specs/process-isolation-sandbox.md`. This spec is a refinement layer on top.
- nsjail bind-mount docs: <https://github.com/google/nsjail/blob/master/MANUAL.md>
- macOS sandbox-exec deny-subpath: <https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf>
