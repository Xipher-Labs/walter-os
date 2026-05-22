# SPEC: Agent-install tier completion — align install.sh + walter-os + compose.yml + tier prompts

**Status:** Draft (2026-05-21). Awaiting operator approval.
**Triggered by:** Copilot Round 2 review on closed PR #103 surfacing 6 real drift findings between the four `setup/agent-install/tier-*.md` prompts (merged via #103's scope) and the actual current state of `install.sh`, `bin/walter-os`, and `compose.yml`.
**Related:** Closed PR #103, `setup/agent-install/tier-1.md`–`tier-4.md`, `install.sh`, `bin/walter-os`, `compose.yml`, `docs/specs/multi-agent-autonomy.md`, ADR 0014.
**Rigor classification:** MAJOR (touches `install.sh`, `bin/walter-os`, `compose.yml`, and the agent contract surface — operator-elected full rigor; auto-escalation does NOT fire here).

---

## 1. Problem

PR #103 added four tier installation prompts at `setup/agent-install/tier-{1,2,3,4}.md` that an operator pastes into Claude Code / Codex CLI / Cursor to install Walter-OS without following manual steps. Copilot Round 2 review identified **six real findings** where the prompts assume an API surface that does not exist today:

| # | Prompt promise | Reality |
|---|---|---|
| F1 | `install.sh` symlinks `AGENTS.md` and installs hooks (tier-1.md:128) | Partially true — `--upgrade` does symlinks, but the prompt enumerates a hook list that doesn't fully match what's installed. |
| F2 | `walter-os` CLI lives at `~/.local/bin/walter-os` (tier-1.md:133, tier-2.md:45) | False — the CLI lives at `${WALTER_OS_HOME}/bin/walter-os`. `install.sh` exports `PATH` to include it but does not copy/symlink to `~/.local/bin/`. |
| F3 | `install.sh --skills`, `--mcp-default`, `--mcp-high-risk`, `--commands`, `--approval-gate`, `--daily-audit-hook` exist (tier-2.md:85) | False — `install.sh` accepts only `--check`, `--dry-run`, `--upgrade`, `--uninstall`, `--step`. `--upgrade` already does everything those granular flags would have. |
| F4 | `walter-os doctor --tier N` (tier-2.md:235, tier-3.md, tier-4.md:66) | Partially true — `walter-os doctor` exists (`bin/walter-os` ~line 1086) and validates config + symlinks + skills + audit. But it does not accept `--tier N` for tier-scoped output. |
| F5 | `control-tower` runs only in Tier IV; Tier III's `docker compose --profile core --profile design up -d` does NOT start it (tier-3.md:64) | False — `compose.yml`'s `control-tower` block has NO `profiles:` declaration, so it starts on **any** `docker compose up -d`. |
| F6 | Plane workspace projects include `personal-projects` (tier-4.md:100) | Inconsistent — `docs/specs/multi-agent-autonomy.md` defines context labels as `context:{work,projects-personal,personal,medical}`. tier-4.md drifts. |

The drift makes the prompts unusable as written. An operator who pastes them into an agent gets verification errors at every "validate" step.

## 2. Goals

- **G1.** Every `install.sh` and `walter-os` command referenced in the four prompt files exists today AND does what the prompt claims.
- **G2.** Path references in the prompts match where files actually live, with one source of truth (`${WALTER_OS_HOME}/bin/` vs `~/.local/bin/` — ADR 0014 picks the answer).
- **G3.** `compose.yml` profile boundaries match the tier-N description (Tier IV services are profile-gated; Tier I-III services are not).
- **G4.** Plane workspace / project / label conventions match `docs/specs/multi-agent-autonomy.md` exactly across all artifacts.
- **G5.** Each tier prompt's "Verify" step actually passes when an operator runs it end-to-end on a fresh machine.
- **G6.** No regression on existing `install.sh --upgrade` / `walter-os doctor` consumers — both keep their pre-change contracts; we only add (tier-aware doctor) or restrict (profile gates) without removing.

## 3. Non-goals

