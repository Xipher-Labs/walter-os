# W-4: Provider Choice Wizard

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

Walter-OS is built around a specific stack: LiteLLM for the LLM gateway, Plane for
project management, Forgejo for git, Infisical for secrets, Plausible for analytics,
Brave Search for search, and nomic-embed-text for embeddings. For a single operator
who has already committed to this stack, that's fine. For adoption, it is a
significant barrier: a team already using Linear has to understand the full Walter-OS
codebase to figure out where to swap in their own project tracker.

Every service category has at least one popular alternative: Linear vs Plane,
GitHub vs Forgejo, Doppler vs Infisical, direct Anthropic vs LiteLLM proxy,
Google Analytics vs Plausible, OpenAI embeddings vs local nomic. The configuration
for each alternative is scattered across `mcp/servers.json`, `.env.local`, and
script-level env var references. There is no single place to say "I use GitHub,
not Forgejo" and have that propagate correctly.

The provider wizard must also auto-detect: if `GITHUB_TOKEN` is already set and
`FORGEJO_TOKEN` is not, the wizard should propose GitHub as the detected choice
for the git provider, not ask the operator to type it.

## Proposed solution

`walter providers configure` — an interactive shell wizard (pure bash, no external
deps) that walks through seven provider categories. For each category, it detects
currently configured providers (by checking env vars and `providers.yaml`), presents
options, lets the operator select or confirm, and writes the result to
`~/.config/walter-os/providers.yaml`. It also patches `.env.local` with the
appropriate new env vars and updates `mcp/servers.json` to enable/disable the
relevant MCP entry.

`providers.yaml` becomes the canonical source of truth for provider choices.
The existing tooling reads from env vars, so `providers.yaml` is materialized into
`.env.local` by the wizard (and by `walter-os sync` on upgrade). No script
needs to be rewritten to read YAML — they still read env vars.

## Acceptance Criteria

- [AC-1] `walter providers configure` launches an interactive wizard that
  presents each of the seven provider categories in order. For each category,
  detected providers are highlighted with "(detected)" label.
- [AC-2] After the wizard completes, `~/.config/walter-os/providers.yaml` exists
  and contains one selected provider per category. The file survives a re-run
  (only updated categories change).
- [AC-3] `.env.local` is updated with provider-appropriate env vars. Example:
  if GitHub is selected for git, `GIT_PROVIDER=github` and `FORGEJO_URL` are
  removed (or commented out). If Forgejo is selected, `FORGEJO_URL` is set.
- [AC-4] `mcp/servers.json` is updated to enable the MCP for the selected provider
  and disable (not delete) MCPs for non-selected alternatives within the same
  category. Example: selecting Linear enables `linear` MCP entry and disables
  `plane` MCP entry (or vice versa).
- [AC-5] If the operator runs the wizard with `--category llm`, only the LLM
  provider category is reconfigured. All other categories are unchanged.
- [AC-6] If the operator selects "Ollama local" for embeddings, the wizard
  prints a post-config note: "Ollama must be running at OLLAMA_BASE_URL with
  nomic-embed-text pulled. Verify: `ollama list | grep nomic-embed-text`".
- [AC-7] Bats tests in `tests/cli/providers.bats` mock the interactive prompts
  and assert the resulting `providers.yaml` and `.env.local` contents for three
  representative configurations:
  - All-self-hosted (Plane + Forgejo + Infisical + Plausible + LiteLLM + Brave + nomic)
  - Cloud-first (Linear + GitHub + Doppler + Plausible cloud + Direct Anthropic + Algolia + OpenAI ada-002)
  - Minimal (no project tracker + GitHub + no secrets manager + no analytics + Direct Anthropic + no search + no embeddings)

## Provider categories and options

| Category | Options |
|---|---|
| LLM gateway | LiteLLM-proxy-all (self-host) \| Direct Anthropic \| Direct OpenAI \| Ollama local |
| Project management | Plane self-host \| Linear \| Plane cloud \| None |
| Git | Forgejo self-host \| GitHub \| GitLab |
| Secrets | Infisical self-host \| Doppler \| 1Password CLI \| Bitwarden CLI \| None |
| Web analytics | Plausible self-host \| Cloudflare Web Analytics \| GA4 \| None |
| Search | Brave Search API \| Algolia \| None |
| Embeddings | nomic-embed-text local (Ollama) \| OpenAI ada-002 \| Voyage AI \| None |

## Non-goals

