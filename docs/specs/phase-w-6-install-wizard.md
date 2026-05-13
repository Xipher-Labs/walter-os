# W-6: Install.sh Interactive Wizard

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

The current `install.sh` is designed for an operator who already knows the full
Walter-OS mental model, has a running Walter-VM, and is performing an upgrade —
not a first install. It symlinks files, generates configs, and registers a launchd
job, but it does not:

- Ask what OS or architecture the operator is on (macOS vs Linux assumptions
  are scattered implicitly).
- Guide the operator through filling in the 50+ env vars in `.env.example`.
- Detect what services are already running.
- Create the Plane workspace and custom states required by the Council.
- Provision the Postgres databases (lessons, analytics, control-tower).
- Register n8n workflow templates.
- Initialize the Infisical workspace and Machine Identity.
- Run `walter doctor` and surface what is still broken.
- Tell the operator where to go next.

A new adopter running `./install.sh` on a fresh clone gets a set of symlinks but
no clear sense of whether anything is working. The gap between "install done" and
"first Council task executed" is currently a multi-hour manual process documented
across three separate operational runbooks.

## Proposed solution

Rewrite `install.sh` as a 9-step interactive wizard. Steps are modular (each step
can be skipped or retried independently). A `--dry-run` flag previews every action
without executing. A `--step <N>` flag re-runs a specific step (for recovery from
partial failures).

The wizard is still pure bash. No Python, no Node. The only new runtime dependency
is `curl` (already present on macOS/Linux) and `jq` (installed in step 1 if missing).

Two critical design decisions from W-5 and W-1 are prerequisites:
- W-5 must be complete before W-6 ships, because step 3 references overlay paths.
- W-1 must be complete before W-6 ships, because step 6 runs `docker compose up`.

The existing `install.sh` behavior (symlink skills/agents/commands, generate
`~/.codex/config.toml`) is preserved as "step 0" — it runs silently and is
still the right behavior for `--upgrade`.

## Acceptance Criteria

- [AC-1] Running `./install.sh` on a fresh macOS (Apple Silicon) or Ubuntu 22.04+
  machine completes all 9 steps without error, given: Docker is installed,
  `WALTER_DOMAIN` is set, and the operator has copy-pasted the 5 bootstrap env
  vars into the wizard prompts.
- [AC-2] Step 1 (detect OS + install deps) installs missing deps via
  `brew install` on macOS or `apt-get install` on Ubuntu. Required deps:
  `git`, `curl`, `jq`, `docker`, `bats`. Missing docker triggers a human-readable
  error with install instructions and exits 1 (wizard cannot continue without docker).
- [AC-3] Step 2 (env var prompts) presents each of the 5 bootstrap vars with
  the current value (if already set in `.env.local`), a description, and a
  default (where applicable). Operator can press Enter to accept the current/default
  value. After step 2, `.env.local` contains all 5 vars.
- [AC-4] Step 3 (personal overlay) calls `setup/personal-overlay-init.sh` if the
  overlay does not exist, and prints instructions to fill in the operator profile.
  If the overlay already exists, prints "overlay found, skipping init".
- [AC-5] Step 4 (Plane workspace + states) creates via Plane API: workspace
  named `walter-os`, and custom states `awaiting-resume`, `awaiting-consensus`,
  `awaiting-human`, `held_for_vacation` in the Council project. If API call
  fails (PLANE_API_TOKEN unset or Plane not yet running), prints "Plane not
  configured — skipping. Re-run with --step 4 after Plane is up."
- [AC-6] Step 5 (Postgres DBs) runs SQL to create databases: `walter_lessons`,
  `walter_analytics`, `walter_control_tower` with appropriate users and grants.
  Idempotent: `CREATE DATABASE IF NOT EXISTS` equivalent. If postgres is
  unreachable, prints "Postgres not reachable — skipping. Re-run with --step 5."
- [AC-7] Step 6 (docker compose up) runs `docker compose up -d` (W-1 compose)
  then calls `scripts/bootstrap.sh`. If compose file is not found, prints
  instructions pointing to W-1 setup and exits step 6 with "skipped".
- [AC-8] Step 7 (n8n workflow import) calls `setup/vm/services/n8n/import-workflows.sh`
  to register the workflow templates. Skips gracefully if n8n is not reachable.
- [AC-9] Step 8 (Infisical init) creates Infisical workspace "walter-os" and
  Machine Identity "walter-agent" via Infisical API. Writes `INFISICAL_CLIENT_ID`
  and `INFISICAL_CLIENT_SECRET` to `.env.local`. Skips if Infisical not reachable.
- [AC-10] Step 9 (doctor + next steps) runs `walter doctor` and prints its output.
  Then prints a "Next steps" banner listing: Control Tower URL, Plane URL, first
  `walter new project --interactive` command, link to docs.
- [AC-11] `./install.sh --dry-run` prints every action that would be taken for all
  9 steps but executes none of them. Exit 0.
- [AC-12] `./install.sh --step 5` runs only step 5 (Postgres DBs). Exit 0 on success.
- [AC-13] Bats test `tests/install/wizard.bats` runs `./install.sh --dry-run`
  and asserts the output contains markers for all 9 steps. Also tests
  `--step 5` flag execution path.

## Non-goals

