# Walter-Personal Skeleton

**Status**: Draft
**Owner**: operator
**Created**: 2026-05-11
**Linear/Plane**: —

## Problem

Walter-OS ships a clean OSS framework with no operator-specific configuration baked
in. The overlay pattern (`~/.config/walter-os/overlay/`) is the correct long-term
home for personal config: it is out-of-repo, never committed to the public fork,
and populated by `setup/personal-overlay-init.sh` from generic templates. This works
well on a single machine.

As soon as an operator needs more than one machine — or wants revision history,
rollback, or disaster recovery for their personal config — the filesystem-only overlay
becomes fragile. The Syncthing pattern (`docs/operational/multi-device-sync.md`)
addresses the sync problem, but it provides no structure, no history, and no on-ramp
for an operator who wants their personal config to be a proper git repo.

There is no canonical example showing what a `walter-personal` private git repo should
look like, what it must contain, how to initialize it from the Walter-OS templates,
and how to clone it onto a second machine. Operators who want this pattern have to
reverse-engineer it from three separate operational docs.

## Proposed solution

Ship a complete skeleton of the `walter-personal` private repo pattern directly inside
Walter-OS as `contexts/_examples/walter-personal-skeleton/`. The skeleton is a
template directory — not a runnable artifact — containing pre-filled placeholder files
with TODO comments, a `.gitignore` tuned for secrets hygiene, a README explaining
the pattern, and a step-by-step INSTALL.md.

`setup/personal-overlay-init.sh` gains two new flags: `--from-skeleton` (copy the
skeleton directory into the overlay instead of file-by-file template merging) and
`--git-clone <url>` (clone an existing private walter-personal repo directly as the
overlay). Both flags support `--dry-run`. The operational doc
`docs/operational/universal-vs-personal-config.md` grows a new "Operator-private git
repo (advanced)" section tying these together.

The pattern is opt-in. The existing no-flag flow is unchanged. Operators who do not
need multi-device git history continue using the overlay as before.

## Acceptance Criteria

- [AC-1] `contexts/_examples/walter-personal-skeleton/` exists and contains exactly
  eight files: `README.md`, `INSTALL.md`, `.gitignore`, `personal.env.template`,
  `contexts/work/AGENTS.md.template`, `contexts/projects-personal/AGENTS.md.template`,
  `contexts/personal/AGENTS.md.template`. All contain only TODO placeholders — no
  operator-specific values, no hostnames, no real emails.

- [AC-2] `setup/personal-overlay-init.sh --from-skeleton` copies
  `contexts/_examples/walter-personal-skeleton/` to `~/.config/walter-os/overlay/`.
  Existing no-flag behavior is unchanged. `--from-skeleton --dry-run` prints the
  planned copy operations without writing anything.

- [AC-3] `setup/personal-overlay-init.sh --git-clone <url>` runs
  `git clone <url> ~/.config/walter-os/overlay/`, validates the cloned repo contains
  `personal.env` or `personal.env.template`, and aborts with a clear message if the
  overlay directory already exists. `--git-clone <url> --dry-run` prints the planned
  clone command without executing it.

- [AC-4] `docs/operational/universal-vs-personal-config.md` contains a new section
  "Operator-private git repo (advanced)" covering: when to use the pattern, how to
  initialize with `--from-skeleton`, how to push to a private remote, how to clone
  on a second machine with `--git-clone`, credential hygiene guidance (avoid raw
  credential values; use Infisical/Vaultwarden refs), and a cross-link to `multi-device-sync.md` as the
  Syncthing alternative.

- [AC-5] `tests/oss/walter-personal-skeleton.bats` exists and passes:
  - Asserts all required files exist under `contexts/_examples/walter-personal-skeleton/`
  - Asserts `setup/personal-overlay-init.sh --help` output mentions `--from-skeleton`
    and `--git-clone`
  - Asserts `setup/personal-overlay-init.sh --dry-run --from-skeleton` prints plan,
    creates no files
  - Asserts the skeleton `.gitignore` excludes `.env` and `secrets/`

- [AC-6] `grep -rn -E '(xipherlabs|operator-handle|operator-email|private-domain|xipherlabs\.xyz)' contexts/_examples/walter-personal-skeleton/`
  returns empty. The skeleton contains zero operator-specific values. Verified by
  extending (or relying on) the existing depersonalization bats suite — the
  `contexts/_examples/` exclusion already exempts the skeleton from the general
  depersonalization assertions, but a dedicated skeleton-specific assertion must
  confirm zero personal references within the skeleton itself.

## Non-goals

- Creating any external `walter-personal` git repo (e.g., `operator-handle/walter-personal`).
  That is an operator action, not framework code.
- Migrating the operator's existing overlay to git. The operator does this manually
  using the INSTALL.md steps.
- Replacing or deprecating the Syncthing pattern. Both coexist; operators may use
  either or both.
- Scaffolding skill customizations, agent-approvals.yml, or Grafana/n8n exports in
  the skeleton. Only the base env + context AGENTS.md files are in scope.
- Auto-pushing to any remote. The skeleton and flags only scaffold local state.
- Any CI change to depersonalization.bats beyond ensuring the new skeleton directory
  is included in the `contexts/_examples/` exemption (already covered by the existing
  grep exclusion pattern).

## Open questions

- None. Scope is fully locked.

## References

- `contexts/_examples/personal.env.example` — existing env template the skeleton's
  `personal.env.template` mirrors
- `setup/personal-overlay-init.sh` — script being extended
- `docs/operational/universal-vs-personal-config.md` — doc being extended
- `docs/operational/multi-device-sync.md` — Syncthing alternative, cross-linked
- `tests/oss/depersonalization.bats` — existing bats suite; skeleton must not break it
- `docs/decisions/0011-depersonalization-strategy.md` — architectural context for the
  OSS/personal split
