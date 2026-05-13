# 0009. Agent Trust Tiers

**Date**: 2026-05-11
**Status**: Proposed

## Context

`approval-gate.sh` (spec section 7, `docs/specs/multi-agent-autonomy.md`) is currently binary: an operation is either blocked and escalated to the operator, or it is allowed. It does not distinguish risk by agent.

The six Council agents have very different risk profiles:

| Agent | What it does | Blast radius |
|---|---|---|
| **triage** | Classifies events and creates Plane issues | Minimal: writes issues only, no code or infrastructure |
| **researcher** | Reads the web, ingests wiki sources, creates wiki pages | Low: the wiki is private and reversible |
| **coder** | Writes code on feature branches and opens PRs | Medium: PRs are visible, diffs are reversible, and it cannot merge |
| **reviewer** | Reads diffs and posts review comments | Low: read-only over code; write access only to PR comments |
| **janitor** | Runs lint, dependency bumps, stale-PR sweeps, and DR drills | Medium-high: can touch config files and open PRs that look mechanical but have real impact |
| **liaison** | Reads Council activity and writes digests | Low on infrastructure, high on information exposure: reads and writes text only |

With a binary approval gate, the operator receives the same amount of manual approval noise for a reviewer reading a diff as for a janitor deleting temporary files. That erodes attention on the blocks that actually matter.

The goal of trust tiers is to **reduce low-risk approval noise without weakening protections for high-risk operations**. A trust tier does not replace `approval-gate.sh`; it complements the gate with a question: "For this agent and operation category, is an implicit standing approval appropriate?"

## Decision

Define three tiers: `low`, `medium`, and `high`. Assign them to the six agents. The trust table defines which approval-gate categories, from section 7.1 of the autonomy spec, can be auto-approved by tier.

### Tier Assignments

| Agent | Trust tier | Rationale |
|---|---|---|
| triage | `medium` | Creates issues in Plane but never touches code or infrastructure. Non-destructive by design. |
| researcher | `medium` | Writes private, reversible wiki text. Never touches source code. |
| coder | `medium` | Writes code on feature branches and opens PRs. It cannot merge, so the blast radius is contained to the branch. |
| reviewer | `high` | Read-only over code; writes only PR comments and review approvals. The worst direct damage is approving a bad PR, and merge remains operator-only. |
| janitor | `low` | Touches config files, may remove files that only look temporary, and performs dependency bumps that can break builds. The name sounds harmless, but its real blast radius is medium-high. |
| liaison | `low` | The liaison has the largest exfiltration surface: it writes summaries to external channels such as Telegram, email drafts, and status reports. A compromised liaison is strategically worse than a compromised coder. The coder can only push to a feature branch, while the liaison can leak full Council activity summaries to uncontrolled channels. Low trust requires explicit operator approval for anything leaving the homelab. |

### Override Table by Tier

The categories come from section 7.1 of the autonomy spec. Tiers define **auto-allow overrides**: categories the tier may execute without an `approved-by-operator` label.

**Tier `high` auto-allows**, in addition to everything `medium` allows:

- `git-push-feature-branch`: push to `feature/*`, never to main, staging, or release.
- `gh-pr-create`: open PRs, but not merge them.
- `gh-pr-comment`: comment on PRs.
- `gh-pr-review-approve`: approve a PR. Merge remains operator-only.
- `read-any-file`: read any file. This is already allowed for all tiers, but high makes it explicit.
- `run-tests-linters`: run tests, linters, and formatters.

**Tier `medium` auto-allows**, in addition to everything `low` allows:

- `git-push-feature-branch`: push to `feature/*`.
- `gh-pr-create`: open PRs.
- `gh-pr-comment`: comment on PRs.
- `run-tests-linters`: run tests and linters.
- `write-source-files-feature-branch`: edit source files on feature branches, not main or staging.
- `write-wiki-pages`: create or edit private wiki pages.
- `create-plane-issue`: create Plane issues.

**Tier `low` auto-allows**:

- `read-any-file`
- `run-tests-linters`
- `gh-pr-comment`
- `create-plane-issue`

**Blocked for all tiers**, including `high`:

