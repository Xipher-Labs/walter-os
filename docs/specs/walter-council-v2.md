# Walter Council v2

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Plane**: ticket to be filed

## Problem

Walter Council v1 works, but it is blind to its own health, slow to recover from failures, and disconnected across its moving parts. The six agents execute tasks in Plane, write to the wiki, and post to Telegram, but there is no single place to see what they are doing, how much they spend, or what one agent learned that another agent should know.

When an agent dies mid-task, the Plane issue stays `claimed` indefinitely. There is no heartbeat, no watchdog, and no re-enqueue path. The operator usually discovers the problem only when the morning digest never arrives. Token spend is visible in LiteLLM, but there is no attribution by agent or task. Agent memory is siloed: the reviewer may learn that an auth pattern is unsafe, while the coder repeats it in the next issue.

The practical result is that the operator still has to babysit the Council. The burden is different from v1, but the attention cost remains high. Real autonomy requires real observability, failure recovery, and a conversational channel where the operator can talk with the Council, not only receive notifications from it.

## Proposed Solution

Walter Council v2 is a set of nine infrastructure improvements to the existing Council, plus a new visual and conversational interface named **Control Tower**. The improvements are grouped into four layers:

- Observability and cost: Improvements 1-2.
- Memory and collective intelligence: Improvements 3-4.
- Operational resilience: Improvements 5-6.
- Autonomy controls: Improvements 7-9.

Control Tower is the operations surface that brings those layers together in one place.

The improvements are incremental and non-breaking. Each can be implemented and deployed independently. Implementation order follows the critical path that produces observable value fastest.

---

## Improvement 1: Council Observability (Prometheus + Grafana)

### Problem Statement

There is no first-class telemetry for Council work. The operator can open the LiteLLM dashboard or grep the audit log, but there is no unified panel showing how many tasks ran today, spend by agent, approval-gate blocks, or which agent is in which state.

### Proposed Solution

Expose Prometheus metrics from the agent runner (`scripts/agents/`) and create a Grafana dashboard that combines these metrics with existing LiteLLM panels.

New metrics under the `walter_council_` namespace:

| Metric | Labels | Description |
|---|---|---|
| `walter_council_tasks_total` | `agent`, `result` (`success`, `failed`, `needs_operator`) | Counter for completed tasks by agent and result |
| `walter_council_tokens_total` | `agent`, `model` | Counter for consumed tokens, input plus output |
| `walter_council_approvals_total` | `agent`, `category`, `outcome` (`blocked`, `allowed_operator`, `allowed_standing`) | Counter for approval-gate events |
| `walter_council_task_duration_seconds` | `agent` | Histogram for task duration from claim to done or failed |
| `walter_council_agent_state` | `agent`, `state` (`idle`, `working`, `blocked`) | Gauge for each agent's current state |
| `walter_council_heartbeat_age_seconds` | `agent` | Gauge for seconds since last heartbeat; used by Improvement 5 |

The agent runner writes metrics to a Prometheus textfile at `/var/lib/walter-council/metrics.prom`. Node Exporter's `textfile_collector` exposes it. The runner does not gain a new HTTP server.

### Acceptance Criteria

- [AC-1] `curl walter-vm:9100/metrics | grep walter_council_tasks_total` returns the metric with correct labels after any task runs.
- [AC-2] Grafana dashboard "Walter Council" exists on walter-vm Grafana with at least six panels: tasks/day, tokens/agent, task success rate, approval-gate heatmap, agent state, task duration P95.
- [AC-3] Metrics survive agent-runner restarts because the `.prom` file persists.
- [AC-4] `walter-os agents status` shows current-day metrics in text format without requiring Grafana access.

---

## Improvement 2: Cost Attribution per Agent

### Problem Statement

LiteLLM records spend, but current tags do not include `agent_id` or `task_id`. The operator cannot tell whether monthly cost came from coder or researcher, nor which specific task burned through a large amount in one run.

### Proposed Solution

Add `agent_id`, `task_id`, and `context` tags to every LLM call through LiteLLM metadata. `llm.sh` already supports metadata, but not all tags. Connect LiteLLM's `/spend/tags` endpoint to a new `walter-os spend report` command.

Each call expands metadata from `{agent: $agent}` to `{agent_id: $agent, task_id: $task_id, context: $context, model_alias: $model_tag}`.

