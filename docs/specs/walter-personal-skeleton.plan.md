# Implementation Plan: walter-personal-skeleton

## Overview

Four sequential tasks. Each task has a RED phase (failing bats assertion) before
any production file is written, per the TDD discipline in AGENTS.md.

Estimated total: ~15–20 minutes of implementation time.

---

## Task 1: Scaffold skeleton directory [AC-1, AC-6] (~5 min)

**Files touched**:
- `contexts/_examples/walter-personal-skeleton/README.md` (new)
- `contexts/_examples/walter-personal-skeleton/INSTALL.md` (new)
- `contexts/_examples/walter-personal-skeleton/.gitignore` (new)
- `contexts/_examples/walter-personal-skeleton/personal.env.template` (new)
- `contexts/_examples/walter-personal-skeleton/contexts/work/AGENTS.md.template` (new)
- `contexts/_examples/walter-personal-skeleton/contexts/projects-personal/AGENTS.md.template` (new)
- `contexts/_examples/walter-personal-skeleton/contexts/personal/AGENTS.md.template` (new)

**RED**: Write `tests/oss/walter-personal-skeleton.bats` with just the AC-1 structure
assertions (file existence checks). Run `bats tests/oss/walter-personal-skeleton.bats`
— all assertions fail because no skeleton files exist yet.

**GREEN**: Create the seven skeleton files with the exact content below.

### `README.md`

```markdown
# walter-personal

This directory is the skeleton for your private `walter-personal` git repository.
It contains template configuration files for [Walter-OS](https://github.com/xipher-labs/walter-os).

## What is walter-personal?

Walter-OS is a public framework. Your personal configuration — your domain, your
company context, your life-admin preferences — lives here, in a *private* repo that
you own and control.

## When to use this pattern

- You use Walter-OS on more than one machine and want config changes to sync via git
  (rather than Syncthing alone).
- You want revision history and rollback for your personal context files.
- You want to back up your overlay to a private remote (GitHub, Forgejo, Gitea, etc.).

If you only ever use one machine and don't need history, the plain overlay at
`~/.config/walter-os/overlay/` (without git) is sufficient.

## Security caveats

**Never commit raw secrets to this repo, even if it is private.**

This skeleton's `.gitignore` excludes `.env*` (except `.env.template` and
`.env.example`) and `secrets/`. Use these patterns to keep credentials out:

- Store API keys in Infisical (self-hosted) and reference them by project ID.
- Store passwords in Vaultwarden and reference them by secret path.
- If you must commit a value, store only the Infisical/Vaultwarden reference path,
  not the secret itself.

See `docs/operational/universal-vs-personal-config.md` in the Walter-OS repo for
full secrets guidance.

## Backup considerations

Even with a private remote, consider encrypting the repo at rest if it contains
sensitive context files (your health notes, financial context, etc.). Options:

- `git-crypt` — encrypt specific files transparently.
- `age` — encrypt entire files before committing.
- Full-disk encryption on the machine hosting the bare clone (recommended baseline).

## Structure

```
walter-personal/
├── README.md                          # this file
├── INSTALL.md                         # 6-step onboarding
├── .gitignore                         # pre-configured for secrets hygiene
├── personal.env.template              # → rename to personal.env and fill in values
└── contexts/
    ├── work/
    │   └── AGENTS.md.template         # → rename to AGENTS.md and fill in
    ├── projects-personal/
    │   └── AGENTS.md.template         # → rename to AGENTS.md and fill in
    └── personal/
        └── AGENTS.md.template         # → rename to AGENTS.md and fill in
```
```

### `INSTALL.md`