- `push-to-main-staging-release`: push to protected branches.
- `gh-pr-merge`: merge PRs.
- `force-push-any-branch`: force-push any branch.
- `modify-hooks`: edit `hooks/`, `AGENTS.md`, `install.sh`, or `mcp/servers.json`.
- `modify-agent-definitions`: edit `agents/*.md` or `skills/*/SKILL.md`.
- `destructive-shell`: `rm -rf`, `dd`, `mkfs`, `truncate`.
- `sql-destructive`: `DROP`, `TRUNCATE`, `DELETE FROM`.
- `http-delete-managed-services`: DELETE calls against Hetzner, Cloudflare, Stripe, Forgejo, or Vercel.
- `money-spending`: any provisioning or spending.
- `public-communication`: tweets, blog posts, or sent emails.
- `auth-crypto-phi-files`: `auth/*`, `crypto/*`, medical-data projects, `*.key`, `*.pem`.
- `env-file-writes`: any `*.env*` write.
- `production-db-migrations`: migrations against staging or production.

### Persistence

Each agent's trust tier lives in `~/.config/walter-os/trust-tiers.yml`:

```yaml
agents:
  triage:
    tier: medium
    overrides: {}     # empty = use tier defaults

  researcher:
    tier: medium
    overrides: {}

  coder:
    tier: medium
    overrides: {}

  reviewer:
    tier: high
    overrides: {}

  janitor:
    tier: low
    overrides:
      write-wiki-pages: allow    # janitor may clean up the wiki

  liaison:
    tier: low
    overrides:
      write-wiki-pages: allow    # liaison may write internal wiki digests
```

The `overrides` field allows agent-specific tuning without changing the tier. An `allow` override permits a category that the tier would normally block; a `block` override blocks a category the tier would normally allow. Overrides cannot unblock the "blocked for all tiers" list; that list is hardcoded in `approval-gate.sh`.

### Hot Reload

`approval-gate.sh` is a short-lived process invoked by the PreToolUse hook, not a daemon. It reads `trust-tiers.yml` on every invocation. Changes to the file take effect immediately without restart.

## Consequences

**What becomes easier**:

- The reviewer can work without approvals for operations that are already part of its normal function, such as pushing to feature branches and opening PRs. The operator receives fewer interruptions.
- The trust model is auditable: a readable YAML file the operator can review and modify.
- Overrides allow per-agent trust tuning without redesigning the tier system.
- The "blocked for all tiers" list keeps core security guarantees intact regardless of tier.

**What becomes harder**:

- The low-trust janitor may need more manual approvals than before. If the operator adds `write-source-files-feature-branch: allow` to the janitor override, it reduces noise but raises the risk that janitor modifies files outside its expected role.
- The override table can grow over time and become a complex exception system. Mitigation: quarterly review of the janitor agent, already covered in autonomy spec section 7.5.

**Accepted risks**:

- The reviewer's `high` tier allows feature-branch pushes without approval. If the reviewer has a bug and writes code instead of only reviewing, it can push code to an operator branch. Risk is low because the reviewer cannot merge, PRs still require operator review before merge, and the audit log records all pushes.
- Tiers are static. There is no automatic trust downgrade if an agent behaves badly. Downgrade is a manual operator action through YAML edits. This is intentional: trust should be a conscious operator decision, not an algorithmic output.

## Alternatives Considered

**Trust based on behavior history**:

- Idea: an agent's trust tier automatically increases after N incident-free tasks and decreases after approval-gate blocks.
- Rejected: this creates an exploitable feedback loop. An agent could complete many simple tasks to increase trust, then attempt a risky operation. Trust should be a declarative property of the agent role, not a product of past behavior.

**Trust per individual operation, not by tier**:

- Idea: each agent has an explicit list of allowed operations, with no tier concept.
- Rejected: too granular to maintain. With six agents and fourteen categories, this creates up to eighty-four combinations. Tiers collapse this into three defaults plus exception overrides. The extra complexity does not justify the granularity.

**Trust delegated to the Plane issue**:

- Idea: an operation's trust level is determined by Plane issue labels, for example `trust:high`.
- Rejected: this mechanism already exists as the `approved-by-operator` label. Trust tiers are orthogonal: they define the agent role independently of the specific task. Mixing both creates precedence ambiguity.

**No tiers; expand existing standing approvals only**:

- Idea: use the existing standing approvals mechanism from autonomy spec section 7.5 instead of adding a new abstraction.
- Rejected: standing approvals are global and apply to all agents. They cannot express "standing approval for feature-branch pushes only for the reviewer." Tiers solve exactly this per-agent scoping problem.