LiteLLM already groups spend by tags through `LiteLLM_SpendLogs`. The report queries it through the LiteLLM API: `GET /spend/tags?start_date=...&end_date=...&tags=agent_id`.

### Acceptance Criteria

- [AC-1] Every call in `llm.sh` includes `task_id` from `$WALTER_AGENT_PLANE_ISSUE` and `context` from `$WALTER_AGENT_CONTEXT` in metadata.
- [AC-2] `walter-os spend report --by-agent --last 7d` prints a table: agent, model, input tokens, output tokens, cost USD, sorted by descending cost.
- [AC-3] `walter-os spend report --by-task --last 7d` prints the top 20 most expensive tasks with issue ID, agent, model, and cost.
- [AC-4] If any agent exceeds its daily budget in the last 24 hours, `status` output shows a warning and emits a `warn` alert, as defined in Improvement 8.

---

## Improvement 3: Memory Consolidation — Wiki Weekly Job

### Problem Statement

The wiki grows without pruning. Similar pages are created about the same topic, definitions conflict, and old pages with no inbound links add noise to prompt context.

### Proposed Solution

A weekly job runs on walter-vm every Sunday at 02:00. It invokes the janitor agent with a consolidation skill. The job does three things in order:

1. **Dedupe**: uses embeddings (`bge-small-en-v1.5` through standby homelab node Ollama or GPU inference node vLLM) to detect pages with cosine similarity above 0.92. It proposes merges but never executes them. It outputs JSON candidate reports and posts them to Plane issue `wiki:consolidation`.
2. **Contradictions**: uses a cheap LLM to review pairs of pages about the same concept and detect conflicting definitions. It marks the oldest page with a `[CONTRADICTION]` comment.
3. **Pruning**: marks pages with `last-modified > 180 days AND no inbound links` as `[STALE]` in frontmatter. It never deletes pages; the operator confirms deletion.

The job always produces proposals, never irreversible actions.

### Acceptance Criteria

- [AC-1] The job runs without errors on walter-vm at 02:00 on Sundays. Logs land at `/var/log/walter-council/wiki-consolidation.log`.
- [AC-2] After running on a wiki with at least 20 pages, it generates at least one candidate report, even if empty.
- [AC-3] The dedupe candidate JSON includes `page_a`, `page_b`, `similarity_score`, and `reason`. It is posted as a Plane issue with label `wiki:consolidation`.
- [AC-4] Pages marked `[STALE]` are not deleted automatically. They require explicit operator action: `walter-os wiki prune --confirm`.
- [AC-5] The job completes within 10 minutes on a wiki with up to 200 pages, measured in a manual test.

---

## Improvement 4: Cross-Agent Learning Broker

### Problem Statement

Each agent stores lessons in `~/sync/agent-memory/<agent>/`. If reviewer learns that an auth pattern is unsafe, coder may still repeat it because it cannot access reviewer's lessons. Agents learn in silos.

### Proposed Solution

Create a centralized lessons broker: a SQLite index at `~/.config/walter-os/lessons.db` with this schema:

```sql
CREATE TABLE lessons (
  id           TEXT PRIMARY KEY,
  source_agent TEXT NOT NULL,
  tags         TEXT,           -- JSON array of strings
  headline     TEXT NOT NULL,  -- short phrase, <= 120 chars
  body         TEXT,           -- full detail
  embedding    BLOB,           -- float32[] vector, 384-dim (bge-small)
  context      TEXT,           -- context:work / context:projects-personal / etc.
  created_at   TEXT NOT NULL,
  confidence   REAL DEFAULT 1.0
);
```

**Write path**: when an agent finishes a task and finds something worth remembering, it calls `lesson_write <headline> <body> <tags>` from a new `scripts/agents/lib/lessons.sh`. The script computes the local embedding and writes to the DB.

**Read path**: before any agent invokes an LLM for a task, `lesson_query <task_description> <agent_name>` retrieves the top five lessons by cosine similarity, filtered by context when relevant. Relevant lessons are injected into the agent system prompt under `## Lessons from the Council`.

**Embedding architecture across peers**:

