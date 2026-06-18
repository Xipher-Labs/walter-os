# High-Risk Tool Wrappers

## Problem

`walter-os doctor --enforcement` can verify Claude Code hooks, but the host can
still remain in `partial` mode when supported high-risk command wrappers are
absent from `PATH`. In that state, direct CLI invocations such as `curl` or
`gh` can bypass Walter's hook chain.

## Decisions

- Add `walter-os wrappers setup|status|env`.
- Store wrappers under `${WALTER_CONFIG}/wrappers` by default, with `--dir` for
  tests and advanced installs.
- Tighten permissions only for newly created wrapper directories; preserve
  permissions on existing operator-supplied directories.
- Generate real executable files, not symlinks, because the enforcement doctor
  treats symlink wrappers as bypass-visible.
- Pin `WALTER_OS_HOME`, `WALTER_CONFIG`, `WALTER_WRAPPER_DIR`, and
  `WALTER_WRAPPER_BASH` in generated wrappers so runtime callers cannot
  redirect the policy store, repo checkout, wrapper directory, or shell.
- Start with `gh` and `curl`, where the existing gates already have command
  coverage. Additional CLIs need tool-specific policy before they count as
  enforced.
- Use one versioned runner: `scripts/walter/high-risk-tool-wrapper.sh`.
- Each wrapper runs Walter's approval, bash denylist, capability, and network
  gates before delegating to the real tool found later in `PATH`.
- Approval-gate policy override variables are stripped before the wrapper runs
  the gate, matching the fail-closed posture used for JSON gate bypass vars.
- `gh alias set --shell`, `gh alias set -s`, boolean `--shell=true`, and
  `!`-prefixed expansions are treated as shell-code registration: the wrapper
  runs `bash-denylist.sh` against the alias payload itself, not only the safely
  quoted top-level `gh` command.
- Stdin-backed `gh alias set --shell <alias> -` payloads are blocked because
  the wrapper cannot safely inspect and replay stdin to the real `gh` process.
- Persist operator shell hints in the private overlay env by default, unless
  `--no-env` is passed.

## Acceptance Criteria

- `walter-os wrappers setup --dir <dir>` creates one executable non-symlink
  wrapper per high-risk tool.
- `walter-os wrappers setup` is idempotent.
- `walter-os wrappers env --dir <dir>` prints export lines for
  `WALTER_WRAPPER_DIR` and `PATH`.
- A generated wrapper blocks a destructive command before the real tool runs.
- A generated wrapper delegates allowed commands to the real binary outside the
  wrapper directory.
- Walter gate-control flags are consumed by the wrapper and are not forwarded to
  the real binary.
- Wrapper callers cannot self-enable Walter bypass environment variables.
- All supported `gh alias set` shell forms (`--shell`, `-s`, `--shell=true`,
  and `!`-prefixed expansions) with payloads matching `bash-denylist.sh`
  patterns are blocked before the real `gh` binary runs.
- `gh alias set --shell <alias> -` is blocked before the real `gh` binary runs.
- Piped `curl` commands are blocked when they write to stdout directly or
  through stdout-equivalent targets such as `/dev/stdout`, including later
  transfers after `--next` or later output options. `--remote-header-name`
  alone is not treated as a safe output target.
- `walter-os wrappers status --dir <dir>` reports whether wrapper files exist.

## Non-Goals

- This does not modify shell dotfiles directly.
- This does not replace process isolation or network namespace enforcement.
- This does not grant agents permission to bypass approval, capability, or
  egress gates.
- This does not yet enforce `hcloud`, `docker`, `cloudflared`, `stripe`,
  `vercel`, or `railway`; those need explicit gate semantics before wrapper
  registration.
