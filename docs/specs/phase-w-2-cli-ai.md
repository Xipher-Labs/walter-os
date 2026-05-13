# W-2: Walter CLI AI Integration

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

Walter-OS has a mature LLM invocation stack (`scripts/agents/lib/llm.sh`) that the
six Council agents use for every task they execute. The operator-facing CLI (`bin/walter`
and `bin/walter-os`) uses none of it. All CLI commands are static: they read files,
call APIs, print formatted output. There is no natural-language interface — you
either know the exact subcommand (`walter-os agents status`) or you don't know it
exists.

This creates two friction points. First, onboarding: a new operator running
`walter help` gets a wall of subcommands with no way to ask "what are my agents
working on right now?" in plain language. Second, the `project-induction` skill
(Phase R) works as a conversational interview inside a Claude Code session, but
it requires the operator to be inside Claude Code. A new operator who just ran
`install.sh` on a bare machine cannot start a project interview without first
setting up Claude Code. A CLI-native `walter new project --interactive` fixes that.

The LLM integration must degrade gracefully: if `LITELLM_BASE_URL` is unset (no
LiteLLM configured yet, new install scenario), every AI-powered command falls back
to a clear "AI not configured" message with instructions, not a silent failure.

## Proposed solution

Four new subcommands added to `bin/walter` (the simpler of the two binaries,
currently handling project-level ops). Each subcommand routes through the existing
`lib/llm.sh` with appropriate system prompts. Mocked LLM response support in tests
via the `WALTER_LLM_MOCK_FILE` environment variable (already used by some agent
tests).

The implementation is pure bash, consistent with the rest of `bin/walter`. No new
runtime dependencies. LiteLLM is the preferred endpoint; direct Anthropic API
falls back if `LITELLM_BASE_URL` is unset and `ANTHROPIC_API_KEY` is set; graceful
no-AI mode if neither is configured.

## Acceptance Criteria

- [AC-1] `walter new project --interactive` invokes an LLM-driven interview
  (minimum 5 questions: project name, domain, stack, compliance regime, project
  type). After the interview, outputs to stdout: (a) a `AGENTS.md` draft,
  (b) a spec charter in `docs/specs/` format, (c) a Plane epic creation command
  the operator can confirm and run. With LLM unset, prints "AI not configured"
  + instructions and exits 1.
- [AC-2] `walter ask "<question>"` sends the question to the LLM with a system
  prompt containing current Council state (output of `walter-os agents status`
  + current `mode.json` + last 24h spend summary). Returns a natural-language
  answer. Example: `walter ask "what agents are blocked"` returns a prose
  summary. With LLM unset, exits 1 with clear message.
- [AC-3] `walter explain <skill>` reads `skills/<skill>/SKILL.md`, sends it to
  the LLM with a system prompt explaining the operator's current stack (derived
  from `~/.config/walter-os/providers.yaml` if present, else generic), and
  returns a 3–5 sentence plain-English explanation of what the skill does and
  when to use it. Unknown skill name: exits 1 with list of available skills.
  With LLM unset: prints the raw SKILL.md content as fallback (no exit 1).
- [AC-4] `walter pivot` invokes the `project-pivot` skill (W-3). Effectively an
  alias for `walter new project --interactive` scoped to existing project
  reconfiguration. If no `AGENTS.md` found in cwd, prints guidance and exits 1.
- [AC-5] All four commands have bats tests in `tests/cli/ai.bats` that use
  `WALTER_LLM_MOCK_FILE` to mock LLM responses. Tests cover: happy path,
  LLM unset (graceful degradation), invalid arguments.
- [AC-6] `walter help` output updated to include the four new commands with
  one-line descriptions.
- [AC-7] Cost recording: every successful AI call (from ask, explain, pivot,
  new-project-interactive) appends a JSONL line to ~/.config/walter-os/cli-spend.jsonl
  with schema: {timestamp, command, model, approx_tokens}. Real cost attribution
  in USD is deferred to v0.3.0 (requires per-provider rate cards).

## Non-goals

- Streaming responses: LLM calls return full response before printing. Streaming
  is a UX improvement deferred to v0.3.0.