- When the agent runs on the standby homelab node, because the operator is near the active local peer, embeddings use the local Ollama `nomic-embed-text` service. Expected latency is about 10 ms, with no cache needed.
- When the agent runs on Walter-VM, because the operator is remote or during failover, embeddings use CPU-based service on Walter-VM plus Redis cache for frequent requests. Expected latency is up to 500 ms, accepted by the operator.

The standby homelab node is not a passive backup. It is an **active peer** that runs the Council when the operator is near the local node. Synchronization between standby homelab node and Walter-VM for lessons DB, wiki, and Plane state uses **eventual consistency with Last-Write-Wins**: Syncthing for files, Postgres logical replication for state. See `docs/specs/archive/standby-node-replication.md`.

This does not depend on Anthropic APIs.

**Limit**: maximum five lessons per invocation, maximum 800 tokens. Lessons with confidence below 0.5 are not injected. Feedback mechanism: the operator can lower confidence on incorrect lessons through `walter-os lessons rate <id> <score>`.

### Acceptance Criteria

- [AC-1] `lessons.db` exists in `~/.config/walter-os/` after the first execution of any agent with the new library.
- [AC-2] After reviewer writes a lesson about an auth pattern, coder receives it in the next relevant task as part of the system prompt. Verification: `--dry-run` prints the resulting system prompt.
- [AC-3] `walter-os lessons list --agent reviewer --last 30d` lists reviewer lessons with headline, tags, and date.
- [AC-4] `walter-os lessons rate <id> 0.0` lowers confidence to zero; the lesson stops being injected. Verification uses the same `--dry-run`.
- [AC-5] Lesson query adds no more than 500 ms to any task startup. On standby homelab node, target is no more than 50 ms. On Walter-VM, target is no more than 500 ms. The remote latency is operationally acceptable.

---

## Improvement 5: Failure Recovery — Heartbeat + Zombie Watchdog

### Problem Statement

When an agent dies mid-task, because of OOM, network drop, LLM timeout, or process crash, the Plane issue stays `claimed` indefinitely. Nothing detects it. The operator discovers it manually days later.

### Proposed Solution

Three coordinated pieces:

**A — Heartbeat**: the agent runner (`scripts/agents/run.sh`) writes a heartbeat every 60 seconds to `/var/lib/walter-council/heartbeats/<agent>/<issue_id>.heartbeat` with ISO-8601 timestamp and progress checkpoint. The heartbeat is append-only JSONL.

**B — Zombie watchdog**: a walter-vm cron runs `scripts/agents/watchdog.sh` every 5 minutes. The script:

1. Lists all Plane issues in `claimed`.
2. Finds the corresponding heartbeat file for each.
3. Declares the issue zombie if the heartbeat file is missing or if `now - last_heartbeat_ts > 30min`.
4. Posts a Plane comment: "Agent declared zombie after 30min without heartbeat. Re-enqueueing."
5. Transitions the issue back to `ready` and clears the assignee.

**C — Checkpoint serialization**: heartbeat JSONL acts as a checkpoint. When the watchdog re-enqueues an issue, the next agent reads the latest heartbeat to know where to resume. The checkpoint uses a simple `completed_steps: [...]` key where each item is a plan subtask name.

### Acceptance Criteria

- [AC-1] While an agent runs a task, the heartbeat file updates every 60 seconds. Verify with `watch -n 5 cat /var/lib/walter-council/heartbeats/<agent>/<issue_id>.heartbeat`.
- [AC-2] Killing an agent process mid-task results in watchdog detection within 35 minutes, a Plane comment, and issue transition back to `ready`.
- [AC-3] Watchdog log at `/var/log/walter-council/watchdog.log` records every zombie detection with timestamp, agent, and issue ID.
- [AC-4] When a second agent takes the re-enqueued issue, it can read the checkpoint and knows which steps were already completed. The claim comment says: "Resuming from checkpoint: steps [X, Y] already done." The heartbeat persists `completed_steps`. `files_touched` and `tests_run` remain stub fields (`[]` and `0`) until Phase U adds tool-call instrumentation hooks. **PARTIAL**: `completed_steps` implemented; file and test tracking deferred.
- [AC-5] `walter-os agents status` includes a "Zombies detected (last 7d): N" section.

---

## Improvement 6: Project Induction Skill

### Problem Statement

When a new project is created, the operator must manually populate context: repo `AGENTS.md`, first spec, first Plane epic, and non-negotiable rules. The process is inconsistent. Sometimes `AGENTS.md` is missing, the spec is incomplete, or the first epic is never created. Agents working in the new project lack context from day one.

