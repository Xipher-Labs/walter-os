# Process isolation sandbox (OSS Trust A-3) — spec

**Status**: implementation in progress; see `oss-trust-runtime-implementation.plan.md`
**Parent**: OSS Trust roadmap Layer A item A-3 — umbrella roadmap is in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); once merged the in-tree path is `docs/specs/oss-trust-roadmap.md`.
**Target release**: v0.5.x (after A-1 / A-2 / A-4 land)
**Depends on** (all in flight — must merge before A-3 implements):
- A-1 network egress allowlist — [PR #86](https://github.com/Xipher-Labs/walter-os/pull/86) (post-merge file: `docs/specs/network-egress-allowlist.md`)
- A-2 capability tokens — [PR #88](https://github.com/Xipher-Labs/walter-os/pull/88) (post-merge file: `docs/specs/capability-tokens.md`)
- A-4 time-bounded sessions — [PR #87](https://github.com/Xipher-Labs/walter-os/pull/87) (post-merge file: `docs/specs/time-bounded-sessions.md`)

## Problem

Walter-OS's hooks (`approval-gate`, `bash-denylist`, `capability-check`, `network-gate`) work at the SCRIPT level. They inspect a tool call, decide allow/block. But once allowed, the tool runs with the operator's full POSIX permissions: full filesystem access, full network (modulo A-1 allowlist), full ability to fork/exec/signal other processes.

A determined prompt-injection that reaches an "allowed" tool call (because it looks legitimate, or because the gates haven't seen this pattern) can still:
- Read arbitrary files outside the project (e.g. `~/.ssh/id_ed25519`)
- Spawn long-running background processes (e.g. mining)
- Signal / kill other operator processes

A-3 puts ALL hooks + skill execution inside a per-OS process sandbox with **deny-specific-paths + signal scope**. Hook execution uses a strict read-only posture with only a private scratch directory writable. Skill execution uses the more ergonomic default policy described in D-4, and operators can tighten it via overlay profiles for high-sensitivity projects.

## Non-goals

- Sandboxing the WHOLE shell session. The agent + the operator's terminal stay outside the sandbox; only hooks + skill executions go inside.
- Hardening agent processes themselves (Claude Code, Codex CLI). Those run in their own context; we sandbox what THEY spawn.
- Replacing host-level firewalls / SELinux / AppArmor. Operator's host security stays authoritative.
- Building a custom seccomp filter (rejected per parent D-1).

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Wrap per-OS primitives**: Linux → `nsjail`, macOS → `sandbox-exec`. Operator can override to `firejail` on Linux via `WALTER_SANDBOX_PROVIDER=firejail`. WSL is not separately detected in this shim slice; if it reports `Linux` from `uname -s`, it follows the Linux path. | Per parent D-1. No invented sandbox; we use mature tools. |
| D-2 | **Single uniform shim**: `scripts/walter/lib/sandbox.sh` exposes `walter_sandbox_run <profile> <cmd...>` (positional args; the `<cmd...>` collects the executable plus its args — identical to the AC-1 signature). Internally resolves the per-OS invocation. | Skills + hooks don't care which sandbox is active; they call the shim. |
| D-3 | **Two profiles for v0.5.x**: `walter-hook-default` (for PreToolUse hooks — read-only filesystem except private sandbox scratch + no net) and `walter-skill-default` (for skill executions — read-write repo + read-only overlay + network per A-1 allowlist). | Most hooks don't need host writes or net. Skills are the place real work happens. |
| D-4 | **Default policy: allow most, deny dangerous**. From parent D-1 open question — `walter-skill-default` denies: write outside cwd repo + parent (limit 1 level up); access to `~/.ssh/`, `~/.aws/`, `~/.config/walter-os/state/session-*.key` (per-session signing keys from A-2 / capability-tokens — NOT the whole `state/` directory, which also holds decision journals + knowledge cards that skills legitimately read), `~/.gnupg/`, `*.pem`, `*.key`; signal to PIDs outside the sandboxed tree. Allows everything else by default. | Reflects parent D-1 second option. Lower footgun for first-time adopters. Operator hardens per project via overlay profile. Scoping the state deny to `session-*.key` only avoids breaking the general `state/` use cases. |
| D-5 | **`walter-skill-default` honors the `cap_token` IF present**: if the calling tool has a valid PASETO cap-token (A-2) declaring `scope.paths`, the sandbox tightens to those paths. No cap → fall back to the D-4 default-allow-but-deny-sensitive policy. | Composes with A-2. A high-tier op that already required a cap also benefits from path-tightened sandbox. |
| D-6 | **Bypass requires `WALTER_SANDBOX_BYPASS=1` + `--no-sandbox` flag** in the tool command — same two-factor pattern. Logged in the audit chain. | Same as bash-denylist + egress-allowlist bypass. |
| D-7 | **Sandbox failure semantics**: if the per-OS primitive is missing or fails to start, hook emits a `block` (fail-CLOSED). Don't silently run unsandboxed. | Same posture as P0-03 jq-fail-closed. |
| D-8 | **Profile customization via overlay**: `~/.config/walter-os/overlay/sandbox-profiles/<name>.nsjail.conf` (Linux) or `.sb` (macOS). Operator extends a profile by inheriting from `walter-hook-default` / `walter-skill-default`. | Operators with sensitive repos (medical data, etc.) can tighten without forking Walter-OS. |

## Acceptance criteria

### AC-1 — `sandbox.sh` shim + per-OS provider detection
- [ ] `scripts/walter/lib/sandbox.sh` exposes:
  - `walter_sandbox_provider` — echoes `nsjail` / `sandbox-exec` / `firejail` per detected OS + env override
  - `walter_sandbox_run <profile> <cmd...>` — wraps the command; returns the wrapped command's exit code
  - `walter_sandbox_check` — verifies the provider binary is installed + the default profiles exist
- [ ] Linux default = `nsjail` (operator can override to `firejail` via `WALTER_SANDBOX_PROVIDER=firejail`).
- [ ] macOS default = `sandbox-exec` (no override available; only one option).
- [ ] Other OS = fail with `walter-sandbox: no supported sandbox provider on <os>; sandbox required by A-3` (fail-CLOSED).
- [ ] bats coverage in `tests/walter/sandbox-shim.bats`:
  - macOS path: `walter_sandbox_provider` → `sandbox-exec`
  - Linux path (via mock `uname`): `walter_sandbox_provider` → `nsjail`
  - Override path: `WALTER_SANDBOX_PROVIDER=firejail` → `firejail`
  - Missing provider: `walter_sandbox_check` exits 1

### AC-2 — `walter-hook-default` profile
- [ ] `setup/sandbox-profiles/walter-hook-default.nsjail.conf` (Linux):
  ```
  # Read-only repo root; read-only operator overlay; no network; no signal out.
  mode: ONCE
  rlimit_as: 512  # MB
  rlimit_cpu: 30  # seconds
  rlimit_fsize: 100  # MB
  rlimit_nofile: 64
  
  mount {
    src: "${WALTER_OS_HOME}"
    dst: "${WALTER_OS_HOME}"
    is_bind: true
    rw: false
  }
  mount {
    src: "${HOME}/.config/walter-os"
    dst: "${HOME}/.config/walter-os"
    is_bind: true
    rw: false
  }
  mount {
    src: "/dev/null"
    dst: "/dev/null"
    is_bind: true
    rw: true
  }
  mount {
    src: "/dev/urandom"
    dst: "/dev/urandom"
    is_bind: true
    rw: false
    mandatory: false
  }
  
  envar: ["PATH", "HOME", "USER", "LANG", "WALTER_CONFIG", "WALTER_OS_HOME"]
  
  keep_caps: false
  disable_no_new_privs: false
  iface_no_lo: true
  # No internet — hooks shouldn't need to call out.
  ```
- [ ] `setup/sandbox-profiles/walter-hook-default.sb` (macOS sandbox-exec profile, semantically equivalent).
- [ ] bats coverage in `tests/walter/sandbox-hook-profile.bats`:
  - Running `cat ~/.ssh/id_rsa` via the profile → blocked
  - Running `cat $WALTER_OS_HOME/README.md` via the profile → allowed (read-only)
  - Running `echo X > $WALTER_OS_HOME/X` via the profile → blocked (read-only)
  - Running `echo X > <cwd outside HOME/WALTER/config>` via the profile → blocked
  - Running `mktemp` via the profile → allowed inside the sandbox's private tmpfs on Linux (`nsjail` `/tmp`, `firejail` `private-tmp`) and inside private sandbox scratch via `TMPDIR` on macOS
  - Network call (`curl https://example.com`) via the profile → blocked

### AC-3 — `walter-skill-default` profile
- [ ] `setup/sandbox-profiles/walter-skill-default.nsjail.conf`:
  - Repo cwd + 1-level parent: `rw: true`
  - Operator overlay: `rw: false`
  - DENY: `~/.ssh/`, `~/.aws/`, `~/.config/walter-os/state/session-*.key` (per-session signing keys from A-2 only — NOT the whole `state/` dir; matches D-4's narrower scope so skills can still read decision journals + knowledge cards from `state/`), `~/.gnupg/`, `*.pem`, `*.key`
  - Network: per A-1 egress allowlist (sandbox doesn't override; A-1 hook is still authoritative)
  - Signal scope: cgroup-limited (no kill outside sandboxed PID tree)
- [ ] macOS equivalent in `walter-skill-default.sb`.
- [ ] bats coverage in `tests/walter/sandbox-skill-profile.bats`:
  - Write to cwd-repo → allowed
  - Write to `~/Desktop/` (outside cwd parent) → blocked
  - Read `~/.ssh/id_rsa` → blocked
  - Read `~/Projects-Personal/walter-os/README.md` from a cwd of `~/.../some-other-project` → blocked (outside cwd parent)
  - `kill -9 <operator-shell-pid>` → blocked

### AC-4 — Hook + skill integration
- [ ] `hooks/approval-gate.sh`, `hooks/bash-denylist.sh`, `hooks/capability-check.sh`, `hooks/network-gate.sh` — all wrap their python/jq invocations via `walter_sandbox_run walter-hook-default`. (All four hooks live under `hooks/`; earlier draft of this AC dropped the `hooks/` prefix on the last three, which would have implied bare-name paths that don't exist.)
- [ ] Skill-execution entry point (where `walter-os` invokes a skill — TBD per-skill): wraps via `walter_sandbox_run walter-skill-default`.
- [ ] Bypass: `WALTER_SANDBOX_BYPASS=1 walter ... --no-sandbox` runs unsandboxed; emits a WARN to stderr + audit-chain entry with `decision_source: "operator-sandbox-bypass"`.
- [ ] bats coverage in `tests/hooks/sandbox-integration.bats`.

### AC-5 — install.sh + audit integration
- [ ] `install.sh` checks for the per-OS sandbox provider:
  - Linux: `nsjail` (suggest `apt install nsjail` or build from source)
  - macOS: `sandbox-exec` (built-in; no install needed)
  - **Missing during install** → `install.sh --upgrade` emits a
    LOUD WARNING and writes a `~/.config/walter-os/sandbox-disabled`
    sentinel so the operator knows the sandbox layer is not active.
    `install.sh` does NOT silently skip — the message tells the
    operator exactly how to remediate (install nsjail / use macOS).
  - **Missing during runtime** (the hook fires but the provider has
    been uninstalled since `install.sh` ran): hook emits `block`
    (fail-CLOSED per D-7). This is the strict path — once Walter-OS
    KNOWS sandbox should be active, missing-provider is treated as
    a security regression, not a soft degradation.
  - The two cases are deliberately different: at install time we
    haven't promised the user anything yet; at runtime we have.
- [ ] `daily-supply-chain-audit` adds `check_sandbox_state()`:
  - Provider missing AND no `sandbox-disabled` sentinel → `crit`
    finding (sandbox layer is down without operator acknowledgment)
  - Provider missing WITH sentinel → `high` finding (operator
    acknowledged at install time but hasn't installed the provider
    since)
  - **Provider binary checksum drift** → `crit` finding. Audit
    snapshots `sha256sum $(command -v nsjail)` (or `sandbox-exec`
    / `firejail`) on first run; subsequent runs that hash a
    different binary emit a `crit` finding identifying the path
    + the before/after sha256. Same pattern as P1-07 external-
    hook integrity. `walter-os baseline-sandbox-provider`
    re-snapshots after an intentional reinstall.
  - Profile files modified since baseline → `high` finding (operator
    might have intentionally changed; can re-baseline via
    `walter-os baseline-sandbox-profiles`)

### AC-6 — Cap-token integration (D-5)
- [ ] When a tool call carries a valid PASETO cap-token (A-2) declaring `scope.paths`, the skill profile is dynamically rewritten:
  - Profile template loaded from `walter-skill-default`
  - `mount` entries replaced with the cap's `scope.paths` (rw: true for matching paths; rw: false for everything else)
  - Generated profile stored at `${WALTER_RUNTIME_DIR}/sandbox/skill-<cap-nonce>.nsjail.conf`
  - Sandbox wrapping uses the generated profile
- [ ] bats coverage in `tests/walter/sandbox-cap-integration.bats`:
  - With cap declaring `scope.paths: ["./src/**"]`: write to `./src/x.ts` allowed; write to `./tests/y.bats` blocked
  - Without cap: falls back to `walter-skill-default` D-4 policy

### AC-7 — Operator-facing docs + CHANGELOG
- [ ] `docs/operational/sandbox-profiles.md` (new):
  - Per-OS provider detection (nsjail / sandbox-exec / firejail)
  - Profile inheritance pattern (overlay extension)
  - Common operator customizations (medical-data PHI profile, financial-tools profile, etc.)
  - Sandbox-bypass two-factor escape + when to use it
- [ ] CHANGELOG entry under `[Unreleased] → Added (runtime sandboxing)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Allowed Bash call reads `~/.ssh/id_rsa` despite approval-gate approve | `walter-skill-default` D-4 denies access to `~/.ssh/*` regardless of approval-gate. |
| Allowed Bash spawns long-running miner | `walter-skill-default` cgroup-limits the PID tree; kill on session end. |
| Allowed Bash kills operator's shell | Signal scope limited to sandbox PID tree. |
| Sandbox provider replaced with a no-op binary | `walter_sandbox_check` (AC-1) currently only verifies the binary is INSTALLED + the profile files exist; that's not enough to detect a binary swap. Detection needs a checksum baseline + diff (same pattern as P1-07 external-hook integrity). The daily audit's `check_sandbox_state()` (AC-5) is extended to snapshot the sha256 of `$(command -v <provider>)` on first run and emit a `crit` finding on any subsequent change. Documented as the actual detection mechanism, NOT `walter_sandbox_check` alone. |
| Operator legitimately needs to write outside cwd parent | `WALTER_SANDBOX_BYPASS=1` + `--no-sandbox` two-factor (logged) OR ship a custom profile via overlay. |
| Cap-token scoped to one path; sandbox profile-rewrite leaks broader access | The dynamic profile rewriter is the SOLE source of truth for the wrapped command's mounts; `walter-skill-default` is the default ONLY when no cap is present. Bats test asserts. |

## Out of scope

- Custom seccomp-bpf filter (parent D-1 rejected this).
- Sandboxing the agent process (Claude Code / Codex CLI) itself.
- Sandboxing Walter-VM service stacks (those run under their own Docker isolation; orthogonal).
- Hardware-level isolation (VM-per-session, Firecracker, etc.). Future layer.
- Multi-cgroup orchestration on Linux (single-cgroup-per-session is the v0.5.x floor).

## Recommended PR ordering

1. AC-1 — `sandbox.sh` shim + provider detection + bats
2. AC-2 — `walter-hook-default` profile (Linux + macOS) + bats
3. AC-3 — `walter-skill-default` profile + bats
4. AC-4 — wire hooks + skill entry-point to `walter_sandbox_run`
5. AC-5 — install.sh check + audit integration
6. AC-6 — cap-token dynamic profile rewriter (depends on A-2 caps merged)
7. AC-7 — docs + CHANGELOG (closing PR)

Each ≤300 LOC. 3-round review.

## Open questions for the operator

1. **macOS `sandbox-exec` is deprecated by Apple but still functional.** Should we use it (proposal — no current alternative) or skip macOS sandboxing for v0.5.x and wait for a replacement (Apple hasn't announced one yet)? Proposal: use it; document the deprecation in `docs/operational/sandbox-profiles.md`; operators who don't want it can opt out via the two-factor bypass (`WALTER_SANDBOX_BYPASS=1` env var AND `--no-sandbox` flag on the command — both required per D-6 — NOT the env var alone, which by itself does nothing).
2. **Linux `nsjail` requires kernel features that some restrictive hosting providers disable.** Fall back to `firejail`? Proposal: yes — `firejail` is more widely available; document the trade-off (nsjail is more fine-grained, firejail is more available). Operator chooses via `WALTER_SANDBOX_PROVIDER`.
3. **`walter-skill-default` allows writing to "cwd repo + 1 level parent"** — too tight (operators do legitimately write to `~/Desktop/`)? Too loose? Proposal: keep tight; operator-overlay profile extends if they need a wider write scope per-project.

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` Layer A item A-3
- Sibling: `docs/specs/capability-tokens.md` A-2 (cap-token-driven dynamic profile rewrite — AC-6)
- Sibling: `docs/specs/network-egress-allowlist.md` A-1 (sandbox composes; egress-allowlist is still authoritative on network)
- nsjail: <https://github.com/google/nsjail>
- macOS sandbox-exec: <https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf>
- firejail: <https://github.com/netblue30/firejail>
