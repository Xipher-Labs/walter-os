# Graphify knowledge maps — pilot spec

**Status**: ready for `/write-plan` after operator approval of pilot scope
**Issue**: #31 (`[FEAT] -LEARNING- add Graphify knowledge maps`)
**Tier**: 3 (multi-week pilot, opt-in only)
**Target release**: v0.6.0 (after the v0.4.0 / v0.5.0 cycle stabilizes)
**Depends on**: existing supply-chain audit + the env-allowlist parser (P1-09).

## Problem

Walter-OS is increasingly a multi-agent operating system, not a small codebase. Important behavior is spread across `AGENTS.md`, `contexts/**`, `skills/**`, `hooks/**`, `docs/specs/**`, `docs/operational/**`, and project-specific overlays. Agents rediscover structure with `rg` + file reads + local reasoning every session. That's expensive in context tokens and frequently misses cross-file relationships (a hook references a skill which references an ADR; agent picks one file, misses the other two).

[Graphify](https://github.com/safishamsi/graphify) (MIT, Python 3.10+, version v0.7.16 as of 2026-05-12) generates a knowledge graph over a repository and exposes it as JSON + Markdown + HTML + an stdio MCP server. The proposal: integrate it as an OPT-IN capability that operators turn on per repo, prove the value, then decide whether it earns a place in the default Walter-OS agent stack.

## Non-goals

- Replacing `rg` / file reads / existing Walter-OS skills with Graphify.
- Auto-installing Graphify across every operator project.
- Adding a global Graphify MCP server to the default profile.
- Sending PHI / medical / secrets / private overlays / sensitive wiki content to external model APIs.
- Committing large graph caches or cost-metadata files to git.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Pilot in walter-os itself first.** Generate a graph over THIS repo before promoting to operator projects. | Eat dogfood. If Graphify can't make sense of Walter-OS's own multi-layer structure, it's not ready for operator repos. |
| D-2 | **Opt-in per-repo via `walter-os graphify init`.** Never auto-enabled. Operator runs the command in a repo they want to graph. | Avoids surprise dependency installs + accidental remote upload of repo content. |
| D-3 | **`graphify-out/` is gitignored by default.** Generated artifacts (graph.json, graph.html, GRAPH_REPORT.md) stay local. | Cache size grows over time; not useful in version control; may contain extracted summaries that shouldn't leave the local machine. |
| D-4 | **`.graphifyignore` is committable and shipped with the repo.** Defines what Graphify must NEVER scan. | Documents the trust boundary inside the repo. Lives alongside `.gitignore`. |
| D-5 | **Default `.graphifyignore` excludes**: `.git/`, `node_modules/`, `external/`, `apps/control-tower/.next/`, `apps/control-tower/test-results/`, `~/.config/walter-os/overlay/` (operator-local), `~/sync/wiki/medical/` (PHI), `.env*`, `secrets.env*`, `*.key`, `*.pem`. | Prevents Graphify from extracting/sending these paths to its configured model provider. Per the project's docs, code is local-parsed via Tree-sitter but docs/PDFs/images may go to the LLM. |
| D-6 | **Force local-only mode via `GRAPHIFY_LOCAL_ONLY=1`** documented in the operator setup runbook. When set, Graphify must not call any remote model API even for docs. | Operator working with sensitive material can hard-gate remote calls. |
| D-7 | **No MCP server in v0.6.0.** Pilot ships CLI integration only. Decide on MCP after operator runs it for 2+ months. | Adding a new always-on MCP server is a daily-supply-chain-audit concern. Defer that until value is proven. |
| D-8 | **`uv tool install graphifyy==<exact-version>`** — pinned by Walter-OS to a verified-against-audit version. Bump in a deliberate PR after `check_min_release_age` clears the new version. | Same supply-chain discipline as every other operator tool. |

## Acceptance criteria

### AC-1 — Pilot setup script + `.graphifyignore`
- [ ] `scripts/graphify/setup.sh` (new) — bash script that:
  - Checks `uv` is installed. Install hints by platform:
    - macOS: `brew install uv`
    - Debian/Ubuntu (current Walter-OS reference Linux): `curl -LsSf https://astral.sh/uv/install.sh | sh` (Astral's official installer; runs unprivileged into `~/.local/bin`). `apt install uv` once it lands in stable.
    - Other Linux / WSL: same upstream installer.
    Canonical install matrix: <https://docs.astral.sh/uv/getting-started/installation/>. The setup script prints the platform-appropriate hint based on `$(uname -s)`.
  - Runs `uv tool install graphifyy==<pinned-version>` if not already installed.
  - Verifies `graphify --version` matches the pinned version.
  - Writes `.graphifyignore` if absent (with the D-5 exclusion list).
  - Adds `graphify-out/` to `.gitignore` if absent.
- [ ] `scripts/graphify/setup.sh` is idempotent — re-running is safe.
- [ ] `walter-os graphify init` wraps `scripts/graphify/setup.sh` as the operator-facing entry point per D-2. The wrapper is a thin shim that just dispatches to the script.
- [ ] `.graphifyignore` (new) ships at repo root with the D-5 default exclusions.

### AC-2 — Pilot generation + report
- [ ] `scripts/graphify/build.sh` (new) — runs `graphify build` against the CURRENT REPO (resolved via `git rev-parse --show-toplevel`, falling back to `pwd` if not a git repo). Outputs `graphify-out/{graph.json,graph.html,GRAPH_REPORT.md}` inside that repo. The build script is per-repo (matching D-2's opt-in-per-repo workflow), NOT hardcoded to `$WALTER_OS_HOME`. The pilot ASCII diagram earlier in this spec shows the operator running it inside walter-os as a SPECIFIC example, but the script itself is repo-agnostic.
- [ ] First-time build prints elapsed time, output size, and a "are docs being sent to your model API?" prompt that reads `GRAPHIFY_LOCAL_ONLY` env var.
- [ ] `walter-os graphify build` wraps `scripts/graphify/build.sh` for discoverability.

### AC-3 — Query workflow
- [ ] `walter-os graphify query <natural-language>` runs `graphify query` and prints the answer.
- [ ] `walter-os graphify path <file-a> <file-b>` shows the shortest dependency / reference path between two files.
- [ ] `walter-os graphify explain <symbol>` returns Graphify's summary of a function / class / skill.
- [ ] All three wrap the underlying CLI; no new logic in walter-os except argument forwarding.

### AC-4 — Local-only enforcement
- [ ] `scripts/graphify/build.sh` exports `GRAPHIFY_LOCAL_ONLY=1` by default. Operator must explicitly opt in to remote extraction via `walter-os graphify build --allow-remote-extraction`.
- [ ] `--allow-remote-extraction` prints a one-screen disclaimer + requires the operator to type `acknowledge` to proceed.
- [ ] bats test `tests/scripts/graphify-local-only.bats` asserts the env var is set in the default path.

### AC-5 — Audit + drift integration
- [ ] `daily-supply-chain-audit` extended `check_versions()` to verify `graphifyy` is at the pinned version when installed.
- [ ] `check_min_release_age` covers `graphifyy` releases like every other operator tool.
- [ ] `.graphifyignore` schema validated by a bats test (must not be empty; must include `.git/`, `node_modules/`, `external/`).

### AC-6 — Pilot success criteria
After ≥ 30 days of operator use, decide on promotion to default profile. Success = TRUE iff:

- [ ] Operator self-reports ≥ 5 cases where Graphify saved tokens vs. `rg` + file reads.
- [ ] Graphify never produced a result that contradicted the actual repo state in a way that confused the operator.
- [ ] No security incidents (data leak, dependency CVE, etc.) tied to Graphify.

If success, file follow-up issue to evaluate the Graphify MCP server for default-profile inclusion (separate from `pentest` profile spec #27 work).

### AC-7 — Docs
- [ ] `docs/operational/graphify-runbook.md` (new) — the canonical operator
  runbook for the Graphify integration. (Earlier draft proposed
  `graphify-pilot.md` as a temporary pilot-period name; using `runbook` from
  the start avoids a rename later when the pilot concludes.)
  - Setup steps (one paragraph)
  - Privacy boundary diagram (what stays local, what may go to the LLM)
  - When to use Graphify vs `rg` vs reading files directly
  - Pilot success-criteria checklist for operator self-reporting
- [ ] CHANGELOG entry under `[Unreleased] → Added (optional / opt-in)`.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Operator opts in to Graphify for a specific repo                  │
│  $ walter-os graphify init                                         │
│     ├─► uv tool install graphifyy==<pinned>                        │
│     ├─► writes .graphifyignore (D-5 defaults)                      │
│     ├─► appends graphify-out/ to .gitignore                        │
│     └─► prints setup summary                                       │
└────────────────────────────┬───────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────────┐
│  $ walter-os graphify build                                        │
│     ├─► export GRAPHIFY_LOCAL_ONLY=1   (D-6 hard gate)             │
│     ├─► graphify build $WALTER_OS_HOME                             │
│     │     → graphify-out/graph.json                                │
│     │     → graphify-out/graph.html                                │
│     │     → graphify-out/GRAPH_REPORT.md                           │
│     └─► prints elapsed + output size                               │
└────────────────────────────┬───────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────────┐
│  Operator (or agent) queries the graph                             │
│  $ walter-os graphify query "where is the approval-gate test?"     │
│  $ walter-os graphify path AGENTS.md hooks/approval-gate.sh        │
│  $ walter-os graphify explain matches_standing_approval            │
│                                                                    │
│  All read graphify-out/graph.json — no network round-trip.         │
└────────────────────────────────────────────────────────────────────┘
```

## Threat model

- **PHI / secrets leakage to model API.** D-5 default `.graphifyignore` excludes `.env*`, `secrets.env*`, `*.key`, `*.pem`, and any path under `~/sync/wiki/medical/` (PHI). D-6 `GRAPHIFY_LOCAL_ONLY=1` is the hard floor — operator types `acknowledge` to lift it.
- **Supply chain.** `graphifyy` PyPI package pinned to exact version, bumped only after `check_min_release_age` clears the new release. Same discipline as `elevenlabs-mcp` (PR #48) and `heygen-mcp` rejection (PR #76 — but Graphify HAS a real maintainer, unlike `heygen-mcp@0.0.3`).
- **Stale graph confuses agent.** `graphify build` is operator-initiated, so the graph can lag the repo by N days. Mitigation: `walter-os graphify status` reports last-build time + a warning if > 7 days old. Daily-audit `info` finding if > 30 days old.
- **MCP server adoption.** Deferred to AC-6 follow-up — only after the pilot proves value.

## Out of scope

- **Cross-repo graph aggregation** (graph of all operator projects in one view). Could be a Control Tower (Phase V) follow-up.
- **Auto-rebuild on git commit.** Operator-initiated only in v0.6.0. Hook-driven auto-rebuild is a follow-up if pilot proves value.
- **Graphify MCP server in default profile.** Per AC-6, decide after pilot.
- **Replacing the existing `walter-os audit` + `walter-os status` with Graphify queries.** Walter-OS skills stay authoritative; Graphify is a complementary view.

## Recommended PR ordering

1. AC-1 — `scripts/graphify/setup.sh` + `.graphifyignore` (no operator-facing CLI yet)
2. AC-2 — `scripts/graphify/build.sh` + `walter-os graphify build` subcommand
3. AC-3 — `walter-os graphify query/path/explain` subcommands
4. AC-4 — local-only enforcement + bats test
5. AC-5 — daily-audit integration
6. AC-7 — operator-facing docs + CHANGELOG
7. (After ≥ 30 days operator use) AC-6 evaluation issue

## Open questions for the operator

1. **Pinned version**: lock to `graphifyy==0.7.16` (latest at issue write-time)? Or pin to whatever version is current at PR open? Default proposed: latest at PR open, but `check_min_release_age` must clear it first.
2. **`.graphifyignore` should include `~/sync/wiki/medical/` explicitly even though it's outside the repo**: should the file ALSO mention this in a comment, OR rely on Graphify's "don't follow symlinks outside repo root" default? Default proposed: include the comment for operator clarity.
3. **`walter-os graphify` as a subcommand vs `walter graphify`**: which CLI surface? Default proposed: `walter-os graphify` (the agent-facing CLI), mirroring `walter-os audit` / `walter-os spend`.

## Refs

- Issue #31
- Graphify project: <https://github.com/safishamsi/graphify>
- Graphify install docs: <https://graphify.net/#install>
- PyPI: <https://pypi.org/project/graphifyy/> (v0.7.16 as of 2026-05-12)
- License: MIT
- Codex install path doc: `graphify install --platform codex`
- `skills/daily-supply-chain-audit/SKILL.md` `check_min_release_age` — the existing audit pattern this spec extends
- `mcp/servers.json` — the MCP catalog (Graphify MCP NOT added to either profile in v0.6.0)