### Proposed Solution

Add a `project-induction` skill invoked through `walter new project <type> <name>`. It guides the operator through a 7-9 minute interview with structured questions:

1. What does this project do? Answer in two or three user-language sentences.
2. What is the primary technical stack?
3. What rules are non-negotiable, such as security, compliance, or performance?
4. Which three KPIs define success in six months?
5. Which external integrations are critical, such as APIs, MCPs, or services?
6. Who are the users? Include profile and expected volume.
7. What is most likely to go wrong?
8. Does the project involve PHI, financial data, or legally sensitive data?
9. What is the path to market: deploy, distribution, sales, or adoption?
10. Which Council agents will work here? Are any restricted?
11. What is the branching strategy? Are there feature flags or environments?
12. Is there a hard deadline or critical milestone soon?

Induction output:

- `docs/specs/<slug>-project-charter.md` with problem, stack, KPIs, and constraints.
- Repo `AGENTS.md` with project-specific rules.
- First Plane epic with 5-8 bootstrap tasks: repo setup, CI, first feature, first spec.
- `wiki/projects/<name>.md` entry with charter summary.

### Acceptance Criteria

- [AC-1] `walter new project webapp my-app` starts the interactive terminal interview. With `--non-interactive`, it reads answers from YAML.
- [AC-2] After the interview, `docs/specs/my-app-project-charter.md` exists and contains every charter field populated from answers.
- [AC-3] After completion, the new repo root contains `AGENTS.md` with at least stack, non-negotiable rules, enabled/restricted agents, and KPIs.
- [AC-4] Plane epic "Bootstrap: my-app" is created with at least five tasks. Verify through `walter-os agents status` or the Plane UI.
- [AC-5] If the operator answers yes to PHI, generated `AGENTS.md` includes `medical-data-compliance` rules automatically. If the operator answers yes to financial data, generated `AGENTS.md` includes a TODO block noting that the `financial-data-compliance` skill is pending. Until that skill exists, the operator must manually confirm financial operations. The skill itself is deferred; see `docs/specs/financial-data-compliance.md` (TBD).

---

## Improvement 7: Trust Calibration per Agent

### Problem Statement

The approval gate is currently binary. It does not distinguish between a read-only, low-risk reviewer and a janitor that edits config and can cause real damage. This creates two problems: the operator receives unnecessary approvals for low-risk reviewer actions, and janitor receives the same autonomy as reviewer in categories where it should have less.

### Proposed Solution

Introduce `trust_tier` per agent (`low`, `medium`, `high`) and an override table defining which approval-gate categories each tier can auto-approve. See ADR `0009-agent-trust-tiers.md` for the complete decision.

The trust table persists in `~/.config/walter-os/trust-tiers.yml` and is read by `approval-gate.sh` before deciding block or allow.

### Acceptance Criteria

- [AC-1] Every agent has a `trust_tier` in `trust-tiers.yml`. Initial values match ADR-0009.
- [AC-2] Reviewer, with high trust, can run `git push origin feature/*` without operator approval. Verify through `approval-gate.sh check "git push origin feature/test" --tool Bash` with `WALTER_AGENT_NAME=reviewer`.
- [AC-3] Janitor, with low trust, still requires approval for `rm -rf` outside `/tmp`. Verify with the same check.
- [AC-4] `walter-os agents trust <agent>` shows the tier and list of auto-approved categories for that agent.
- [AC-5] Changing an agent's `trust_tier` in `trust-tiers.yml` immediately changes gate decisions without restart.

---

## Improvement 8: Hierarchical Failure Mode Signaling

### Problem Statement

All Council alerts currently go to the same Telegram bot with the same format. A dependency bump notice looks as urgent as runaway LLM spend or a critical MCP CVE. The operator must read everything to avoid missing critical events.

### Proposed Solution

Four signaling tiers with different notification paths:

| Tier | Description | Channel | Effect on Council |
|---|---|---|---|
| `info` | Routine operation, no action required | Local log only at `/var/log/walter-council/events.log` | None |
| `warn` | Something anomalous but tolerable; operator should know | Telegram without interruption | None |
| `critical` | Real failure or exceptional spend; requires prompt attention | Telegram with special format + Control Tower flag | None |
| `panic` | Security event or runaway condition; requires immediate human intervention | Telegram + email + red Control Tower flag + automatic Council pause + approval-gate lock until operator `/unlock` | Council paused, gate blocked |