```markdown
# walter-personal — Onboarding (6 steps)

## Step 1: Copy the skeleton

From your Walter-OS repo:

```bash
cp -r contexts/_examples/walter-personal-skeleton ~/walter-personal
cd ~/walter-personal
```

Or use the helper flag (does the same thing, puts it directly in the overlay):

```bash
./setup/personal-overlay-init.sh --from-skeleton
```

If using `--from-skeleton`, the overlay is immediately live at
`~/.config/walter-os/overlay/`. Skip to Step 3.

## Step 2: Initialize a git repo

```bash
cd ~/walter-personal    # or wherever you copied the skeleton
git init
git add .
git commit -m "chore: initial walter-personal skeleton"
```

## Step 3: Fill in your values

Rename and edit the template files:

```bash
mv personal.env.template personal.env
# Edit personal.env — fill in WALTER_DOMAIN, GITHUB_USER, etc.

mv contexts/work/AGENTS.md.template contexts/work/AGENTS.md
# Edit to describe your company stack and workflow rules.

mv contexts/projects-personal/AGENTS.md.template contexts/projects-personal/AGENTS.md
# Edit to list your active personal projects.

mv contexts/personal/AGENTS.md.template contexts/personal/AGENTS.md
# Edit to add your locale, tax context, health notes policy.
```

Commit your changes:

```bash
git add .
git commit -m "chore: fill in personal values"
```

## Step 4: Push to a private remote

```bash
# GitHub (using gh CLI):
gh repo create YOUR_GITHUB_USER/walter-personal --private --source=. --push

# Forgejo / Gitea (self-hosted):
git remote add origin git@your-forgejo.example.com:YOUR_USER/walter-personal.git
git push -u origin main
```

## Step 5: Wire the overlay

If you used `--from-skeleton`, the overlay is already at `~/.config/walter-os/overlay/`.
If you initialized manually, symlink or clone it:

```bash
# Option A: clone directly as the overlay
./setup/personal-overlay-init.sh --git-clone git@github.com:YOUR_USER/walter-personal.git

# Option B: symlink (if the repo lives elsewhere)
ln -s ~/walter-personal ~/.config/walter-os/overlay
```

## Step 6: Clone on a second machine

On the new machine, after cloning Walter-OS:

```bash
./setup/personal-overlay-init.sh --git-clone git@github.com:YOUR_USER/walter-personal.git
```

This clones your private repo directly to `~/.config/walter-os/overlay/`.
The overlay is immediately active — no further steps required.

---

## Keeping in sync

On each machine, pull changes before starting a session:

```bash
cd ~/.config/walter-os/overlay && git pull
```

After editing context files, commit and push:

```bash
cd ~/.config/walter-os/overlay
git add -p
git commit -m "chore: update work context — new project"
git push
```

For fully automatic sync without git discipline, see the Syncthing alternative
in `docs/operational/multi-device-sync.md`.
```

### `.gitignore`

```gitignore
# Secrets — never commit raw credentials
.env
.env.local
.env.production
.env.staging
secrets/
*.key
*.pem
*.p12
*.pfx
id_rsa
id_ed25519

# Allow template/example files explicitly
!.env.template
!.env.example
!personal.env.template

# macOS
.DS_Store

# Editor noise
.idea/
.vscode/
*.swp
*~

# Walter-OS overlay cache (machine-local, not shareable)
cache/
```

### `personal.env.template`