- Automatic migration of data between providers (e.g., migrate Plane issues to
  Linear). The wizard only configures Walter-OS to point at the new provider;
  data migration is out of scope.
- Validating that API credentials are correct: the wizard writes what the operator
  provides. `walter doctor` is the tool for validation.
- Adding provider options beyond the seven categories above: the list is fixed
  for v0.2.0. Extension mechanism deferred to v0.3.0.

## Open questions

- Should the wizard require operator confirmation before writing `.env.local`
  (show a diff first)? Spec says yes: show the planned changes in a diff-like
  format, then "Press Enter to apply or Ctrl-C to abort." This prevents
  accidental overwrites.
- `mcp/servers.json` is in the `AGENTS.md` "blocked for ALL tiers" list (agents
  cannot modify it). The wizard runs as the operator (not as an agent), so this
  is fine — confirm with reviewer that the wizard is operator-context only.

## Implementation plan

### Task 1: Define `providers.yaml` schema [AC-2]
- File: `templates/providers.yaml.template` (new)
- Change: YAML schema with one key per category, value being selected provider
  slug. Include comments explaining each option. This is also the template
  the wizard uses for first-run initialization.
- Verify: File exists. YAML is valid (`yq . templates/providers.yaml.template`).

### Task 2: Implement detection logic [AC-1]
- File: `scripts/providers/detect.sh` (new)
- Change: Functions that detect configured providers by checking env vars:
  `GITHUB_TOKEN` → github, `FORGEJO_TOKEN` → forgejo, `LINEAR_API_KEY` → linear,
  `PLANE_API_TOKEN` → plane, `INFISICAL_CLIENT_ID` → infisical, etc.
  Returns a JSON/text map of detected providers.
- Verify: Unit test in providers.bats: with `GITHUB_TOKEN` set and others unset,
  detection returns `git=github`.

### Task 3: Implement wizard prompt loop [AC-1, AC-5]
- File: `scripts/providers/wizard.sh` (new)
- Change: Interactive loop over the 7 categories. Each iteration: reads detection
  output, presents numbered menu with "(detected)" labels, reads operator choice,
  stores in local variables. `--category` flag skips non-matching categories.
- Verify: Mock test (piped input) runs wizard non-interactively and captures
  selections.

### Task 4: Implement `providers.yaml` writer [AC-2]
- File: `scripts/providers/wizard.sh` (modify)
- Change: After all selections, shows planned changes diff, waits for Enter,
  writes `providers.yaml`. Merges with existing file (update only changed keys).
- Verify: Second wizard run with same selections produces no changes to `providers.yaml`.

### Task 5: Implement `.env.local` patcher [AC-3]
- File: `scripts/providers/patch-env.sh` (new)
- Change: Reads `providers.yaml`. For each category, comments out env vars for
  non-selected providers and ensures env vars for selected provider are present
  (with placeholder values if not yet set). Uses sed in-place with backup.
- Verify: Test: select GitHub for git, assert `FORGEJO_URL` is commented out in
  patched `.env.local`.

### Task 6: Implement `mcp/servers.json` patcher [AC-4]
- File: `scripts/providers/patch-mcp.sh` (new)
- Change: Reads `providers.yaml`. For each category, sets `"disabled": true`
  for non-selected provider MCPs and `"disabled": false` for selected. Uses
  `jq` for JSON editing.
- Verify: Test: select Linear, assert `plane` MCP has `"disabled": true` in
  patched servers.json.

### Task 7: Wire `walter providers configure` [AC-1, AC-5, AC-6]
- File: `bin/walter` (modify)
- Change: Add `providers_configure()` function that calls `detect.sh`,
  `wizard.sh`, `patch-env.sh`, `patch-mcp.sh` in sequence. Handle `--category`
  flag. Print Ollama post-config note when nomic-embed-text local is selected.
- Verify: `walter providers configure --category llm` runs without error and
  only modifies the `llm` key in `providers.yaml`.

### Task 8: Write `tests/cli/providers.bats` [AC-7]
- File: `tests/cli/providers.bats` (new)
- Change: 3 bats test cases for the three representative configurations.
  Uses piped input to simulate interactive selections. Asserts `providers.yaml`
  and `.env.local` output.
- Verify: `bats tests/cli/providers.bats` passes.

## References

- `mcp/servers.json` — canonical MCP registry
- `.env.example` — current env var reference
- `hooks/approval-gate.sh` — confirms mcp/servers.json is operator-only write
- `docs/specs/phase-w-6-install-wizard.md` — install.sh calls this wizard