Events and tiers:

| Event | Tier |
|---|---|
| Task completed successfully | `info` |
| Dependency bump available | `info` |
| Task re-enqueued by watchdog | `warn` |
| Agent daily budget 80% consumed | `warn` |
| Approval gate blocked an operation | `warn` |
| Task failed after two retries | `critical` |
| Agent daily budget exceeded | `critical` |
| CVE CVSS >= 7 detected by supply-chain audit | `panic` |
| MCP tool-name shadowing detected | `panic` |
| Runaway spend: monthly spend > 200% of baseline | `panic` |
| Agent attempted to modify hooks or AGENTS.md | `panic` |

The function `alert_emit <tier> <message> <context_json>` in `scripts/agents/lib/alerts.sh` is the single entrypoint for all events. Agents and scripts call it instead of posting directly to Telegram.

### Acceptance Criteria

- [AC-1] `alert_emit info "task completed" '{}'` writes only to the local log and does not reach Telegram.
- [AC-2] `alert_emit warn "budget 80% consumed" '{}'` sends a Telegram message prefixed with `[WARN]` and does not pause the Council.
- [AC-3] `alert_emit panic "CVE detected" '{}'` sends Telegram + email to the operator, pauses the Council by creating the pause flag, and makes `approval-gate.sh` block all operations until the operator runs `walter-os agents unlock --reason "..."`.
- [AC-4] Event log at `/var/log/walter-council/events.log` is append-only JSONL with timestamp, tier, message, and context.
- [AC-5] `walter-os agents unlock --reason "CVE triaged, not exploitable in our setup"` lifts the panic lock and records the reason in the event log.

---

## Improvement 9: Council Consensus Mode

### Problem Statement

When the operator is unavailable, tasks requiring human approval accumulate in `needs-operator`. The Council can often determine that routine tasks are safe to approve, but there is no formal mechanism. The operator returns to a large approval queue that could have been reduced automatically without meaningful risk.

### Proposed Solution

Add a global `consensus` mode enabled with `walter-os mode consensus on` and disabled with `walter-os mode consensus off`. It persists in `~/.config/walter-os/mode.json`:

```json
{
  "consensus": true,
  "since": "2026-05-11T14:00:00Z",
  "voting_threshold": 3
}
```

When consensus mode is on:

Tasks that normally require human approval for `info` or `warn` tiers move to an automatic **Council Vote**. Eligible examples include lint fixes, non-major dependency bumps, doc updates, wiki edits, small refactors, formatting, comment changes, and tests-only PRs.

Voting flow:

1. Task enters `awaiting-consensus` in Plane.
2. The three most relevant agents for the task, selected from Plane issue tags, receive this prompt: "Should this task be auto-approved? Respond yes/no with a one-sentence reason."
3. If at least two of three vote yes, the task executes. If one or fewer vote yes, it escalates to `awaiting-human` with Council comments attached.
4. Explicit audit trail: each consensus-approved action receives a Plane comment: `approved by council consensus 3/3 (researcher, reviewer, coder) at <timestamp>. dissent: none.`

Tasks that are never eligible for consensus:

- Any `critical` approval-gate operation: auth, money, PHI, schema changes, production deploys, or security work.
- Any category in the ADR-0009 "blocked for all tiers" list.
- Major dependency bumps. Only minor and patch bumps are eligible.
- Changes to `hooks/`, `AGENTS.md`, `install.sh`, or `mcp/servers.json`.

When consensus mode is off, the current behavior remains: anything requiring human approval waits for the human.

Operator experience on return:

- Run `walter-os mode consensus off`.
- Run `walter-os agents summary --since <last-checkin>`.
- The summary shows how many tasks Council approved by consensus, how many wait for human approval, and how many failed consensus, with links to Plane discussions.

### Acceptance Criteria