- **NG1.** Not adding `install.sh --skills` / `--mcp-default` / etc. as separate flags. `--upgrade` already does the work; granular flags duplicate without value.
- **NG2.** Not building a packager that copies `walter-os` to a Homebrew tap or system path. Either it lives under `${WALTER_OS_HOME}/bin/` (status quo) or it gets a symlink to `~/.local/bin/` (ADR 0014's call).
- **NG3.** Not re-architecting `walter-os doctor`. We add `--tier N` filtering; we do not rewrite the check structure.
- **NG4.** Not changing `multi-agent-autonomy.md`'s Plane workspace spec. The tier-4 prompt aligns to the spec, not vice-versa.
- **NG5.** Not closing all "low confidence" Copilot suggestions on PR #103 (16 of them). Only the 6 high-confidence findings. The low-confidence ones become a follow-up issue.

## 4. Design (decisions locked, see ADR 0014)

### 4.1 CLI path: symlink to `~/.local/bin/` (ADR 0014 picks this)

`install.sh --upgrade` adds one symlink:
```
ln -sf "${WALTER_OS_HOME}/bin/walter-os" "${HOME}/.local/bin/walter-os"
```

Rationale (full in ADR 0014): `~/.local/bin/` is the XDG standard user binary path, on `$PATH` by default on most modern macOS + Linux setups. Symlink (not copy) keeps `git pull` semantics — operators always get the latest CLI without re-running `install.sh`.

The existing `PATH` export in `install.sh` (`${WALTER_OS_HOME}/bin:${PATH}`) is preserved as fallback for operators who don't have `~/.local/bin/` on `$PATH`.

### 4.2 `walter-os doctor --tier N`

Extend the existing `cmd_doctor()` in `bin/walter-os` (~line 1086) to accept an optional `--tier {1,2,3,4}` flag that filters which checks run. Without `--tier`, runs the existing full check set (backward compatible).

| Tier | Checks |
|---|---|
| 1 | `WALTER_OS_HOME` directory exists, `${WALTER_CONFIG}/env` file present, `~/.claude/CLAUDE.md` symlink, `~/.codex/AGENTS.md` symlink, `~/.local/bin/walter-os` symlink, agent CLI in PATH (claude/codex), bootstrap tooling (jq/git/gh) |
| 2 | All of tier 1 + skills symlinked into `~/.claude/skills/` + `~/.claude/settings.json` present + audit ran today + bootstrap tooling (brew/mise/docker/rg/shellcheck/bats/gitleaks/uvx + Solana CLI / Anchor / Maestro / Tailscale per personal context) |
| 3 | All of tier 2 + `WALTER_DOMAIN` env set + `HCLOUD_TOKEN` env set. The actual VM-side health checks run from the VM via the existing tier-3 verification commands; `walter-os doctor --tier 3` on local validates the env prerequisites only. |
| 4 | All of tier 3 + `~/.config/walter-os/trust-tiers.yml` present + Council agent definitions present (`agents/` populated) |

Implementation pattern: each existing `check` / `tier_check` call inside `cmd_doctor` is tagged with a tier number (1-4); the `--tier N` flag filters the calls before execution. New tier 3 and tier 4 checks are added at the end of the function.

> **Drift fix (PR #111 R4 Finding B)**: this table was previously
> aspirational — it mentioned a `branch-flow-guard hook installed`
> tier-1 check that doesn't exist in `cmd_doctor`, and tier-4 checks
> for "per-Council-agent virtual key (via Infisical lookup)" + "Plane
> workspace API reachable" that aren't implemented. Table rewritten to
> mirror `cmd_doctor` line-by-line. If any of the aspirational checks
> are later added (e.g. Plane API reachability under tier 4), update
> the table at the same time.

### 4.3 `compose.yml` profile gates

Add `profiles: [tier4]` to the `control-tower` service block. This is the **only** compose change. Other Tier IV services (Council agent containers, n8n workflows) are not in compose.yml today and are not in scope here.

After the change:
- `docker compose up -d` → starts core services, no control-tower.
- `docker compose --profile design up -d` → starts core + design, no control-tower.
- `docker compose --profile tier4 up -d` → starts core + control-tower.

This matches the prompt's separation: Tier III does not bring up Control Tower; Tier IV does.

### 4.4 Prompts rewrite (4 files)

Each tier-*.md gets reviewed against the actual `install.sh` / `walter-os` / `compose.yml` API. Changes:

- **tier-1.md**: drop the enumerated hook list; replace with "`install.sh --upgrade` installs the hooks declared in `hooks/`". Update CLI path verification to use `which walter-os` (resolves the symlink correctly).
- **tier-2.md**: replace `install.sh --skills`, `--mcp-default`, `--commands` with `install.sh --upgrade` (one command does it all). Drop `--approval-gate` (it's part of the bundle). Update `walter-os doctor` invocation to use `walter-os doctor --tier 2`.
- **tier-3.md**: explicitly add `--profile core` (and other selected profiles) to `docker compose up -d`. Remove the "control-tower NOT started" claim since the profile gate now enforces it. Use `walter-os doctor --tier 3`.
- **tier-4.md**: align Plane project names with `docs/specs/multi-agent-autonomy.md` (`projects-personal` not `personal-projects`). Add `--profile tier4` to the control-tower up. Use `walter-os doctor --tier 4`.

### 4.5 Hooks and contracts NOT touched

Out of scope explicitly:
- `hooks/branch-flow-guard.sh` — unchanged
- `hooks/pr-title-validator.sh` — unchanged
- `AGENTS.md` — unchanged (no policy change)
- `install.sh` legacy step 0 — unchanged

The only `install.sh` change is adding one symlink line inside the existing `--upgrade` path.

## 5. Acceptance criteria

Each criterion gets at least one test (per AGENTS.md DoD rule).

- [ ] **AC1.** After `./install.sh --upgrade`, `~/.local/bin/walter-os` exists as a symlink to `${WALTER_OS_HOME}/bin/walter-os`. Tested via `tests/install/cli-symlink.bats`.
- [ ] **AC2.** `~/.local/bin/walter-os --version` exits 0 and prints a semver. Tested in the same bats file.
- [ ] **AC3.** `install.sh --upgrade` is idempotent w.r.t. the symlink (re-run does not error, does not duplicate). Tested via a "run twice" bats case.
- [ ] **AC4.** `walter-os doctor` (no flag) prints the existing full check set unchanged. Tested via `tests/cli/walter-os-doctor.bats` — golden-output regression.
- [ ] **AC5.** `walter-os doctor --tier 1` runs only the tier-1 subset; `--tier 2` runs tier-1 + tier-2 additions; `--tier 3` and `--tier 4` add their respective extras. Tested via `tests/cli/walter-os-doctor-tier.bats` with stubbed env so all checks pass.
- [ ] **AC6.** `walter-os doctor --tier 99` exits non-zero with an error message ("invalid tier"). Tested in the same file.
- [ ] **AC7.** `docker compose --profile core up -d` does NOT start `control-tower`. Tested via `tests/compose/tier-profile-gates.bats` using `docker compose config --profile core | grep control-tower` (expect no service listing).
- [ ] **AC8.** `docker compose --profile tier4 up -d` DOES include `control-tower`. Tested in the same file.
- [ ] **AC9.** Every `install.sh` flag mentioned in `setup/agent-install/tier-*.md` actually exists in `install.sh`'s argparse. Tested via `tests/install/tier-prompts-flag-coverage.bats` — grep the prompts for `install.sh --<flag>`, assert each flag is in the case statement.
- [ ] **AC10.** Every `walter-os <subcommand>` mentioned in the prompts actually exists in `bin/walter-os`. Same test file.
- [ ] **AC11.** Plane project naming in `tier-4.md` matches `docs/specs/multi-agent-autonomy.md` (`projects-personal` not `personal-projects`). Tested via `tests/skills/tier-prompts-consistency.bats` — grep both files, assert intersection.
- [ ] **AC12.** Existing `bats tests/` suite passes unchanged (no regression). CI gates this.
- [ ] **AC13.** ADR 0014 documents the CLI path choice (symlink to `~/.local/bin/`) with rejected alternatives.

## 6. Out-of-scope follow-ups

- **F1.** Address the 16 "low confidence" Copilot suggestions on PR #103 (most were stylistic or asked for elaboration). File as a single docs follow-up issue.
- **F2.** Implement the `walter-os install-tier <N>` meta-command that wraps the four tier prompts into a single shell invocation. Useful for operators who don't want to paste prompts at all. Defer until the prompts are stable.
- **F3.** Profile-gate other Tier IV services (Council agent containers, n8n workflow loaders) once those land in `compose.yml`.
- **F4.** Validate the tier prompts via a literal "agent in CI" smoke test (LLM execution on a sandboxed container). Out of scope — would require non-trivial sandbox infra and LLM API spend in CI.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `~/.local/bin/` not on operator's `$PATH` | Med | Low | `install.sh --upgrade` prints a warning if the path isn't in `$PATH` and shows the shell-rc edit needed. Existing `PATH` export to `${WALTER_OS_HOME}/bin/` stays as fallback. |
| Existing operators who scripted around `walter-os` at the old path break | Low | Med | Old path still works (`${WALTER_OS_HOME}/bin/`) — we add the symlink, don't move the canonical file. Documented in commit message and changelog. |
| `compose.yml` profile change breaks existing deploys that relied on default-on control-tower | Med | Med | Document the change in CHANGELOG. Operators who genuinely want it always-on can add `tier4` to `COMPOSE_PROFILES` env. |
| `walter-os doctor --tier N` interferes with the existing `--last`/`--limit` style flags | Low | Low | Argument parser tested for ambiguity; `--tier` only valid for `doctor` subcommand. |
| Prompts rewrite drops a behavior an operator relied on | Low | Low | Reviewer subagent + Codex review will catch. Inline diff in PR shows every change. |

## 8. Open questions

None blocking. The design is locked per the operator-elected MAJOR rigor + survey results in this session. Confirm-and-proceed.

## 9. References

- Closed PR #103 (`feature/agent-installable-tiers`) — origin of the drift findings
- AGENTS.md → "Universal disciplines" → "Task rigor levels (tiny / small / major)"
- ADR 0009 (agent trust tiers) — pattern for per-agent / per-tier configuration
- ADR 0013 (solo-operator merge policy) — precedent for operator-configurable framework knobs
- `bin/walter-os` `cmd_doctor()` line 1086 — existing implementation to extend
- `install.sh` line 1583 ("STEP-0: Legacy symlink/config install") — where the CLI symlink will be added
- `compose.yml` `control-tower:` block — the profile gate target
- `docs/specs/multi-agent-autonomy.md` — Plane workspace + label conventions canonical reference
- `setup/agent-install/tier-{1,2,3,4}.md` (currently in main via PR #103 era) — the 4 prompt files to align