```bash
# personal.env — your operator-specific Walter-OS configuration.
# Copy this file to personal.env and fill in real values.
# NEVER commit personal.env to git — it is in .gitignore.
#
# Precedence (most-specific wins):
#   1. Env vars exported in your shell (immediate override)
#   2. ${PROJECT_ROOT}/.env.local (in-repo, gitignored, this checkout only)
#   3. ~/.config/walter-os/overlay/personal.env (this file, shared across checkouts)
#   4. ${PROJECT_ROOT}/.env.example defaults (generic placeholders)

# === DOMAIN ===
# TODO: Replace with your base domain (used in all *.${WALTER_DOMAIN} URLs)
WALTER_DOMAIN=TODO.example.com

# === GITHUB IDENTITY ===
# TODO: Replace with your GitHub username
GITHUB_USER=TODO-your-github-username
# TODO: Replace if you fork walter-os under a different name
WALTER_OS_UPDATE_REPO=xipher-labs/walter-os
# TODO: Replace with your fork's public URL (used in Control Tower badge)
NEXT_PUBLIC_WALTER_REPO_URL=https://github.com/TODO-your-github-username/walter-os

# === COPYRIGHT / ATTRIBUTION ===
# TODO: Replace with your legal name or org name
WALTER_COPYRIGHT_HOLDER="TODO Your Name"
WALTER_COPYRIGHT_YEAR=2026

# === SERVICE IDENTITY DEFAULTS ===
# TODO: Replace with your Matrix/Synapse admin username
WALTER_MATRIX_USER=TODO-admin
# TODO: Replace with your email (used for ACME/Let's Encrypt)
WALTER_OPERATOR_EMAIL=TODO@example.com

# === SECRETS (do NOT store raw values here) ===
# Reference secrets by their Infisical path or Vaultwarden item name.
# Example (Infisical):
#   ANTHROPIC_API_KEY="infisical://walter-personal/ANTHROPIC_API_KEY"
# Example (Vaultwarden):
#   ANTHROPIC_API_KEY="bw://item/anthropic-api-key/password"
#
# ANTHROPIC_API_KEY=TODO
# FORGEJO_TOKEN=TODO
# PLANE_API_KEY=TODO
```

### `contexts/work/AGENTS.md.template`

```markdown
# AGENTS.md — Work Context

<!-- TODO: Fill in your company and stack details.
     This file is loaded by Walter-OS when your cwd matches your work directory.
     Delete these comment blocks as you fill in real values. -->

## Company context

<!-- TODO: Describe your company, product, and customer base. -->
**[TODO: Your Company]** — [TODO: one-line description of what the company does
and who its customers are].

## Stack

<!-- TODO: Fill in your actual tech stack. -->
- Language/runtime: TODO (e.g. TypeScript, Rust, Go)
- Frontend: TODO (e.g. Next.js, React, Vue)
- Infra: TODO (e.g. AWS, Hetzner, bare-metal)
- CI: TODO (e.g. GitHub Actions, GitLab CI)
- Observability: TODO (e.g. Grafana + Prometheus, Datadog)

## Workflow rules

### PR creation

<!-- TODO: Decide if agents may open PRs automatically or only draft them. -->
Agents may prepare branches and draft PR descriptions. The operator opens every
PR manually.

### Branch flow

<!-- TODO: Note any company-specific branch naming or required sign-offs. -->
Same global `dev → staging → main` rule applies.

### Issue tracker integration

<!-- TODO: Set your tracker (Linear / Jira / Plane / GitHub Issues) and ticket format. -->
Issue tracker: TODO
Ticket reference format: `Refs: [TODO-NNN]`

## Security posture

- Changes touching auth, key handling, or network-exposed surfaces auto-invoke
  the `security-auditor` subagent.
- Dependency audit runs on every PR.
- Secrets never appear in logs.

## Approvals required

<!-- TODO: Add any company-specific approval requirements. -->
These actions need explicit operator confirmation:
- Pushing to any branch other than the current feature branch.
- Modifying CI configuration.
- Adding a new production dependency.
- Posting anything publicly.

## Skill loading (this context)

<!-- TODO: Add domain-specific skills for your stack. -->
Auto-loaded in addition to global skills:
- `web-security-baseline`
- `frontend-quality`
- `data-migration-safety`
```

### `contexts/projects-personal/AGENTS.md.template`