- [AC-1] `walter-os mode consensus on` creates or updates `~/.config/walter-os/mode.json` with `consensus: true` and timestamp. `walter-os mode consensus status` displays it. `walter-os mode consensus off` reverts it.
- [AC-2] In consensus mode, a lint-fix task with tier `info` in Plane goes to `awaiting-consensus` instead of `needs-operator`. Dry-run prints "entering consensus voting" instead of "escalating to operator".
- [AC-3] With at least two of three yes votes, the task moves from `awaiting-consensus` to `ready`, then execution. Attached Plane comment includes individual votes and reasons.
- [AC-4] A production DB schema migration in consensus mode goes directly to `awaiting-human`, never `awaiting-consensus`. Verify through `approval-gate.sh check "psql migration" --tool Bash`, which returns block reason `consensus-ineligible: prod-db-migration`.
- [AC-5] `walter-os agents summary --since 2026-05-10` prints total consensus-approved tasks, total `awaiting-human`, total consensus failures, and links to Plane issues.
- [AC-6] The consensus-mode toggle is visible in Control Tower's Mode Indicator with the number of auto-approved tasks since activation.

---

## Part B: Control Tower

### Problem Statement

Walter Council operates in the dark from the operator's perspective. Alerts arrive in Telegram, while system state is spread across Plane, Grafana, the audit log, and the LiteLLM dashboard. To know what is happening right now, the operator must open four separate windows. There is no single surface where "see the Council" and "talk with the Council" happen together.

Control Tower is the Council's operational interface: a web dashboard on Walter-VM, Tailscale-only, single user. It shows realtime agent state, embedded metrics, costs, HA state, active alerts, and also provides a conversational mode where the operator can ask the Council to think through a topic together.

### Proposed Solution

A Next.js 15 App Router web app deployed on walter-vm as a Docker container. See ADR `0008-control-tower-stack.md` for stack rationale.

Visual modules:

- **Agent Status Board**: realtime state of the six agents (`idle`, `working`, `blocked`), current task, and time in state. Updates through WebSocket.
- **Decision Timeline**: log of Council decisions, including what executed, what blocked, what approved, with links to Plane issues and commits.
- **Metrics Dashboard**: embedded Grafana panels from Improvement 1. Metric UI is not duplicated.
- **Cost Dashboard**: spend report from Improvement 2, with sparklines by agent.
- **HA Status**: walter-vm vs standby homelab node state, based on `standby-node-hetzner-replication.md`. Green/red by service.
- **Alert Feed**: active alerts with tier (`info`, `warn`, `critical`, `panic`) and acknowledge button.
- **Mode Indicator**: consensus mode state, ON/OFF toggle, and count of auto-approved tasks since last activation.

Conversational modules:

- **Council Chat**: the operator enters a topic or question. The Council responds with a three-phase hybrid flow:
  1. **Round 1 — parallel groupthink**: all six agents receive the operator prompt and respond independently, without seeing each other's answers. Outputs are short, up to 300 tokens each. Goal: capture perspectives without cross-contamination.
  2. **Round 2 — sequential deliberation**: each agent receives all six Round 1 responses and produces a longer answer that refines its position, cites or refutes other agents by name, and proposes explicit trade-offs. Round 2 order is descending trust tier (`high` → `medium` → `low`) so lower-trust agents do not dominate early discourse.
  3. **Synthesis**: `liaison` reads all twelve responses and produces a summary with convergent positions, open disagreements, recommended path forward, and actionable next steps. The summary includes a "Spin this as spec + plan" button that invokes the architect agent.
  Council Chat is not a general-purpose chat. It is specifically for structured Council deliberation.
- **Ideation Session**: assisted brainstorm mode. The operator proposes an idea, the Council deliberates with the same three-phase flow, and the final summary includes a "Spin this as spec + plan" button to invoke architect for formal spec creation.
- **Conversation History**: searchable by date, topic, and agent.

### Acceptance Criteria

