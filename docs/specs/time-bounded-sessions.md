# Time-bounded sessions (OSS Trust A-4) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer A item A-4
**Target release**: v0.5.0
**Depends on**: env-allowlist parser (P1-09 — in flight) for the new env vars.

## Problem

Today an agent session (Claude Code, Codex CLI, walter-os agents run-once) can run indefinitely if the operator forgets to close it. Idle 8-hour sessions on a developer laptop, multi-day session that survives a sleep/wake cycle, agent left running on a remote VM — all increase the blast radius of any compromise (stolen capability token, hijacked terminal, etc.).

A simple max-time + max-idle gate brings the cost-to-compromise down: even if everything else fails, the session dies on a schedule.

## Non-goals

- Replacing the operator's terminal multiplexer (tmux, zellij) idle handling. Operator's tooling stays authoritative for foreground-shell idle detection.
- Coordinating across multiple parallel sessions on the same machine. v0.5.0 = per-session; multi-session orchestration is a Phase V follow-up.
- Hard-killing a running tool mid-call. Session-end signal asks the agent to wrap up; tool finishes its current op, then session exits cleanly.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Two limits**: `WALTER_SESSION_MAX_HOURS` (wall-clock, default 8) and `WALTER_SESSION_MAX_IDLE_MIN` (idle since last tool call, default 60). Either tripping → session end. | 8 hours = a workday; 60 minutes = forgot-to-close. Operator-overridable per personal.env. |
| D-2 | **Implementation via `hooks/session-timeout.sh`** running on `UserPromptSubmit` (Claude Code) / `before_prompt` (Codex CLI). Every turn, check the clock; if either limit hit → emit a `block` with reason "session expired". | No new daemon. Uses existing PreToolUse-style hook chain. |
| D-3 | **Session start = first invocation in a working directory after a gap of `> SESSION_MAX_IDLE_MIN`.** Tracked via `~/.config/walter-os/state/session-<repo-hash>.json` (start-time + last-activity timestamps). | "Session" is operator-implicit; we don't try to be smarter. A different repo or a gap longer than the idle threshold starts a new session. |
| D-4 | **End behavior**: hook emits a `block` with `permissionDecisionReason: "Walter-OS session expired at HH:MM (max-hours=8). Type /session restart to begin a new session, or close this terminal."`. | Clear, actionable, doesn't kill the terminal. Operator decides what to do next. |
| D-5 | **`/session` slash command** in `commands/session.md` exposes `status`, `restart`, `extend <hours>`. `extend` REQUIRES an explicit reason (logged), capped at +2 hours per extension. | Operator can override for a legitimate long-running task; the extension is auditable. |
| D-6 | **PHI override**: when `WALTER_MODEL_PHI` is set (medical-data-compliance skill active), max-hours hard-cap at 4 and max-idle at 30 min, unmodifiable. | PHI sessions need tighter blast-radius. Independent of operator-set defaults. |
| D-7 | **Daily-audit reminder**: if `~/.config/walter-os/state/session-*.json` files exist with start-time > 24h ago (i.e. session-state didn't get cleaned up), emit `info` finding. | Catches operator-forgot-to-restart-after-extend scenarios. |

## Acceptance criteria

### AC-1 — Session state tracking
- [ ] `~/.config/walter-os/state/session-<repo-hash>.json` schema:
  ```json
  {
    "session_id": "<uuid>",
    "started_at": "2026-05-21T03:14:22Z",
    "last_activity_at": "2026-05-21T04:30:11Z",
    "repo_path": "/Users/.../walter-os",
    "max_hours": 8,
    "max_idle_min": 60,
    "extensions": [
      {"ts": "...", "added_hours": 2, "reason": "long debug session"}
    ]
  }
  ```
- [ ] `scripts/walter/lib/session-state.sh` exposes `walter_session_get`, `walter_session_touch`, `walter_session_end`.
- [ ] `bats` coverage in `tests/walter/session-state.bats`:
  - First invocation creates the state file with current ts
  - Subsequent invocations within idle window update `last_activity_at`
  - Invocation after `max_idle_min` gap creates a NEW session
  - Invocation after `max_hours` since start triggers end-of-session

### AC-2 — `hooks/session-timeout.sh` hook
- [ ] Hook runs on every `UserPromptSubmit` (Claude Code).
- [ ] Reads / writes session state via `session-state.sh`.
- [ ] On expiry: emits `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","permissionDecision":"block","permissionDecisionReason":"Walter-OS session expired at HH:MM (reason). Type /session restart to begin a new session."}}` and exits 0.
- [ ] On non-expiry: passthrough allow.
- [ ] bats coverage in `tests/hooks/session-timeout.bats`:
  - Within limits → allow
  - Beyond `max_hours` → block with `session expired (max-hours)` reason
  - Beyond `max_idle_min` → block with `session expired (max-idle)` reason
  - PHI mode → max-hours capped at 4

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

- Parent: `docs/specs/oss-trust-roadmap.md` Layer A item A-4
- Pattern: `docs/specs/p1-hardening-epic.md` AC-6 (env-allowlist — same approach for env vars)
- `commands/` directory (existing slash-command structure this extends)
- `scripts/walter/lib/env-loader.sh` (P1-09 — vars get added to its allowlist)
