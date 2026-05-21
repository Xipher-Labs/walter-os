# 0014. Walter-OS CLI lives at `${WALTER_OS_HOME}/bin/walter-os` with a symlink to `~/.local/bin/walter-os`

**Date**: 2026-05-21
**Status**: Proposed
**Spec**: `docs/specs/agent-install-tier-completion.md`
**Plan**: `docs/specs/agent-install-tier-completion.plan.md`

## Context

The four agent-install tier prompts merged via PR #103
(`setup/agent-install/tier-{1,2,3,4}.md`) assumed the `walter-os` CLI
lives at `~/.local/bin/walter-os`. Reality: `install.sh` keeps the
canonical CLI binary inside the cloned repo at
`${WALTER_OS_HOME}/bin/walter-os` and exports the directory onto `$PATH`
via the operator's shell init.

Copilot Round 2 review on PR #103 surfaced this drift as finding F2 (see
spec §1). An operator who follows the prompt as written hits a "file
not found at `~/.local/bin/walter-os`" error in the very first
verification step.

We have three reasonable ways to align prompts to reality:

1. **Move the canonical CLI to `~/.local/bin/`** — copy or move the
   binary out of the repo.
2. **Update the prompts to point to `${WALTER_OS_HOME}/bin/walter-os`** —
   document the status quo, no symlink.
3. **Keep the canonical at `${WALTER_OS_HOME}/bin/`, add a symlink to
   `~/.local/bin/`** — operators get the standard path, repo keeps
   single-source-of-truth semantics.

Each affects supply-chain hygiene, `git pull` semantics, and operator
discoverability differently. Picking one frames every future
documentation reference, hook path resolution, and `walter-os doctor`
check.

## Decision

**Adopt option 3: keep `${WALTER_OS_HOME}/bin/walter-os` as the canonical
location, and have `install.sh --upgrade` add a symlink at
`~/.local/bin/walter-os`.**

Concretely, `install.sh` gains one new line inside the existing STEP-0
block (no new flags):

```bash
ln -sf "${WALTER_OS_HOME}/bin/walter-os" "${HOME}/.local/bin/walter-os"
```

If `~/.local/bin/` is not on the operator's `$PATH`, the existing
`PATH` export to `${WALTER_OS_HOME}/bin/` keeps working as a fallback.
`install.sh --upgrade` prints a warning with the shell-rc edit
operators need to make `~/.local/bin/` discoverable.

## Why this approach

**`~/.local/bin/` is the XDG-standard user binary path.** Modern macOS
and Linux setups put it on `$PATH` by default (via `~/.zprofile` /
`~/.profile` / Homebrew shellenv etc.). Operators learning Walter-OS
do not have to learn a Walter-specific `PATH` convention to invoke the
CLI.

**Symlink preserves `git pull` semantics.** `walter-os` is a shell
script that evolves with the repo. A symlink means `git pull` in the
walter-os clone immediately upgrades the CLI everywhere `walter-os` is
invoked from. A copy would require re-running `install.sh --upgrade`
after every pull — easy to forget, source of "stale CLI" bugs.

**Repo stays single-source-of-truth.** The canonical file lives in
`bin/walter-os` inside the clone. Every consumer (the symlink in
`~/.local/bin/`, any operator-added secondary symlink, the
`${WALTER_OS_HOME}/bin/` `$PATH` export) ultimately resolves to one
file. No drift possible.

**Symmetric with the rest of `install.sh`.** `--upgrade` already
symlinks `~/.claude/CLAUDE.md → ${WALTER_OS_HOME}/AGENTS.md` and
`~/.codex/AGENTS.md → ${WALTER_OS_HOME}/AGENTS.md` (and several
others). The CLI symlink follows the established pattern — no new
mechanism, no new policy to remember.

## Alternatives considered and rejected

### A) Move the canonical CLI to `~/.local/bin/walter-os` (copy, not symlink)

`install.sh --upgrade` would `cp bin/walter-os ~/.local/bin/walter-os`.

**Rejected** because:

- Breaks `git pull` semantics. Operator pulls a CLI fix in the repo;
  the copied binary stays stale until they remember to re-run
  `install.sh --upgrade`. We've watched this exact pattern produce
  "wait, I fixed that" loops in other tools.
- Duplicates code on disk for no real benefit. The symlink + canonical
  pattern is what every long-lived Unix tool does (homebrew formulae,
  uv, rustup, etc.).
- Loses the "the repo is the source of truth" property that the rest
  of `install.sh` already establishes for `AGENTS.md`, skills,
  commands, hooks — all of which are symlinks.

### B) Keep canonical at `${WALTER_OS_HOME}/bin/walter-os`, document the path, no symlink

The prompts would be rewritten to use `${WALTER_OS_HOME}/bin/walter-os`
or `walter-os` (assuming the operator added the repo bin to `$PATH`
themselves).

**Rejected** because:

- Forces every operator to know about and edit `$PATH` themselves.
  That's exactly the friction the tier-1 install prompt is supposed
  to remove.