```markdown
# AGENTS.md — Projects Context

<!-- TODO: Fill in your active personal software projects.
     This file is loaded by Walter-OS when your cwd matches your personal
     projects directory. Delete comment blocks as you fill in real values. -->

## Mode

Higher autonomy than work context. Auto-PR enabled after review iterations
converge. Wrong-but-fast is acceptable on branches that are not staging or main.

Hard limits stay the same: branch flow, security gates, never auto-merge.

## Active projects

<!-- TODO: Add your active personal projects below. For each project, describe:
     - What it is
     - Its tech stack
     - Any regulatory context relevant to your jurisdiction
     - Any special agent rules (e.g. "never auto-deploy this one") -->

### TODO: Project 1

[TODO: one-line description]

Stack: TODO

### TODO: Project 2

[TODO: one-line description]

Stack: TODO

## Issue tracker integration

Issue tracker: TODO
Spec location: `docs/specs/<slug>.md` (committed to each project repo)

## Toolchain shortcuts

<!-- TODO: Override if your defaults differ from Walter-OS generic templates. -->
- Landing pages: Astro (static) or Next.js App Router (dynamic)
- Database: Supabase (managed Postgres + auth + realtime + storage)
- Deploy: Vercel (frontend), Fly.io or Railway (stateful services)
- Analytics: Plausible (self-hosted)
- Auth: Supabase Auth or Clerk

## Skill loading (this context)

Auto-loaded in addition to global skills:
- `hackathon-spinup`
- `brand-creation`
- `regulatory-research-international`
- `landing-page-fast`
- `frontend-quality`
- `data-migration-safety`
- `web-security-baseline`
```

### `contexts/personal/AGENTS.md.template`

```markdown
# AGENTS.md — Personal Life Context

<!-- TODO: Fill in your personal life context.
     This is for non-dev personal life: finances, health, journaling, notes.
     For personal software projects, see contexts/projects-personal/AGENTS.md.
     Delete comment blocks as you fill in real values. -->

## Mode

Lower-stakes than dev contexts. The agent assists, does not enforce. Privacy-first:
nothing written here is sent to external services without explicit confirmation.

## Locale and jurisdiction

<!-- TODO: Set your locale for tax, legal, and date-format context. -->
Country/region: TODO (e.g. Argentina, United States — California, Germany)
Tax authority: TODO (e.g. AFIP, IRS, Finanzamt)
Key tax dates: TODO (e.g. annual filing: June 30, quarterly VAT: last day of Q)
Currency: TODO (e.g. ARS / USD, EUR)

## Personal finance

<!-- TODO: Describe what you track and how. -->
Tracking: expenses, income, investments
Tools: TODO (e.g. Google Sheets, Actual Budget, Obsidian)

The agent can help with calculations and reminders but does NOT execute financial
operations. Transfers and trades are yours to initiate.

## Health

Personal medical notes, reminders, appointment calendar.
PHI rule: strict medical-data-compliance applies even for your own data.
Local LLM only for analysis.

## Journaling / reflection

<!-- TODO: Describe your journaling practice. -->
Format: TODO (e.g. daily journal in Obsidian, weekly review template)
Privacy: summaries done locally only.

## Learning

<!-- TODO: List active learning topics or systems. -->
Current focus: TODO
Tools: TODO (e.g. Obsidian for notes, Anki for spaced repetition)

## Household / daily life

<!-- TODO: List household context the agent should know. -->
Shopping: TODO
Recurring tasks: TODO

## Language preference

<!-- TODO: Set your preferred language for personal-context responses. -->
Default response language: TODO (e.g. Spanish for casual, English for technical)

## Skill loading (this context)

Auto-loaded in addition to global skills:
- `medical-data-compliance` (always, even for your own data)
- `regulatory-research-international`
```

**Verify**: Run `bats tests/oss/walter-personal-skeleton.bats` — AC-1 file
existence assertions pass. Then run:

```bash
grep -rn -E '(xipherlabs|operator-handle|operator-email|private-domain)' \
  contexts/_examples/walter-personal-skeleton/
```

Must return empty (AC-6 check). Also run `bats tests/oss/depersonalization.bats`
— must still be 36/36 green (skeleton is under `contexts/_examples/` which the
depersonalization suite already exempts).

---

## Task 2: Extend personal-overlay-init.sh with new flags [AC-2, AC-3] (~5 min)

**Files touched**:
- `setup/personal-overlay-init.sh` (modify)

**RED**: Add to `tests/oss/walter-personal-skeleton.bats` the AC-2/AC-3 assertions:
- `--help` mentions `--from-skeleton`
- `--help` mentions `--git-clone`
- `--dry-run --from-skeleton` creates no files and prints a copy plan
- `--git-clone URL --dry-run` prints clone command, creates no files

Run bats — these assertions fail because the flags don't exist yet.