- Persistent conversation: `walter ask` is stateless per call. No session history.
- Plugin architecture for adding new AI commands: plain bash convention is
  sufficient for the four commands needed here.

## Open questions

- Should `walter new project --interactive` write the AGENTS.md and spec to disk
  automatically, or print to stdout and let the operator redirect? Spec says
  stdout-first with explicit `--write` flag to persist to disk. This prevents
  polluting the cwd on a misfire.
- `walter ask` context window: including full `agents status` output in the system
  prompt may exceed token limits for complex states. Mitigation: truncate to last
  100 lines of status, with a note in the output if truncation occurred.

## Implementation plan

### Task 1: Add LLM health-check helper to `lib/llm.sh` [AC-1, AC-2, AC-3, AC-4]
- File: `scripts/agents/lib/llm.sh` (modify)
- Change: Add `llm_available()` function that returns 0 if LiteLLM or direct
  Anthropic API is configured, 1 otherwise. Used by all four commands before
  attempting LLM calls.
- Verify: Unit test in `tests/cli/ai.bats` asserts `llm_available` returns 1
  when both `LITELLM_BASE_URL` and `ANTHROPIC_API_KEY` are unset.

### Task 2: Implement `walter new project --interactive` [AC-1, AC-5]
- File: `bin/walter` (modify)
- Change: Add `new_project_interactive()` function. Sources `lib/llm.sh`.
  Drives 5-turn interview via `llm_invoke`. Assembles AGENTS.md draft and
  spec charter from interview output. Prints to stdout unless `--write` passed.
- Verify: `WALTER_LLM_MOCK_FILE=tests/fixtures/mock-interview.json walter
  new project --interactive` exits 0 and stdout contains "## Problem" (spec
  charter marker) and "# AGENTS.md" marker.

### Task 3: Implement `walter ask` [AC-2, AC-5]
- File: `bin/walter` (modify)
- Change: Add `cmd_ask()` function. Collects context: `walter-os agents status`
  output (truncated), `mode.json` contents, `walter-os spend report --last 24h`
  output. Sends as system prompt context + user question to LLM.
- Verify: Mock test asserts `walter ask "test question"` returns mock response
  text. Unset LLM test asserts exit 1 + "AI not configured" in stderr.

### Task 4: Implement `walter explain <skill>` [AC-3, AC-5]
- File: `bin/walter` (modify)
- Change: Add `cmd_explain()`. Reads `WALTER_OS_HOME/skills/<arg>/SKILL.md`.
  Sends to LLM with stack context system prompt. Falls back to cat of SKILL.md
  if LLM unavailable (not an error for this command).
- Verify: With mock LLM, output contains mocked explanation. With LLM unset,
  output contains raw SKILL.md content. With unknown skill name, exit 1 +
  list of available skills (ls of skills/ directory).

### Task 5: Implement `walter pivot` [AC-4, AC-5]
- File: `bin/walter` (modify)
- Change: Add `cmd_pivot()`. Checks for AGENTS.md in cwd. If missing, prints
  guidance and exits 1. Otherwise invokes `project-pivot` skill path through
  `new_project_interactive()` in reconfiguration mode (different system prompt).
- Verify: Mock test in cwd without AGENTS.md exits 1. Mock test in cwd with
  AGENTS.md exits 0 and produces output.

### Task 6: Write `tests/cli/ai.bats` [AC-5, AC-6]
- File: `tests/cli/ai.bats` (new)
- Change: Bats test suite. Fixtures: `tests/fixtures/mock-interview.json`,
  `tests/fixtures/mock-ask.json`, `tests/fixtures/mock-explain.json`. Tests
  all four commands + graceful degradation paths.
- Verify: `bats tests/cli/ai.bats` passes with no LLM credentials set.

### Task 7: Update `walter help` output [AC-6]
- File: `bin/walter` (modify, help section)
- Change: Add four new command descriptions to the help output block.
- Verify: `walter help` output contains "new project", "ask", "explain", "pivot".

## References

- `scripts/agents/lib/llm.sh` — LLM invocation helper
- `bin/walter-os` — existing CLI for ops commands
- `docs/specs/walter-council-v2.md` §R — project-induction skill (prerequisite)
- `docs/specs/phase-w-3-pivot-skill.md` — pivot skill spec