- `${WALTER_OS_HOME}` is not a standard env var. References to
  `${WALTER_OS_HOME}/bin/walter-os` in docs and scripts read as
  Walter-OS jargon, not as a path operators recognize. Reduces
  discoverability for anyone reading a script that invokes the CLI.
- A user who clones into a non-standard path (e.g. `/srv/tools/walter-os`)
  has to either re-export PATH on every machine or hand-edit every
  shell rc. The symlink hides this complexity.

### C) Publish `walter-os` via Homebrew tap / pipx / apt

The "real" Unix way to ship a CLI: package it, distribute it via a
package manager.

**Rejected** because:

- Walter-OS is v0.4-alpha with breaking changes every sprint. A package
  manager release cadence (and the maintenance burden of formulae /
  packages across distros) is not justified at this stage.
- The CLI is a single bash script; the value-add of packaging is
  marginal. Symlink-from-clone gives the operator effectively the same
  ergonomics with zero packaging overhead.
- Doesn't help operators who track Walter-OS by `git pull` (which is
  the recommended adoption mode per `README.md` mode 2).

Could be reconsidered post-1.0 if Walter-OS gets a stable release
cadence and a large enough audience to justify the maintenance.

### D) Use `~/bin/walter-os` instead of `~/.local/bin/walter-os`

Some older Unix conventions prefer `~/bin/` over `~/.local/bin/`.

**Rejected** because:

- XDG Base Directory Specification standardized on `~/.local/bin/` for
  user binaries; modern shells and distros have caught up.
- `~/bin/` is not on `$PATH` by default on macOS (Homebrew shellenv
  doesn't add it). `~/.local/bin/` IS on `$PATH` by default with
  Homebrew, uv, pipx, rustup — modern tooling consensus is `.local/bin`.
- Keeping the home directory uncluttered is a minor but real win.

### E) Symlink target chosen at install time by an operator flag

`install.sh --cli-path /custom/path` would let the operator pick.

**Rejected** because:

- Adds a configuration knob for a thing nobody wants to configure. The
  XDG-standard default is correct for ~99% of cases; the remaining
  ~1% can manually `ln -sf` wherever they want after the install.
- Introduces a per-operator override that the rest of Walter-OS would
  have to be aware of (every `walter-os doctor` check, every prompt
  reference). Cost-benefit is bad.

## Consequences

**Positive:**

- Prompts copy-paste-execute on a default macOS or Ubuntu shell setup.
- `git pull` in the walter-os clone immediately upgrades the CLI
  everywhere it's invoked from.
- Repository remains single-source-of-truth (no copied binaries, no
  drift).
- Symmetric with existing `install.sh` symlink behaviors for
  `CLAUDE.md`, `AGENTS.md`, skills, commands, hooks.
- One added line of bash in `install.sh`. Lowest-cost option to
  implement.

**Negative:**

- `~/.local/bin/` not on `$PATH` is still a possible operator
  environment. Mitigation: `install.sh --upgrade` detects this with
  `command -v walter-os` after the symlink and prints the shell-rc
  edit. The existing `${WALTER_OS_HOME}/bin/` `$PATH` export remains
  as a fallback so the install does not break.
- Operators with a previously-existing `~/.local/bin/walter-os` (e.g.
  from a manual install or another tool with the same name) would
  have it overwritten by `ln -sf`. Mitigation: `install.sh` checks
  for the file existing-and-not-a-symlink-to-our-binary and warns
  before overwriting.
- Documentation must consistently say "the `walter-os` command" rather
  than referencing the full path; reviewers should catch any
  `${WALTER_OS_HOME}/bin/walter-os` references in user-facing docs.

**Reversible:**

- Yes. Removing the symlink line from `install.sh` + reverting prompts
  to reference `${WALTER_OS_HOME}/bin/walter-os` is a one-commit
  revert. No data loss; operators with stale symlinks just have a
  dangling `~/.local/bin/walter-os` they can `rm`.

## Migration

1. `install.sh --upgrade` writes the new symlink. No-op if it already
   points where we want.
2. Operators who already had Walter-OS installed before this change
   are not affected by `--upgrade` — the symlink is added without
   removing the existing `PATH` export.
3. Documentation references update in the same PR (the four
   `setup/agent-install/tier-*.md` files).
4. `walter-os doctor` (existing, unchanged) reports whether `~/.local/bin/`
   is on `$PATH`; operators see a clear error if it's not.

## Open questions (non-blocking)

- Q1: Should `install.sh --upgrade` also add the shell-rc `PATH` line
  automatically if missing? *Proposed resolution*: no — modifying the
  operator's shell rc is too invasive for `--upgrade`. Print the line,
  let the operator copy it.
- Q2: Windows / WSL support? *Proposed resolution*: out of scope.
  Walter-OS targets macOS + Linux per AGENTS.md "Tooling preferences".

## References

- XDG Base Directory Specification: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
- `install.sh` STEP-0 block (~line 1583) — where the symlink lives
- `bin/walter-os` — the canonical binary
- ADR 0013 (solo-operator merge policy) — precedent for
  operator-configurable framework knobs with sane defaults
- Closed PR #103, Copilot review finding F2 — origin of this ADR
