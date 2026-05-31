# Time-bounded sessions (OSS Trust A-4) — spec

**Status**: Partially implemented (AC-1 foundation in progress)
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer A item A-4 (parent spec is in PR #83 — not yet on `main` at the time of this spec's writing).
**Target release**: v0.5.0
**Depends on**: env-allowlist parser (P1-09 — in PR #69, also not yet on `main`) for the new env vars.

## Problem

Today an agent session (Claude Code, Codex CLI, walter-os agents run-once) can run indefinitely if the operator forgets to close it. Idle 8-hour sessions on a developer laptop, multi-day session that survives a sleep/wake cycle, agent left running on a remote VM — all increase the blast radius of any compromise (stolen capability token, hijacked terminal, etc.).

A simple max-time + max-idle gate brings the cost-to-compromise down: even if everything else fails, the session dies on a schedule.

## Non-goals

- Replacing the operator's terminal multiplexer (tmux, zellij) idle handling. Operator's tooling stays authoritative for foreground-shell idle detection.
- Coordinating sessions across parallel terminals (e.g., one tmux pane idle-pausing another). v0.5.0 = per-session; cross-terminal orchestration is a Phase V follow-up. AC-6 provides a read-only `walter-os session list` across repos for visibility — that is enumeration, not coordination.
- Hard-killing a running tool mid-call. Session-end signal asks the agent to wrap up; tool finishes its current op, then session exits cleanly.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Two limits**: `WALTER_SESSION_MAX_HOURS` (wall-clock, default 8) and `WALTER_SESSION_MAX_IDLE_MIN` (idle since last tool call, default 60). Either tripping → session end. | 8 hours = a workday; 60 minutes = forgot-to-close. Operator-overridable per personal.env. |
| D-2 | **Implementation via `hooks/session-timeout.sh`** running on `UserPromptSubmit` (Claude Code). For Codex CLI, the timeout is enforced via a wrapper script invoked from the `walter-os` Codex entry point — Codex CLI has no native pre-prompt hook today, so we cannot wire this in `~/.codex/config.toml` directly. The plan revisits Codex integration once Codex ships a hook mechanism; until then, Codex sessions are bounded by the wrapper-script-injected check. Every turn, check the clock; if either limit hit → emit a `block` with reason "session expired". | No new daemon. Uses existing PreToolUse-style hook chain. AC-2 + AC-4 below cover the `UserPromptSubmit` registration in `install.sh`. |
| D-3 | **Session start = first invocation in a working directory after a gap of `> WALTER_SESSION_MAX_IDLE_MIN`.** Tracked via `~/.config/walter-os/state/session-<repo-hash>.json` (start-time + last-activity timestamps). Limits (`max_hours`, `max_idle_min`) come from the env vars NOT the state file — the state file only carries the activity timestamps and per-session UUID. | "Session" is operator-implicit; we don't try to be smarter. A different repo or a gap longer than the idle threshold starts a new session. |
| D-4 | **End behavior**: hook emits a `block` with `permissionDecisionReason: "Walter-OS session expired at HH:MM (<trigger>=<limit>). Type /session restart to begin a new session, or close this terminal."`. `<trigger>` is `max-hours` or `max-idle`; `<limit>` is the **effective** limit at hook-fire time (the operator-configured value, or the PHI cap from D-6 when `WALTER_PHI_MODE=1` is in effect). | Clear, actionable, doesn't kill the terminal. Reflects which limit actually fired AND with which value — an operator who set `WALTER_SESSION_MAX_HOURS=4` doesn't get a misleading "max-hours=8" message. |
| D-5 | **`/session` slash command** in `commands/session.md` exposes `status`, `restart`, `extend <hours>`. `extend` REQUIRES an explicit reason (logged), capped at +2 hours per extension. | Operator can override for a legitimate long-running task; the extension is auditable. |
| D-6 | **PHI override**: when the `medical-data-compliance` skill is active, max-hours hard-cap at 4 and max-idle at 30 min, unmodifiable by `/session extend`. The skill signals PHI-mode via `WALTER_PHI_MODE=1` exported from its activation hook. **Both pieces are new in this spec / the medical-data-compliance skill's roll-out** (the signal is not in `scripts/agents/lib/llm.sh` today; earlier drafts of this spec implied the env var was already wired — that was wrong). When `medical-data-compliance` ships, BOTH this hook AND `scripts/agents/lib/llm.sh` read the same `WALTER_PHI_MODE` env var so PHI sessions get the limit AND route to local-LLM-only consistently. | PHI sessions need tighter blast-radius. Independent of operator-set defaults. A single canonical PHI-mode signal name prevents implementers from building against a different / non-existent flag like `WALTER_MODEL_PHI`. |
| D-7 | **Daily-audit reminder**: if `~/.config/walter-os/state/session-*.json` files exist with start-time > 24h ago (i.e. session-state didn't get cleaned up), emit `info` finding. | Catches operator-forgot-to-restart-after-extend scenarios. |

## Acceptance criteria

### AC-1 — Session state tracking

The state file is a **trust-bounded** record with two anti-tamper
properties:

1. **Limits never come from the state file.** The hook reads
   `max_hours` and `max_idle_min` from env vars at hook-fire time,
   NOT from the state file. The state file echoes the active
   limits for inspection / debugging only — overwriting them on
   disk has no effect on enforcement.

2. **Timestamps are monotonic and audit-snapshotted.** The hook
   refuses any read where `started_at` would move BACKWARD relative
   to the previous tick (a rewind to "now" would otherwise reset
   the wall-clock window). `last_activity_at` follows the same
   floor. The state-dir lives under `~/.config/walter-os/state/`
   which **this spec REQUIRES be mode `0700`**. The mode-0700
   enforcement is NOT yet in the daily audit today
   (`check_state_dir_perms()` is referenced as a future function;
   adding it is part of this spec's AC-4 below — same pattern as
   the existing `check_skill_scripts()`). Additionally, the daily
   audit's `check_skill_scripts()` is extended to include
   `session-*.json` checksum baselines — a state-file rewrite
   between sessions surfaces as a `medium` finding the next audit
   run. Both audit additions are AC-4 items in this spec;
   referenced as "existing" was wrong in the earlier draft.

The combination — env-driven limits + monotonic-timestamp guard +
mode-0700 + daily checksum diff — means the timestamps in the
state file are trusted *enough* for the deny gate without needing
an HMAC. An attacker who can already write arbitrary files into
`~/.config/walter-os/state/` has bigger blast radius than this
hook anyway (they can drop the per-session Ed25519 key from
A-2 / capability-tokens).

- [ ] `~/.config/walter-os/state/session-<repo-hash>.json` schema:
  ```json
  {
    "session_id": "<uuid>",
    "started_at": "2026-05-21T03:14:22Z",
    "last_activity_at": "2026-05-21T04:30:11Z",
    "repo_path": "/Users/.../walter-os",
    "max_hours_at_start": 8,
    "max_idle_min_at_start": 60,
    "extensions": [
      {"ts": "...", "added_hours": 2, "reason": "long debug session"}
    ]
  }
  ```
  Field meanings:
  - **Trusted by the hook** (used for time-comparison): `session_id`,
    `started_at`, `last_activity_at`, `repo_path`, `extensions[].ts`,
    `extensions[].added_hours`.
  - **Inspection-only / NOT trusted** (the hook uses env vars
    instead): `max_hours_at_start`, `max_idle_min_at_start`. Renamed
    from `max_hours` / `max_idle_min` to make the trust boundary
    explicit. These exist so `walter-os session list` (AC-6) can
    display the limits that WERE in effect when the session started,
    even if the env vars have been changed since.
- [x] `scripts/walter/lib/session-state.sh` exposes `walter_session_get`, `walter_session_touch`, `walter_session_end`.
- [x] `bats` coverage in `tests/walter/session-state.bats`:
  - First invocation creates the state file with current ts
  - Subsequent invocations within idle window update `last_activity_at`
  - Invocation after `max_idle_min` gap reports `expired/max-idle` and leaves
    state unchanged until an explicit restart
  - Invocation after `max_hours` since start triggers end-of-session

### AC-2 — `hooks/session-timeout.sh` hook
- [ ] Hook runs on every `UserPromptSubmit` (Claude Code).
- [ ] `install.sh` (and `install.sh --upgrade`) registers the new
  `UserPromptSubmit` hook in `~/.claude/settings.json` alongside the
  existing `SessionStart` + `PreToolUse` registrations. Today the
  installer wires only those two events; the new hook needs an
  explicit registration step plus the same hook-checksums baseline
  treatment as the other hooks.
- [ ] Reads / writes session state via `session-state.sh`.
- [ ] On expiry: emits `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","permissionDecision":"block","permissionDecisionReason":"Walter-OS session expired at HH:MM (<trigger>=<effective-limit>). Type /session restart to begin a new session."}}` and exits 0. **Note**: this JSON shape is the Claude Code `UserPromptSubmit`-event contract (`hookSpecificOutput.permissionDecision`/`permissionDecisionReason`), which DIFFERS from the simpler `{"decision":"block","reason":"..."}` shape used by `PreToolUse` hooks like `bash-denylist.sh` and `approval-gate.sh`. The two contracts are not interchangeable — using the `PreToolUse` shape for a `UserPromptSubmit` hook produces a parse error in Claude Code and the hook fails open. See https://docs.claude.com/en/docs/claude-code/hooks for the per-event schema reference.
- [ ] On non-expiry: passthrough allow.
- [ ] bats coverage in `tests/hooks/session-timeout.bats`:
  - Within limits → allow
  - Beyond `max_hours` → block with `session expired (max-hours)` reason
  - Beyond `max_idle_min` → block with `session expired (max-idle)` reason
  - PHI mode (`WALTER_PHI_MODE=1`) → max-hours capped at 4
  - Hook is actually registered by `install.sh --upgrade` (smoke
    test reads `~/.claude/settings.json` after install).

### AC-3 — `/session` slash command
- [ ] `commands/session.md` documents:
  - `/session status` — prints elapsed wall-clock, time since last activity, time-to-expiry
  - `/session restart` — wipes the state file; next prompt starts a new session
  - `/session extend <hours> "<reason>"` — adds time, logs the extension in the state file's `extensions[]` array. `<hours>` capped at 2 per extension.
- [ ] Implementation in `scripts/walter/subcommands/session.sh` (new).
- [ ] `walter-os session status/restart/extend` CLI mirrors the slash command for non-Claude-Code shells.
- [ ] bats coverage in `tests/walter/session-cli.bats`.

### AC-4 — Env var wiring
- [ ] `WALTER_SESSION_MAX_HOURS`, `WALTER_SESSION_MAX_IDLE_MIN` added to `WALTER_ENV_ALLOWLIST` in `env-loader.sh` (extends the P1-09 allowlist).
- [ ] Defaults documented in `contexts/_examples/personal.env.example` with sensible inline comments.

### AC-5 — PHI override
- [ ] `medical-data-compliance` skill / hook: when active, exports `WALTER_SESSION_MAX_HOURS=4`, `WALTER_SESSION_MAX_IDLE_MIN=30`. These values are STICKY for the session — operator's `personal.env` cannot override upward.
- [ ] bats coverage in `tests/hooks/session-timeout-phi.bats`: with the medical-data skill active, expiry triggers at 4h regardless of operator override.

### AC-6 — Daily-audit integration
- [ ] `daily-supply-chain-audit` adds `check_stale_sessions()`:
  - For each `~/.config/walter-os/state/session-*.json` with `started_at` > 24h ago AND no recent `last_activity_at` update → `info` finding `session-stale-<hash>` with "operator may have forgotten to clean up".
- [ ] `walter-os session list` shows every active session across repos.

### AC-7 — Operator-facing docs + CHANGELOG
- [ ] `docs/operational/session-lifecycle.md` (new): start/end semantics, extension policy, PHI override, troubleshooting.
- [ ] CHANGELOG entry under `[Unreleased] → Added (default-deny security floor)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Operator forgets to close session; attacker walks up to laptop | Idle > 60 min → next prompt rejected; force-restart required |
| Operator's tmux is hijacked overnight | Wall-clock 8h cap; next morning's prompt forces restart |
| Long-running tool task makes idle timer expire mid-call | `walter_session_touch` runs on PreToolUse, not just UserPromptSubmit — tool execution counts as activity |
| Operator extends session 100 times | Each `extend` capped at +2h; capped count + reason logged. Audit-traceable. |
| Compromised session-state.json sets max-hours to 999 | State file is operator-writable; we don't trust it for the LIMITS — those come from env vars (in env-allowlist scope, P1-09-protected). State file only carries the timestamps. |

## Out of scope

- Cross-session orchestration on the same operator's machine.
- Killing terminal processes / signaling tmux. The hook BLOCKS the next prompt; operator decides whether to close the terminal.
- Hardware-token-bound session keys (that's OSS Trust A-2 capability tokens, a different spec).
- Session migration across machines.

## Recommended PR ordering

1. AC-1 — `session-state.sh` lib + bats (foundation)
2. AC-2 — `hooks/session-timeout.sh` (uses lib)
3. AC-3 — `/session` slash command + CLI
4. AC-4 — env-allowlist extension + `personal.env.example` doc
5. AC-5 — PHI override hook
6. AC-6 — daily-audit `check_stale_sessions()`
7. AC-7 — docs + CHANGELOG (closing PR)

Each ≤200 LOC. 3-round review.

## Open questions for the operator

1. **Default `max-hours = 8`**: too tight (the operator does long debug sessions)? Too loose (overnight risk)? Proposal: 8 with `extend` available; iterate based on operator self-reports.
2. **Default `max-idle-min = 60`**: same question. Proposal: 60. (Most lunch breaks are < 60 min; > 60 means operator forgot.)
3. **`/session extend` cap = 2 hours per invocation**: enough? Should the operator be able to extend by more? Proposal: 2h cap forces a re-think for long tasks (use `walter-os agents run-once` for autonomous work instead of an interactive session).

## Refs

- Parent: OSS Trust roadmap Layer A item A-4 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); post-merge in-tree path is `docs/specs/oss-trust-roadmap.md`
- Pattern: P1 hardening epic AC-6 (env-allowlist — same approach for env vars). The spec is in [PR #94](https://github.com/Xipher-Labs/walter-os/pull/94) (or whichever PR carries `docs/specs/p1-hardening-epic.md` once it lands on `main`).
- `commands/` directory (existing slash-command structure this extends)
- `scripts/walter/lib/env-loader.sh` (P1-09 — vars get added to its allowlist)