**GREEN**: Modify `setup/personal-overlay-init.sh` as follows.

1. Update the header comment block (lines 1–16) to add the two new usage lines
   and flag descriptions. The `--help` handler uses `grep '^#' "$0" | head -20`
   so the comment must appear in the first 20 comment lines. Extend the limit to
   `head -30` and add the new usage text.

2. Extend the argument parsing loop (lines 25–34) to handle `--from-skeleton`
   and `--git-clone`:

```bash
DRY_RUN=0
FROM_SKELETON=0
GIT_CLONE_URL=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --from-skeleton) FROM_SKELETON=1 ;;
    --git-clone)
      # next positional — handled below with shift-style index tracking
      # (since we're iterating, capture the next arg on next iteration)
      EXPECT_GIT_URL=1
      ;;
    *)
      if [[ "${EXPECT_GIT_URL:-0}" -eq 1 ]]; then
        GIT_CLONE_URL="$arg"
        EXPECT_GIT_URL=0
      elif [[ "$arg" == -h || "$arg" == --help ]]; then
        grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
        exit 0
      else
        echo "Unknown arg: $arg" >&2; exit 2
      fi
      ;;
  esac
done
```

Note: the existing arg loop uses positional iteration without index tracking.
Switch the loop to use `"$@"` with a flag variable for the URL argument, or
rewrite using a `while [[ $# -gt 0 ]]; do ... shift; done` pattern (cleaner).
The implementer should use the `while/shift` pattern to avoid the
`EXPECT_GIT_URL` hack:

```bash
DRY_RUN=0
FROM_SKELETON=0
GIT_CLONE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=1 ; shift ;;
    --from-skeleton) FROM_SKELETON=1 ; shift ;;
    --git-clone)
      if [[ -z "${2:-}" ]]; then
        echo "--git-clone requires a URL argument" >&2; exit 2
      fi
      GIT_CLONE_URL="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
```

3. After the existing overlay-dir creation block (around line 96), add mutual
   exclusion guard:

```bash
if [[ $FROM_SKELETON -eq 1 && -n "$GIT_CLONE_URL" ]]; then
  echo "Error: --from-skeleton and --git-clone are mutually exclusive." >&2
  exit 2
fi
```

4. After the guard, add the `--git-clone` path (before the existing scaffold block):

```bash
# ---- --git-clone path ----

if [[ -n "$GIT_CLONE_URL" ]]; then
  if [[ -d "$OVERLAY_DIR" ]]; then
    say "Error: overlay directory already exists at $OVERLAY_DIR"
    say "Delete or back it up first, then re-run with --git-clone."
    exit 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would run: git clone $GIT_CLONE_URL $OVERLAY_DIR"
    say "DRY RUN COMPLETE."
    exit 0
  fi
  git clone "$GIT_CLONE_URL" "$OVERLAY_DIR"
  # Validate expected structure
  if [[ ! -f "$OVERLAY_DIR/personal.env" && ! -f "$OVERLAY_DIR/personal.env.template" ]]; then
    say "Warning: cloned repo does not contain personal.env or personal.env.template."
    say "Ensure this is a valid walter-personal repo before proceeding."
  else
    ok "Cloned walter-personal repo to $OVERLAY_DIR"
  fi
  say "Overlay active. Run 'walter doctor' to verify."
  exit 0
fi
```

5. Add the `--from-skeleton` path (before the existing scaffold block, after
   the git-clone block):

```bash
# ---- --from-skeleton path ----

if [[ $FROM_SKELETON -eq 1 ]]; then
  local skeleton_dir="$REPO_ROOT/contexts/_examples/walter-personal-skeleton"
  if [[ ! -d "$skeleton_dir" ]]; then
    echo "Error: skeleton not found at $skeleton_dir" >&2; exit 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would copy $skeleton_dir/ → $OVERLAY_DIR/"
    for f in $(find "$skeleton_dir" -type f | sort); do
      rel="${f#$skeleton_dir/}"
      dry "  $rel"
    done
    say "DRY RUN COMPLETE."
    exit 0
  fi
  mkdir -p "$OVERLAY_DIR"
  cp -r "$skeleton_dir/." "$OVERLAY_DIR/"
  ok "Copied skeleton to $OVERLAY_DIR"
  say ""
  say "Next: rename *.template files to their final names and fill in TODO values."
  say "Then: cd $OVERLAY_DIR && git init && git add . && git commit -m 'initial'"
  exit 0
fi
```