- [AC-1] Control Tower is accessible at `https://tower.${WALTER_DOMAIN}` through Tailscale only. No tailnet access returns 403.
- [AC-2] Agent Status Board updates within 2 seconds when an agent changes state, for example `idle` to `working`. Verify by starting a `run-once` and observing the board.
- [AC-3] Decision Timeline shows the last 50 audit-log events with working Plane links.
- [AC-4] Grafana panels from Improvement 1 are visible in Metrics without additional login, through Grafana anonymous embed or backend API key.
- [AC-5] Cost Dashboard loads last-seven-day spend by agent within 3 seconds.
- [AC-6] HA Status correctly reflects whether walter-vm and standby homelab node are healthy or degraded, using the same health check as Cloudflare Load Balancer.
- [AC-7] In Council Chat, the operator sends a message and the three-phase flow completes within 90 seconds: Round 1 visible within 30 seconds, Round 2 visible within 75 seconds, liaison synthesis visible within 90 seconds. UI shows visible progress for each phase.
- [AC-8] In Ideation Session, clicking "Spin as spec + plan" creates a Plane issue in `lane:code` with session summary as description, and architect takes it in the next polling cycle.
- [AC-9] Control Tower starts in under 5 seconds from cold app start when the container is already running.
- [AC-10] All Council Chat calls go through LiteLLM, not directly to Anthropic API. Verify in LiteLLM logs.

---

## Wiki Normalization (Prerequisite for Phase M)

### Problem Statement

Wiki pages are growing without a consistent frontmatter schema. Some lack `type`, some use free-form strings for `last-modified`, and some omit fields required by the cross-agent learning broker. The broker uses frontmatter to filter by context; broken frontmatter produces incorrect queries.

### Proposed Solution

Add `scripts/wiki/normalize-frontmatter.sh` as a prerequisite before Phase M. The script scans `~/sync/wiki/**/*.md`, validates YAML frontmatter against `wiki/SCHEMA.md`, and applies automatic fixes where safe: default fields and type inference from path, such as `people/*` → `type: person` and `projects/*` → `type: project`. Pages that cannot be auto-normalized are reported for human review and are not silently modified.

The script is also installed as a hook for future wiki writes. See the required `AGENTS.md` amendment below: no wiki write may occur without frontmatter validation.

---

## Required AGENTS.md Amendments

The implementer must add this block to the global `<operator-home>/Projects/walter-os/AGENTS.md`, in "Universal disciplines", as a new subsection between "Wiki integrity" and the next existing section:

```markdown
### Wiki integrity (mandatory)

- Every write to `~/sync/wiki/**` MUST validate frontmatter YAML against
  `wiki/SCHEMA.md` BEFORE the write. The `wiki-validator.sh` hook enforces this.
- Pages with broken frontmatter are rejected. No silent fixes — the agent
  must repair frontmatter explicitly and re-attempt.
- Cross-links use the `[[page-slug]]` format. Broken links fail the write.
- Type inference is allowed from path (e.g. `people/*` → type: person) but
  must be made explicit in frontmatter, not implicit.
```

This amendment is part of implementation and is not optional. Task `T-M-1` in the plan covers it.

---

## Non-Goals

- Voice, wake-word, TTS, and STT. Those belong to local voice assistant on standby homelab node in Phase L. Control Tower is text-only.
- New MCPs. v2 does not add MCPs to the stack.
- New agents. The current six remain. Control Tower can expand to support more agents in v3 if needed.
- Auto-merge for PRs. Merge remains operator-only. Control Tower does not include a merge button.
- Multi-user access. One operator, one instance, no multi-tenant auth.
- Mobile app. Telegram remains the mobile channel. Control Tower is desktop browser.
- Alerts to channels other than Telegram + email. No Slack, PagerDuty, or others are added.

## Open Questions

- For the lessons broker embedding model, use `bge-small-en-v1.5` or `nomic-embed-text`? The first is smaller at 33M parameters; the second is already configured in LiteLLM as `local-embed` on standby homelab node. Recommendation: use `nomic-embed-text` because it is already deployed, but it requires standby homelab node to be up.
- Should Ideation Session automatically save the full transcript to the wiki, or only the operator-approved summary? Recommendation: summary only by default to avoid wiki pollution.

## References

- `docs/specs/multi-agent-autonomy.md`: Walter Council v1, base for this spec.
- `docs/specs/homelab-topology.md`: four-node architecture and where each component runs.
- `docs/specs/archive/standby-node-replication.md`: HA status displayed in Control Tower.
- `docs/decisions/0008-control-tower-stack.md`: Control Tower stack ADR.
- `docs/decisions/0009-agent-trust-tiers.md`: trust-tier ADR.
- `hooks/approval-gate.sh`: gate extended by Improvements 7 and 8.
- `scripts/agents/lib/llm.sh`: LLM invocation extended by Improvement 2.
- `scripts/agents/main.sh`: CLI extended with new subcommands.
