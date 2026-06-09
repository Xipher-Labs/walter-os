# Walter-OS enforcement mode

Walter-OS uses several layers of control. They are not equivalent:

- **Policy-only**: agents can read `AGENTS.md` and follow instructions, but tool
  execution is not verified before it runs.
- **Partial enforcement**: at least one supported interception layer is active,
  such as Claude Code `PreToolUse` hooks or configured high-risk command
  wrappers. Other paths may still bypass Walter guardrails.
- **Enforced**: host hooks are active and high-risk command wrappers are first in
  `PATH` for the tools Walter can inspect.

Run:

```bash
walter doctor --enforcement
```

The command checks the current machine only. It inspects Claude Code settings at
`${CLAUDE_HOME:-$HOME/.claude}/settings.json` for Walter-managed `PreToolUse`
hooks and, when `WALTER_WRAPPER_DIR` is set, verifies that the wrapper directory
is the first entry in `PATH` and that high-risk tools resolve through that
directory.

## How to read the result

`policy-only` means Walter-OS could not prove tool execution is intercepted.
Agent instructions still matter, but they are not enforcement. Re-run
`./install.sh --upgrade`, restart the agent host, and check again.

`partial` means one interception layer is active, but another expected layer is
missing. For example, Claude Code hooks may be active while direct binary
bypasses remain, or high-risk wrappers may be active while supported host hooks
are not detected. This is the expected state before all local guardrails are
installed or before work is moved into a stronger sandbox.

`enforced` means the checked host hooks and configured wrapper directory are both
active. This is still not a complete sandbox. It proves that the inspected host
and wrapped tools route through Walter guardrails.

## Stronger isolation

Hooks are guardrails, not a jail. Stronger guarantees come from combining:

- process sandboxing for spawned commands;
- network egress controls;
- scoped/read-only tokens;
- separate high-risk MCP profiles;
- local-only routing for PHI, medical, privileged, or compliance-sensitive data.

Use `walter doctor --enforcement` as a visibility check, not as proof that every
possible execution path on the machine is contained.