Note: the `local` keyword is invalid outside a function in bash. The implementer
must either remove `local` (use plain assignment) or wrap this block in a helper
function. Use plain assignment (no `local`) since the new code runs at the top
level of the script.

6. Update the comment block at the top of the script to document both new flags.
   Ensure the updated comment fits within the first 30 lines that `--help` prints.

**Verify**:
- `bats tests/oss/walter-personal-skeleton.bats` — AC-2/AC-3 assertions pass
- `bats tests/oss/depersonalization.bats` — still 36/36 green
- `shellcheck setup/personal-overlay-init.sh` — no errors
- Manual: `./setup/personal-overlay-init.sh --from-skeleton --dry-run` prints
  copy plan, creates no files
- Manual: `./setup/personal-overlay-init.sh --git-clone https://example.com/x.git --dry-run`
  prints clone command, creates no files

---

## Task 3: Extend universal-vs-personal-config.md [AC-4] (~3 min)

**Files touched**:
- `docs/operational/universal-vs-personal-config.md` (modify — append new section)

**RED**: Add to `tests/oss/walter-personal-skeleton.bats` a single assertion:

```bash
@test "AC-4: universal-vs-personal-config.md contains 'Operator-private git repo' section" {
  grep -q 'Operator-private git repo' \
    "$REPO_ROOT/docs/operational/universal-vs-personal-config.md"
}
```

Run bats — this assertion fails.

**GREEN**: Append the following section to the end of
`docs/operational/universal-vs-personal-config.md`:

```markdown
---

## Operator-private git repo (advanced)

This pattern is for operators who want:
- Revision history and rollback for their personal context files.
- Config changes synchronized across machines via `git pull` (rather than
  Syncthing alone).
- A private remote backup (GitHub, Forgejo, Gitea) for the overlay.

If you only use one machine and do not need history, the plain overlay without
git is sufficient. Both patterns use the same `~/.config/walter-os/overlay/`
path.

### When to use this pattern

Use it if any of these apply:
- You regularly work on 2+ machines.
- You want `git log` on your context changes.
- You want disaster recovery via a private remote clone.

If you already use Syncthing for the overlay, you can keep using it. The two
patterns are compatible (a Syncthing-managed directory can also be a git repo).

### Initialize: skeleton → private repo

```bash
# 1. Scaffold the overlay from the skeleton template
./setup/personal-overlay-init.sh --from-skeleton

# 2. Initialize git in the overlay
cd ~/.config/walter-os/overlay
git init
git add .
git commit -m "chore: initial walter-personal skeleton"

# 3. Fill in TODO values
mv personal.env.template personal.env
# Edit personal.env, contexts/*/AGENTS.md.template files, rename them.
git add -p && git commit -m "chore: fill in personal values"

# 4. Push to a private remote
gh repo create YOUR_USER/walter-personal --private --source=. --push
# Or for self-hosted Forgejo:
git remote add origin git@your-forgejo.example.com:YOUR_USER/walter-personal.git
git push -u origin main
```

The overlay is now a versioned private repo. Run `git pull` at the start of
each session to pick up changes from other machines.

### Clone on a second machine

After cloning Walter-OS on the new machine:

```bash
./setup/personal-overlay-init.sh \
  --git-clone git@github.com:YOUR_USER/walter-personal.git