- GUI or TUI (terminal UI with ncurses): the wizard is plain readline-style
  prompts. Line-by-line is sufficient and more debuggable.
- Automated TLS certificate acquisition during install: Caddy handles ACME
  post-install. The wizard does not touch cert management.
- Windows support: macOS and Linux (Debian/Ubuntu) only for v0.2.0.
- Complete automation without operator input: the wizard always requires the
  5 bootstrap env vars. Fully unattended install via env vars is a v0.3.0
  feature (`./install.sh --unattended`).
- **[AC-3.5 DEFERRED → v0.3.0] Tailscale auto-detect**: if
  `command -v tailscale && tailscale status` succeeds, skip Headscale
  setup steps. NOT-A-GOAL for v0.2.0 — current install assumes Headscale
  self-host. Will be revisited in v0.3.0 when Tailscale funnel support
  is evaluated.

## Open questions

- Should `./install.sh --upgrade` still run the "step 0" symlink-only path
  (current behavior) or should it run the full wizard in non-interactive mode,
  checking each step idempotently? Spec says: `--upgrade` runs only step 0
  (symlinks + config regen) to preserve the fast upgrade path. The full wizard
  is for first install. Flag if the reviewer wants this changed.
- Step 6 calls `docker compose up -d` from the repo root. This assumes the
  all-in-one `compose.yml` from W-1 is at the repo root. If operators prefer
  `setup/vm/compose.yml`, the wizard needs a `--compose-file` flag. Spec
  includes this flag as optional, defaulting to `./compose.yml`.

## Implementation plan

### Task 1: Scaffold wizard harness [AC-11, AC-13]
- File: `install.sh` (rewrite, preserving step 0 logic)
- Change: Refactor install.sh to a step-dispatch pattern. Add `--dry-run`,
  `--step N` flags. Define `STEPS` array with 9 entries. Step 0 is the
  existing symlink logic. Steps 1–9 are new functions (stubs in this task).
- Verify: `./install.sh --dry-run` exits 0 and prints 9 step markers.
  `./install.sh --step 3` calls `step_3()` stub without error.

### Task 2: Implement step 1 — OS detection + dep install [AC-2]
- File: `install.sh` (modify step_1 function)
- Change: `uname -s` → macOS or Linux. Detect missing deps. `brew install`
  or `apt-get install -y` per dep. Hard-fail on missing Docker.
- Verify: Bats test: with `docker` command missing (mocked), step 1 exits 1
  with appropriate error message.

### Task 3: Implement step 2 — env var prompts [AC-3]
- File: `install.sh` (modify step_2 function)
- Change: Loop over 5 bootstrap vars. Read current value from `.env.local`.
  Prompt with `read -p` showing current value. Write accepted value to `.env.local`.
  `--dry-run` skips write.
- Verify: Bats test with piped input confirms `.env.local` written correctly.

### Task 4: Implement step 3 — personal overlay init [AC-4]
- File: `install.sh` (modify step_3 function)
- Change: Check for `~/.config/walter-os/overlay/`. If absent, call
  `setup/personal-overlay-init.sh`. If present, print "found, skipping".
  `--dry-run` prints what would happen.
- Verify: Test on machine without overlay: script called. With overlay: "skipping".

### Task 5: Implement step 4 — Plane workspace + states [AC-5]
- File: `install.sh` (modify step_4 function)
- Change: `curl` Plane API to create workspace (if not exists) and 4 custom
  states. Reads `PLANE_API_TOKEN` and `PLANE_API_URL` from `.env.local`.
  Graceful skip if unset or API unreachable.
- Verify: Mock Plane API server in bats test. Assert workspace and states
  created. Assert graceful skip when token unset.

### Task 6: Implement steps 5, 7, 8, 9 [AC-6, AC-8, AC-9, AC-10]
- File: `install.sh` (modify step_5, step_7, step_8, step_9 functions)
- Change: Step 5: psql commands for 3 databases. Step 7: calls
  `import-workflows.sh`. Step 8: Infisical workspace + Machine Identity via
  API. Step 9: `walter doctor` + next-steps banner.
- Verify: Each step has a --dry-run path that prints intended action.
  Step 9 output contains "Next steps" string.

### Task 7: Implement step 6 — docker compose up [AC-7]
- File: `install.sh` (modify step_6 function)
- Change: Run `docker compose -f ${COMPOSE_FILE:-compose.yml} up -d`. Wait
  for health check loop (max 3 minutes, 10s intervals). Then run
  `scripts/bootstrap.sh`. Graceful skip if compose file not found.
- Verify: --dry-run prints `docker compose up -d` without executing.

### Task 8: Write `tests/install/wizard.bats` [AC-13]
- File: `tests/install/wizard.bats` (new)
- Change: Tests: `--dry-run` contains all 9 step markers, `--step 5` output
  contains step-5 marker only, `--help` exits 0.
- Verify: `bats tests/install/wizard.bats` passes.

## References

- `install.sh` — existing installer (base for rewrite)
- `docs/specs/phase-w-1-docker-compose.md` — W-1 (prerequisite for step 6)
- `docs/specs/phase-w-5-depersonalization.md` — W-5 (prerequisite for step 3)
- `docs/operational/council-v2-prereqs.md` — manual steps now automated here
- `docs/operational/council-v2-deployment-runbook.md` — post-merge verification
  steps incorporated into step 9's next-steps banner