```

This clones your private repo directly to `~/.config/walter-os/overlay/`.
The overlay is immediately active — no further steps required.

If the overlay directory already exists, the script will abort with an
instructions message. Delete or back up the existing overlay first.

### Secrets hygiene

**Never commit raw secrets** to this repo, even if it is private.

The skeleton `.gitignore` already excludes `.env`, `.env.local`, and
`secrets/`. Follow these rules:

- Store API keys and tokens in Infisical (self-hosted on Walter-VM) and
  reference them by project ID in your scripts.
- Store passwords in Vaultwarden and reference them by secret path.
- `personal.env` is gitignored — fill in real values there but never commit
  the file itself. Commit only the `personal.env.template` with TODO
  placeholders.
- If you absolutely must track a credential reference (not the credential
  itself), use a Vaultwarden or Infisical URI:
  `ANTHROPIC_API_KEY=bw://item/anthropic-api-key/password`

### Syncthing alternative

If you prefer file-level sync without git discipline, see the Syncthing
pattern in `docs/operational/multi-device-sync.md`. The two approaches are
compatible: a Syncthing-managed `overlay/` directory can simultaneously be
a git repo — Syncthing syncs the working tree files, git tracks history.
In this hybrid setup, add `.git/` to your Syncthing ignore patterns to
avoid syncing git internals across devices.
```

**Verify**:
- `bats tests/oss/walter-personal-skeleton.bats` — AC-4 assertion passes
- All prior assertions still pass

---

## Task 4: Complete bats suite and CI verification [AC-5, AC-6] (~4 min)

**Files touched**:
- `tests/oss/walter-personal-skeleton.bats` (finalize)

**Note**: The bats file is written incrementally across Tasks 1–3 (RED first
in each task). This task finalizes the file with any remaining assertions not
yet written, runs the full suite, and runs shellcheck.

**Final bats file** (`tests/oss/walter-personal-skeleton.bats`):

```bash
#!/usr/bin/env bats
# tests/oss/walter-personal-skeleton.bats
# Assertions for walter-personal-skeleton (PR #49, v0.2.0 OSS launch chain).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SKELETON="$REPO_ROOT/contexts/_examples/walter-personal-skeleton"
  SCRIPT="$REPO_ROOT/setup/personal-overlay-init.sh"
}

# ---------------------------------------------------------------------------
# AC-1: Skeleton directory contains all required files
# ---------------------------------------------------------------------------

@test "AC-1: skeleton directory exists" {
  [ -d "$SKELETON" ]
}

@test "AC-1: skeleton contains README.md" {
  [ -f "$SKELETON/README.md" ]
}

@test "AC-1: skeleton contains INSTALL.md" {
  [ -f "$SKELETON/INSTALL.md" ]
}

@test "AC-1: skeleton contains .gitignore" {
  [ -f "$SKELETON/.gitignore" ]
}

@test "AC-1: skeleton contains personal.env.template" {
  [ -f "$SKELETON/personal.env.template" ]
}

@test "AC-1: skeleton contains contexts/work/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/work/AGENTS.md.template" ]
}

@test "AC-1: skeleton contains contexts/projects-personal/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/projects-personal/AGENTS.md.template" ]
}

@test "AC-1: skeleton contains contexts/personal/AGENTS.md.template" {
  [ -f "$SKELETON/contexts/personal/AGENTS.md.template" ]
}

# ---------------------------------------------------------------------------
# AC-2/AC-3: personal-overlay-init.sh --help mentions new flags
# ---------------------------------------------------------------------------

@test "AC-2: --help output mentions --from-skeleton" {
  "$SCRIPT" --help | grep -q '\-\-from-skeleton'
}

@test "AC-3: --help output mentions --git-clone" {
  "$SCRIPT" --help | grep -q '\-\-git-clone'
}

# ---------------------------------------------------------------------------
# AC-2: --from-skeleton --dry-run creates no files
# ---------------------------------------------------------------------------

@test "AC-2: --from-skeleton --dry-run creates no files" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOME="$tmpdir" "$SCRIPT" --from-skeleton --dry-run >/dev/null 2>&1 || true
  local count
  count="$(find "$tmpdir" -mindepth 1 | wc -l | tr -d ' ')"
  rm -rf "$tmpdir"
  [ "$count" -eq 0 ]
}

@test "AC-2: --from-skeleton --dry-run prints copy plan" {
  local output
  output="$(HOME="$(mktemp -d)" "$SCRIPT" --from-skeleton --dry-run 2>&1 || true)"
  echo "$output" | grep -qi 'dry'
}

# ---------------------------------------------------------------------------
# AC-3: --git-clone --dry-run creates no files and prints clone command
# ---------------------------------------------------------------------------

@test "AC-3: --git-clone URL --dry-run creates no files" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOME="$tmpdir" "$SCRIPT" --git-clone https://example.com/foo.git --dry-run \
    >/dev/null 2>&1 || true
  local count
  count="$(find "$tmpdir" -mindepth 1 | wc -l | tr -d ' ')"
  rm -rf "$tmpdir"
  [ "$count" -eq 0 ]
}

@test "AC-3: --git-clone URL --dry-run mentions the clone command" {
  local output
  tmpdir="$(mktemp -d)"
  output="$(HOME="$tmpdir" "$SCRIPT" \
    --git-clone https://example.com/foo.git --dry-run 2>&1 || true)"
  rm -rf "$tmpdir"
  echo "$output" | grep -qi 'clone'
}

# ---------------------------------------------------------------------------
# AC-4: docs updated
# ---------------------------------------------------------------------------

@test "AC-4: universal-vs-personal-config.md contains 'Operator-private git repo' section" {
  grep -q 'Operator-private git repo' \
    "$REPO_ROOT/docs/operational/universal-vs-personal-config.md"
}

# ---------------------------------------------------------------------------
# AC-5: skeleton .gitignore excludes .env and secrets/
# ---------------------------------------------------------------------------

@test "AC-5: .gitignore excludes '.env'" {
  grep -q '^\\.env$' "$SKELETON/.gitignore"
}

@test "AC-5: .gitignore excludes 'secrets/'" {
  grep -q '^secrets/$' "$SKELETON/.gitignore"
}

# ---------------------------------------------------------------------------
# AC-6: No operator-specific values in skeleton files
# ---------------------------------------------------------------------------

@test "AC-6: skeleton contains no xipherlabs references" {
  local count
  count="$(grep -rl 'xipherlabs' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-6: skeleton contains no operator email placeholders" {
  local count
  count="$(grep -Erl 'operator@|operator\\.email' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "AC-6: skeleton contains no operator-handle references" {
  local count
  count="$(grep -rl 'operator-handle' "$SKELETON" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}
```

**Verify** (full CI run):

```bash
# Shellcheck
shellcheck setup/personal-overlay-init.sh

# New bats suite
bats tests/oss/walter-personal-skeleton.bats

# Existing depersonalization suite — must still be 36/36
bats tests/oss/depersonalization.bats

# Manual dry-run checks
./setup/personal-overlay-init.sh --from-skeleton --dry-run
./setup/personal-overlay-init.sh --git-clone https://example.com/foo.git --dry-run
./setup/personal-overlay-init.sh --help | grep -E 'from-skeleton|git-clone'

# Manual read of INSTALL.md for sense-check
# Open contexts/_examples/walter-personal-skeleton/INSTALL.md and verify
# the 6-step onboarding makes sense for a fresh operator.
```

All must pass before the PR is opened.

---

## Implementation notes

- The plan includes full file content for all skeleton files. The implementer
  copies them verbatim — no improvisation on placeholder text.
- The bats file is built RED-first across tasks. Do NOT write the entire bats
  file upfront and then write production code — that violates TDD discipline.
- `shellcheck` must pass with zero warnings. Pay special attention to the
  `while/shift` rewrite of the argument loop and the absence of `local`
  outside functions.
- The `--from-skeleton` and `--git-clone` flags are mutually exclusive. The
  guard must fire before any filesystem operations.
- The `--git-clone` abort on existing overlay must print a human-readable
  message, not just `exit 1` silently.
- Do not add any new test cases to `depersonalization.bats` — that suite has
  its own ownership. The skeleton-specific AC-6 assertions live exclusively in
  `walter-personal-skeleton.bats`.
