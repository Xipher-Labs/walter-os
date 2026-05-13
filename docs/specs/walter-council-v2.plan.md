# Implementation Plan: walter-council-v2

Spec: `docs/specs/walter-council-v2.md`

## Phases

```
Phase F — Foundation: Observability + Cost Attribution (T-1 to T-8)
Phase M — Memory + Intelligence: Wiki Normalization + Consolidation + Learning Broker (T-M-0, T-M-1, T-9 to T-16)
Phase R — Resilience: Recovery + Induction (T-17 to T-24)
Phase T — Trust + Controls: Tiers + Signaling + Consensus Mode (T-25 to T-36c)
Phase U — UI: Control Tower (T-35 to T-54)
```

Note: Phase T tasks were renumbered when consensus mode replaced vacation mode and expanded from 3 to 8 tasks. Phase U tasks shifted accordingly (T-35 scaffold → T-37 scaffold in this plan). The original T-35 through T-52 numbering is preserved in Phase U with a +2 offset; T-53 and T-54 are new tasks for consensus mode UI integration.

**Critical path to v0 usable Control Tower**: F → partial U (T-35 to T-42).
R and M can run in parallel with U after F is done.

**Dependency map**:
- T-1 through T-8 (Phase F) have no dependencies on other phases.
- T-9 through T-16 (Phase M) depend on T-1 (metrics file exists) and T-5 (spend report).
- T-17 through T-24 (Phase R) depend on T-1 and T-8 (alert_emit exists).
- T-25 through T-36c (Phase T) depend on T-8, T-17, and T-22 (plane.sh helpers). Consensus tasks T-32 through T-36c additionally depend on T-22.
- T-35 through T-54 (Phase U) depend on T-1, T-5, T-8, T-25, and T-32 (all Phase F + trust tier + consensus mode).

---

## Phase F — Foundation: Observability + Cost Attribution

**Estimated effort**: 10–14 hours

---

### T-1: Prometheus metrics writer [AC-1, AC-3 of Improvement 1]

- File: `scripts/agents/lib/metrics.sh` (new)
- Change: Bash library with functions `metric_inc <name> <labels> <value>` and `metric_set <name> <labels> <value>`. Writes to `/var/lib/walter-council/metrics.prom` in Prometheus text format. Uses file locking (`flock`) to avoid concurrent write corruption. Includes a `metrics_init` call that sets all known metrics to 0 if the file doesn't exist (prevents missing metrics in Grafana).
- Verify: Unit test in `tests/agents/metrics.bats` — call `metric_inc walter_council_tasks_total 'agent="coder",result="success"' 1`, then grep the output file for the expected line. Run twice and verify the counter accumulates.

### T-2: Wire metrics into agent runner [AC-1 of Improvement 1]

- File: `scripts/agents/run.sh` (modify — task start, task end, approval-gate event hooks)
- Change: Source `lib/metrics.sh` at top. At task start: `metric_set walter_council_agent_state 'agent="$AGENT"' 1` (working). At task end: `metric_inc walter_council_tasks_total` + `metric_inc walter_council_tokens_total` (using token count from LLM response). At task done/failed: restore `agent_state` to 0 (idle). Heartbeat loop (for Improvement 5) also updates `walter_council_heartbeat_age_seconds`.
- Depends on: T-1
- Verify: Run `walter-os agents run-once researcher --issue <test-issue-id> --dry-run`. Grep `/var/lib/walter-council/metrics.prom` for `walter_council_agent_state{agent="researcher"}` == 1 during run, 0 after.

### T-3: Node Exporter textfile_collector wiring [AC-1 of Improvement 1]

- File: `setup/vm/services/node-exporter/compose.yml` (modify) + `setup/vm/services/node-exporter/README.md` (modify)
- Change: Add `--collector.textfile.directory=/var/lib/walter-council` to the Node Exporter command. Add volume mount so the container sees that path. Document the expected file permissions (node-exporter user must read `metrics.prom`).
- Depends on: T-1
- Verify: `curl walter-vm:9100/metrics | grep walter_council` returns at least one metric after a test agent run.

### T-4: Grafana dashboard provisioning [AC-2 of Improvement 1]

- File: `setup/vm/services/grafana/dashboards/walter-council.json` (new) + `setup/vm/services/grafana/provisioning/dashboards/walter-council.yml` (new)
- Change: Dashboard JSON with 6 panels: (1) tasks/day bar chart by agent, (2) tokens/agent stacked area, (3) task success rate stat panel, (4) approval-gate events heatmap by category, (5) agent state table, (6) task duration P95 histogram. Use the Prometheus datasource already configured in Grafana. Dashboard is provisioned via Grafana's file-based provisioning (no manual import needed).
- Depends on: T-3
- Verify: Restart Grafana container. Navigate to `grafana.${WALTER_DOMAIN}/dashboards`. Dashboard "Walter Council" appears. All 6 panels load without "No data" when at least one agent run has happened.

### T-5: `walter-os status` metrics integration [AC-4 of Improvement 1]

- File: `bin/walter-os` (modify — `cmd_status` function)
- Change: In `cmd_status`, after the audit + spend section, add a "Council (today)" section that reads `/var/lib/walter-council/metrics.prom` with grep+awk and prints: tasks completed, tasks failed, total tokens consumed, agents currently working. Only shows if the metrics file exists; silently skips otherwise.
- Depends on: T-1
- Verify: After a test agent run, `walter-os status` output includes a "Council (today):" section with at least `tasks_completed` and `tokens_total` fields with non-zero values.

### T-6: Extend LLM metadata with task_id and context [AC-1 of Improvement 2]

- File: `scripts/agents/lib/llm.sh` (modify — `llm_invoke` function)
- Change: Add two parameters to `llm_invoke`: `task_id` (from `$WALTER_AGENT_PLANE_ISSUE`) and `context` (from `$WALTER_AGENT_CONTEXT`). In the litellm branch, expand `metadata` from `{agent: $agent}` to `{agent_id: $agent, task_id: $task_id, context: $context, model_alias: $model_tag}`. In the anthropic direct branch, add `x-litellm-tags` header with the same fields (for future routing).
- Verify: Run a dry-run agent invocation with `LITELLM_BASE_URL` pointing to a local mock. Inspect the request body — `metadata.task_id` and `metadata.context` are present and non-empty.

### T-7: `walter-os spend report` subcommand [AC-2, AC-3 of Improvement 2]

- File: `bin/walter-os` (modify — add `cmd_spend_report` and wire into dispatch) + `scripts/agents/lib/spend.sh` (new)
- Change: `spend.sh` has `spend_report_by_agent <start_date> <end_date>` and `spend_report_by_task <start_date> <end_date>` that call LiteLLM's `GET /spend/tags` API and format the response as a table with column headers. `bin/walter-os` adds `spend report --by-agent --last 7d` and `spend report --by-task --last 7d` subcommands that call these functions. Dates are computed from `--last N` flag.
- Depends on: T-6
- Verify: `walter-os spend report --by-agent --last 7d` prints a table with at least one row per agent that has run in the last 7 days. Columns: agent, model, tokens_in, tokens_out, cost_usd. Table is aligned with printf format.

### T-8: alerts.sh — unified alert emission library [AC-1 through AC-5 of Improvement 8]

- File: `scripts/agents/lib/alerts.sh` (new)
- Change: `alert_emit <tier> <message> <context_json>` function. Tier `info`: appends to `/var/log/walter-council/events.log` JSONL only. Tier `warn`: log + Telegram via existing `WALTER_TELEGRAM_BOT_TOKEN` with `[WARN]` prefix. Tier `critical`: log + Telegram with `[CRITICAL]` prefix + `TOWER_CRITICAL_FLAG` file creation (Control Tower reads this). Tier `panic`: all of the above + email via `sendmail`/`msmtp` + creates pause flag at `$PAUSE_FLAG` + creates `$WALTER_CONFIG/gate.lock` file that `approval-gate.sh` reads to block ALL operations. Also adds `alert_unlock` function used by `walter-os agents unlock`. Tier validation (rejects unknown tiers). All log entries are JSONL: `{ts, tier, message, context}`.
- Verify: Unit tests in `tests/agents/alerts.bats`:
  - `alert_emit info "test" '{}'` → no Telegram call (mock the curl), log entry exists.
  - `alert_emit warn "test" '{}'` → Telegram call happens (mock), log entry exists, pause flag NOT created.
  - `alert_emit panic "test" '{}'` → pause flag created, gate.lock created, Telegram mock called.
  - After `alert_unlock`, gate.lock removed and reason logged.

---

## Phase M — Memory + Intelligence

**Estimated effort**: 14–20 hours (was 12–18h; +2h for T-M-0 and T-M-1)
**Depends on**: T-1 (for logging), T-6 (for llm.sh invocations)

### T-M-0: Wiki frontmatter normalization pass [pre-requisite for T-9 to T-16] ✓ DONE

- File: `scripts/wiki/normalize-frontmatter.sh` (new) + `wiki/SCHEMA.md` (new if not exists, otherwise validate it exists)
- Change: Bash script that traverses `~/sync/wiki/**/*.md`. For each file: (1) parses the YAML frontmatter block, (2) validates required fields against `wiki/SCHEMA.md` (`type`, `title`, `created`, `tags`), (3) applies auto-fixes where unambiguous (type inference from path: `people/*` → `type: person`, `projects/*` → `type: project`; `created` from git log if missing), (4) writes fixed files in-place, (5) collects files that need human review (missing title, ambiguous type, malformed YAML) into a report at `/tmp/wiki-normalization-report-<date>.md`. The script is idempotent — running it twice produces identical results.
- Verify: Point the script at `tests/fixtures/wiki-test/` (5 mock pages: 2 valid, 1 missing type, 1 missing title, 1 malformed YAML). The 2 valid pages are unchanged. The missing-type page is fixed. The missing-title and malformed-YAML pages appear in the report. Running the script a second time produces no changes.

### T-M-1: AGENTS.md global wiki integrity amendment [wiki integrity] ✓ DONE

- File: `<operator-home>/Projects/walter-os/AGENTS.md` (modify — add `### Wiki integrity` subsection under "Universal disciplines")
- Change: Add the wiki integrity rule block as specified in the spec section "Required AGENTS.md amendments". Also install `scripts/wiki/wiki-validator.sh` (new) — a short script that accepts a file path, validates its frontmatter against `wiki/SCHEMA.md`, and exits 0/1. This is the hook that agents will call before any wiki write. Document its usage in `SKILL.md` of any skill that writes to the wiki.
- Verify: (1) `grep -A 10 "Wiki integrity" <operator-home>/Projects/walter-os/AGENTS.md` shows the rule block. (2) `scripts/wiki/wiki-validator.sh tests/fixtures/wiki-test/valid-page.md` exits 0. (3) `scripts/wiki/wiki-validator.sh tests/fixtures/wiki-test/broken-frontmatter.md` exits 1 with an error message on stderr.

---

### T-9: lessons.db schema + migration [AC-1 of Improvement 4] ✓ DONE

- File: `scripts/agents/lib/lessons.sh` (new) + `scripts/agents/migrations/001_lessons_schema.sql` (new)
- Change: `lessons.sh` sources a `lessons_init` function that creates `~/.config/walter-os/lessons.db` with the schema from the spec using `sqlite3`. Idempotent (`CREATE TABLE IF NOT EXISTS`). Also initializes the FTS5 virtual table on `headline` and `body` for text search fallback when embeddings are unavailable.
- Verify: `source lessons.sh && lessons_init` creates `~/.config/walter-os/lessons.db`. `sqlite3 lessons.db ".schema"` shows the `lessons` table with all columns.

### T-10: Embedding helper — local embed via LiteLLM [AC-5 of Improvement 4] ✓ DONE

- File: `scripts/agents/lib/lessons.sh` (extend — add `_lesson_embed` function)
- Change: `_lesson_embed <text>` calls `POST ${LITELLM_BASE_URL}/v1/embeddings` with `model: local-embed` and returns a JSON array of 384 floats. Falls back to empty blob if embedding service is unavailable (lessons still work, just no vector similarity — FTS5 only). Stores float32 binary in SQLite BLOB via hex encoding.
- Depends on: T-9
- Verify: `_lesson_embed "test lesson about auth"` returns a JSON array of length 384. `time _lesson_embed "..."` completes in ≤ 200ms when standby homelab node is on LAN. When standby homelab node is unreachable, returns empty without hanging (5s timeout).

### T-11: lesson_write + lesson_query functions [AC-2, AC-3 of Improvement 4] ✓ DONE

- File: `scripts/agents/lib/lessons.sh` (extend)
- Change: `lesson_write <agent> <headline> <body> <tags_json>` — generates a UUID, computes embedding, inserts row into `lessons.db`. `lesson_query <task_description> <agent_name> [--context <ctx>]` — embeds the task description, computes cosine similarity against all rows in the DB (in-process using Python snippet via `python3 -c` for the vector math, no extra dependency), returns top-5 as JSON array sorted by similarity. Filters out rows with `confidence < 0.5`. If embedding unavailable, falls back to FTS5 `MATCH` on task_description tokens.
- Depends on: T-10
- Verify: Write a lesson about "never use raw string concatenation in SQL queries, use parameterized queries". Then query with "writing a database query function". Verify the lesson appears in top-5 results. Verify a query about "CSS grid layout" does NOT return the SQL lesson in top-5.

### T-12: lesson_write integration into agent runner [AC-2 of Improvement 4] ✓ DONE

- File: `scripts/agents/run.sh` (modify — add lesson extraction step at task end)
- Change: At the end of each successful task, the agent runner calls the LLM one more time with a short "what did you learn?" prompt (max 200 tokens, cheap/haiku model). The response, if non-empty and more than 20 chars, is written as a lesson via `lesson_write`. Tags are auto-derived from the Plane issue's labels.
- Depends on: T-11, T-6
- Verify: Run a full agent task. After completion, `walter-os lessons list --agent <name> --last 1d` shows at least one new entry with a non-empty headline.

### T-13: lesson injection into system prompt [AC-2 of Improvement 4] ✓ DONE

- File: `scripts/agents/run.sh` (modify — before LLM invocation, inject lessons)
- Change: Before calling `llm_invoke`, call `lesson_query "$task_description" "$AGENT"` and prepend the results to the system prompt under a `## Lessons from the Council` section. Format: bulleted list of `[<source_agent>] <headline>`. Cap at 5 lessons and 800 tokens total.
- Depends on: T-12
- Verify: Run agent with `--dry-run`. Output includes a `## Lessons from the Council` section when the DB has relevant entries. When DB is empty or has no relevant lessons, the section is omitted (no empty header).

### T-14: `walter-os lessons` subcommand [AC-3, AC-4 of Improvement 4] ✓ DONE

- File: `bin/walter-os` (modify — add `cmd_lessons` + wire dispatch) + `scripts/agents/lib/lessons.sh` (extend — add `lessons_list`, `lessons_rate` functions)
- Change: `walter-os lessons list [--agent <name>] [--last <N>d] [--tag <tag>]` prints a table of lessons. `walter-os lessons rate <id> <0.0..1.0>` updates the `confidence` field. Both delegate to `lessons.sh` functions.
- Depends on: T-11
- Verify: `walter-os lessons list` prints the table header even with empty DB. After `lesson_write`, the new entry appears. `walter-os lessons rate <id> 0.0` + `lesson_query` confirms the lesson no longer appears.

### T-15: Wiki consolidation job script [AC-1, AC-2 of Improvement 3] ✓ DONE

- File: `scripts/wiki/consolidate.sh` (new)
- Change: Bash script that:
  1. Reads all `.md` files in `~/sync/wiki/`.
  2. For each pair, calls `_lesson_embed` on the first 500 chars of each page.
  3. Computes cosine similarity (via the same Python snippet).
  4. Pairs with similarity > 0.92 are written to a JSON report at `/tmp/wiki-consolidation-<date>.json`.
  5. Calls `plane_issue_create` (new helper in `lib/plane.sh`) with the report content and label `wiki:consolidation`.
  6. Contradiction detection: for the top-10 most similar pairs, calls LLM with a "do these contradict each other?" prompt and appends findings to the same Plane issue.
  7. Stale detection: pages with git mtime > 180 days and 0 inbound links (grep-based) are listed in the Plane issue with `[STALE]` flag.
- Depends on: T-10, T-9 (for the plane.sh dependency)
- Verify: Point the script at a test wiki directory with 5 manually crafted pages (including 2 near-duplicates). Script completes in < 2 minutes. JSON report exists. Plane issue is created (or dry-run mode prints the issue content to stdout).

### T-16: Wiki consolidation cron [AC-1, AC-5 of Improvement 3] ✓ DONE

- File: `setup/vm/cron/crontab.d/wiki-consolidation` (new) + `setup/vm/install-cron.sh` (modify — include the new cron)
- Change: Cron entry: `0 2 * * 0 /usr/local/bin/walter-run wiki-consolidation`. The `walter-run` wrapper sets the right env vars from Infisical before calling the script. Log to `/var/log/walter-council/wiki-consolidation.log` with rotation.
- Depends on: T-15
- Verify: Manually trigger the cron: `sudo -u walter /usr/local/bin/walter-run wiki-consolidation`. Verify log entry is written and no uncaught errors.

---

## Phase R — Resilience: Recovery + Induction

**Estimated effort**: 14–20 hours
**Depends on**: T-1, T-8

---

### T-17: Heartbeat writer in agent runner [AC-1 of Improvement 5] ✓ DONE

- File: `scripts/agents/run.sh` (modify — add heartbeat loop)
- Change: Before the main LLM loop, start a background heartbeat process: `while sleep 60; do heartbeat_write "$AGENT" "$PLANE_ISSUE_ID" "$CURRENT_STEP"; done &`. The `heartbeat_write` function appends a JSONL line to `/var/lib/walter-council/heartbeats/<agent>/<issue_id>.heartbeat` with `{ts, agent, issue_id, step, files_touched: [...]}`. When the task ends (success or failure), kill the background process and write a final heartbeat with `{status: done/failed}`.
- Verify: Start a long-running test task. Every 60s a new line appears in the heartbeat file. After task completion, final line has `status: done`.

### T-18: heartbeat.sh library [AC-1, AC-4 of Improvement 5] ✓ DONE

- File: `scripts/agents/lib/heartbeat.sh` (new)
- Change: `heartbeat_write`, `heartbeat_read_last`, `heartbeat_checkpoint_steps` functions. `heartbeat_checkpoint_steps <issue_id> <step_name>` appends `completed_steps: [step_name]` to the current heartbeat. `heartbeat_read_checkpoint <issue_id>` reads the most recent heartbeat and returns the `completed_steps` array. Used by the agent runner to skip already-completed steps when resuming.
- Depends on: T-17
- Verify: Write a heartbeat with steps `["fetch_issue", "analyze"]`. Read it back via `heartbeat_read_checkpoint`. Verify the steps array is intact.

### T-19: Zombie watchdog script [AC-2, AC-3 of Improvement 5] ✓ DONE

- File: `scripts/agents/watchdog.sh` (new)
- Change: Bash script that:
  1. Calls `plane_issues_list_by_state claimed` (new helper in `lib/plane.sh`).
  2. For each claimed issue, reads the corresponding heartbeat file.
  3. If heartbeat missing OR `now - last_heartbeat_ts > 1800` (30 min in seconds): declares zombie.
  4. Posts Plane comment with the zombie declaration + last known step from checkpoint.
  5. Calls `plane_issue_set_state <id> ready` and clears the assignee.
  6. Calls `alert_emit warn "zombie detected: <agent>/<issue>" ...`.
  7. Logs to `/var/log/walter-council/watchdog.log` JSONL.
- Depends on: T-18, T-8
- Verify: Run a test task, then kill the agent process mid-run. Wait 31 minutes (or mock the timestamp). Run watchdog manually. Verify Plane issue is back in `ready` state and comment is posted.

### T-20: Watchdog cron [AC-2 of Improvement 5] ✓ DONE

- File: `setup/vm/cron/crontab.d/watchdog` (new)
- Change: Cron entry: `*/5 * * * * /usr/local/bin/walter-run watchdog`. Log to `/var/log/walter-council/watchdog.log`.
- Depends on: T-19
- Verify: After install, `crontab -l` shows the entry. `grep -c "watchdog" /var/log/walter-council/watchdog.log` increases over time.

### T-21: `walter-os agents status` zombie section [AC-5 of Improvement 5] ✓ DONE

- File: `scripts/agents/main.sh` (modify — `status` subcommand)
- Change: Add a "Zombies detected (last 7d):" section to the `status` output that reads from `/var/log/walter-council/watchdog.log` and counts lines with `event: zombie_detected` in the last 7 days.
- Depends on: T-19
- Verify: After a zombie detection event, `walter-os agents status` shows "Zombies detected (last 7d): 1".

### T-22: `plane_issue_create` + `plane_issues_list_by_state` helpers [AC-3 of Improvement 3, AC-2 of Improvement 5] ✓ DONE

- File: `scripts/agents/lib/plane.sh` (modify — add two functions)
- Change: `plane_issue_create <title> <description> <lane_label>` — POSTs to Plane to create a new issue. Returns the issue ID. `plane_issues_list_by_state <state_name>` — GETs all issues in a given state and returns a newline-delimited list of issue IDs. Both follow the same error-handling pattern as existing functions.
- Verify: `plane_issue_create "Test Issue" "Test body" "janitor"` creates an issue in Plane. `plane_issues_list_by_state ready` returns a list (possibly empty) without errors.

### T-23: `project-induction` skill [AC-1 through AC-5 of Improvement 6] ✓ DONE

- File: `skills/project-induction/SKILL.md` (new) + `skills/project-induction/scripts/induction.sh` (new)
- Change: `induction.sh` runs the 12-question interview interactively (prompts on stdout, reads from stdin). Supports `--non-interactive --answers-file <yaml>` for scripted use. After collecting answers, calls the LLM to generate: (1) the project charter markdown, (2) the repo-level `AGENTS.md`, (3) the Plane epic with tasks (via `plane_issue_create`), (4) the wiki page. Detects PHI/financial answers and auto-includes compliance rules in the `AGENTS.md`. `SKILL.md` documents the skill contract (trigger, inputs, outputs, dependencies).
- Depends on: T-22, T-6
- Verify: Run `skills/project-induction/scripts/induction.sh --non-interactive --answers-file tests/fixtures/induction-answers.yml`. Verify that `docs/specs/test-project-charter.md`, `AGENTS.md`, and a Plane issue are created. With `answers.phiData: true`, verify `AGENTS.md` contains `medical-data-compliance` rule.

### T-24: `walter new project` CLI wiring [AC-1 of Improvement 6] ✓ DONE

- File: `bin/walter-os` (modify — add `new` subcommand dispatch) + `bin/walter` (modify — check if `walter` binary handles this or delegates)
- Change: `walter-os new project <type> <name>` calls `skills/project-induction/scripts/induction.sh`. Validates that `<type>` is one of `webapp | service | solana | hackathon | personal`. Validates `<name>` is alphanumeric+hyphens, ≤ 50 chars.
- Depends on: T-23
- Verify: `walter-os new project webapp my-test-app` starts the interactive interview. `--help` shows usage. Invalid type returns exit code 2 with error message.

---

## Phase T — Trust + Controls

**Estimated effort**: 14–18 hours (was 10–14h; +4h for consensus mode expanding from 3 vacation tasks to 8 consensus tasks T-32 through T-36c)
**Depends on**: T-8 (alerts.sh), T-19 (watchdog exists), T-22 (plane.sh helpers)

---

### T-25: trust-tiers.yml schema + initial values [AC-1 of Improvement 7]

- File: `~/.config/walter-os/trust-tiers.yml` (created by install.sh — template in `setup/templates/trust-tiers.yml`) + `setup/install.sh` (modify — copy template on first install)
- Change: YAML file with structure `agents: { <name>: { tier: low|medium|high, overrides: { <category>: allow|block } } }`. Initial values per ADR-0009. Template lives in `setup/templates/trust-tiers.yml` in the repo; install.sh copies it to the config dir on first run (not overwriting if exists).
- Verify: `cat ~/.config/walter-os/trust-tiers.yml` shows all 6 agents with their tiers. `ls setup/templates/trust-tiers.yml` exists in the repo.

### T-26: Trust tier enforcement in approval-gate.sh [AC-2, AC-3 of Improvement 7]

- File: `hooks/approval-gate.sh` (modify — add trust tier lookup before final block decision)
- Change: After the current `block()` decision, add a new check: read `trust-tiers.yml` with `yq`, get the agent's tier and its `overrides`. If the blocked category is in the agent's `overrides: allow` list, flip the decision to allow with reason "trust tier override". The category mapping (from `reason` string to a category slug) uses a simple lookup table defined at the top of the file.
- Depends on: T-25
- Verify: With `WALTER_AGENT_NAME=reviewer` and `trust-tiers.yml` setting reviewer as high trust with `git-push-feature: allow`, run `approval-gate.sh check "git push origin feature/test" --tool Bash`. Returns exit 0 (allow). Same command with `WALTER_AGENT_NAME=janitor` returns exit 7 (block).

### T-27: `walter-os agents trust` subcommand [AC-4 of Improvement 7]

- File: `scripts/agents/main.sh` (modify — add `trust` subcommand)
- Change: `walter-os agents trust <agent>` reads `trust-tiers.yml` and prints the agent's tier + a table of categories with their effective decision (allow/block/allow-with-tier-override). Uses `yq` to parse YAML.
- Depends on: T-25
- Verify: `walter-os agents trust reviewer` prints "tier: high" and a list of categories with their decisions. `walter-os agents trust unknown-agent` exits with code 2 and error message.

### T-28: Hot-reload of trust tiers [AC-5 of Improvement 7]

- File: `hooks/approval-gate.sh` (modify — always re-reads trust-tiers.yml on each invocation)
- Change: The `approval-gate.sh` already runs fresh per invocation (it's a hook, not a daemon). Document this explicitly in the file header. Add a test that modifying `trust-tiers.yml` between two invocations is reflected immediately.
- Depends on: T-26
- Verify: Run approval-gate check → block. Edit trust-tiers.yml to allow the category. Run same check → allow. No restart required.

### T-29: Wire alerts into agent runner (replace direct Telegram calls) [AC-1 through AC-4 of Improvement 8]

- File: `scripts/agents/run.sh` (modify — replace any direct Telegram curl calls with `alert_emit`)
- Change: Audit all Telegram-posting code in `run.sh`, `watchdog.sh`, `main.sh`, and any other agent scripts. Replace with `alert_emit <tier> <message> <context>` calls. Assign the correct tier to each event per the table in the spec. This is a pure refactor — no behavior change for warn/critical; behavior change only for info (now silent) and panic (now adds pause+lock).
- Depends on: T-8
- Verify: Run a test task that triggers a warn event (e.g., 80% budget). Verify Telegram message is sent (mock). Verify no direct `curl api.telegram.org` calls exist in any script except `alerts.sh`.

### T-30: gate.lock enforcement in approval-gate.sh [AC-3 of Improvement 8]

- File: `hooks/approval-gate.sh` (modify — check for gate.lock at the top)
- Change: At the very beginning of the decision logic (before any analysis), check if `$WALTER_CONFIG/gate.lock` exists. If it does, immediately return `decision=block, reason="Council in panic lock — operator must run walter-os agents unlock"`. This runs before trust tier checks and before standing approvals.
- Depends on: T-8 (gate.lock is created by alert_emit panic)
- Verify: Create the gate.lock file manually. Run `approval-gate.sh check "ls /tmp" --tool Bash`. Returns exit 7 with the panic lock reason.

### T-31: `walter-os agents unlock` subcommand [AC-5 of Improvement 8]

- File: `scripts/agents/main.sh` (modify — add `unlock` subcommand)
- Change: `walter-os agents unlock --reason "..."` removes `gate.lock`, removes the pause flag, and calls `alert_emit info "panic lock cleared by operator" "{reason: $reason}"`. Requires `--reason` to be non-empty. Prints confirmation with the reason logged.
- Depends on: T-30, T-8
- Verify: With gate.lock in place, `walter-os agents unlock --reason "test"` removes the lock. Subsequent `approval-gate.sh check` returns allow. Without `--reason`, exits with code 2.

### T-32: mode.json + `walter-os mode consensus` subcommand [AC-1 of Improvement 9]

- File: `bin/walter-os` (modify — add `mode consensus on|off|status` subcommand) + `scripts/agents/lib/mode.sh` (new)
- Change: `mode.sh` has `mode_consensus_get`, `mode_consensus_set <on|off>`, `mode_consensus_is_on` functions that read/write `~/.config/walter-os/mode.json` (field `consensus: bool`, `since: timestamp`, `voting_threshold: int default 3`). `bin/walter-os` adds `mode consensus on`, `mode consensus off`, `mode consensus status` subcommands.
- Verify: `walter-os mode consensus on` creates/updates `mode.json` with `consensus: true`. `walter-os mode consensus status` prints "Consensus mode: ON (since <timestamp>, threshold: 3)". `walter-os mode consensus off` sets `consensus: false`.

### T-33: Consensus voting library [AC-2, AC-3 of Improvement 9]

- File: `scripts/agents/lib/vote.sh` (new)
- Change: `vote_council <task_id> <task_description> <relevant_agents_json>` function. Takes a JSON array of agent names (max 3, selected by caller based on Plane issue tags). Invokes each agent in parallel via `llm_invoke` with a short prompt: "Should task '<description>' be auto-approved without operator review? Answer yes or no with a 1-sentence reason." Collects responses, counts yes/no. Returns: `{votes: 3, yes: 2, no: 1, quorum_met: true, voters: [{agent, vote, reason}]}` as JSON on stdout. Timeout per agent: 15 seconds. If an agent times out, it counts as abstain (not as no).
- Depends on: T-6 (llm_invoke), T-32
- Verify: Mock the LLM responses via `LITELLM_BASE_URL` pointing to a local stub that returns yes for researcher and reviewer, no for coder. `vote_council "test-123" "fix lint warning in readme" '["researcher","reviewer","coder"]'` returns JSON with `yes: 2, quorum_met: true`.

### T-34: Consensus eligibility check in approval-gate.sh [AC-4 of Improvement 9]

- File: `hooks/approval-gate.sh` (modify — add consensus eligibility classification)
- Change: Add function `consensus_eligible <category>` that returns 0 (eligible) or 1 (ineligible). Ineligible categories: the full "blocked for ALL" list from ADR-0009, plus `prod-db-migration`, `major-dep-bump`, `modify-hooks`, `modify-agent-definitions`, `auth-crypto-phi-files`. Eligible categories: `lint-fix`, `minor-patch-dep-bump`, `doc-update`, `wiki-edit`, `refactor-small`, `formatting`, `comment-change`, `tests-only-pr`. If consensus mode is ON and the blocked category is eligible, instead of returning block, call `plane_issue_set_state <id> awaiting-consensus` and return a new exit code 8 (awaiting-consensus) that the runner interprets as "do not execute, wait for vote result".
- Depends on: T-32, T-26 (approval-gate.sh tier logic)
- Verify: With consensus mode ON, run `approval-gate.sh check "fix lint warning" --tool Bash --category lint-fix`. Returns exit 8. With consensus mode OFF, same check returns exit 7 (block, needs operator). A `prod-db-migration` category always returns exit 7 regardless of consensus mode.

### T-35: Plane state machine extension — `awaiting-consensus` state [AC-2, AC-3 of Improvement 9]

- File: `scripts/agents/lib/plane.sh` (modify — add `awaiting-consensus` and `awaiting-human` state transitions) + `setup/plane/states.md` (document new states)
- Change: Add `plane_issue_set_state_consensus <id>` and `plane_issue_set_state_awaiting_human <id>` helpers. The consensus flow: `needs-operator` → `awaiting-consensus` → (vote pass) `ready` or (vote fail) `awaiting-human`. `awaiting-human` is the new explicit state for tasks that failed consensus and require actual human action. The watchdog skips issues in `awaiting-consensus` and `awaiting-human` (does not declare them zombies). Add the Plane comment with vote results when transitioning out of `awaiting-consensus`.
- Depends on: T-33, T-22
- Verify: Manually set a Plane issue to `awaiting-consensus`. Call `plane_issue_set_state_consensus <id>` with a mock vote result JSON. Verify the issue moves to `ready` and the vote comment is posted. Call again with a failing vote. Verify it moves to `awaiting-human`.

### T-36: Consensus vote trigger in agent runner [AC-2, AC-3 of Improvement 9] ✓ DONE

- File: `scripts/agents/run.sh` (modify — handle exit code 8 from approval-gate)
- Change: When `approval-gate.sh` returns exit 8 (awaiting-consensus), the runner: (1) reads the Plane issue tags to select the 3 most relevant agents for the vote, (2) calls `vote_council`, (3) if quorum met → calls `plane_issue_set_state_consensus <id> --vote-result <json>` which sets state to `ready`, (4) re-enqueues the task for execution, (5) if quorum not met → calls `plane_issue_set_state_awaiting_human <id>` with the vote discussion attached. Logs the full vote to `/var/log/walter-council/consensus-votes.log` JSONL.
- Depends on: T-34, T-35, T-33
- Verify: With consensus mode ON, run a task whose `approval-gate.sh` check would return exit 8. Verify vote is triggered (mock), vote result posted to Plane, and task re-enqueued (state back to `ready` in Plane).

### T-36b: `walter-os agents summary --since` subcommand [AC-5 of Improvement 9] ✓ DONE

- File: `scripts/agents/main.sh` (modify — add `summary` subcommand) + `scripts/agents/lib/mode.sh` (extend — `summary_since` function)
- Change: `walter-os agents summary --since <ISO-date>` reads `/var/log/walter-council/consensus-votes.log` and `/var/log/walter-council/events.log` since the given date. Prints: (1) N tasks auto-approved by consensus (list with Plane links), (2) N tasks in `awaiting-human` (list), (3) N tasks that failed consensus with links to vote discussion. Format is plain text, one section per category.
- Depends on: T-36
- Verify: After running 3 consensus votes (2 pass, 1 fail), `walter-os agents summary --since <today>` shows "Consensus-approved: 2" with links, "Failed consensus (awaiting human): 1" with link.

### T-36c: Consensus mode bats end-to-end test [AC-1 through AC-5 of Improvement 9] ✓ DONE

- File: `tests/agents/consensus.bats` (new)
- Change: End-to-end bats test suite covering: (1) `walter-os mode consensus on` sets mode correctly, (2) approval-gate returns exit 8 for eligible category in consensus mode, (3) vote_council with mocked LLM returns correct JSON with quorum pass, (4) vote_council with mocked LLM returns correct JSON with quorum fail, (5) Plane state transitions work (mock plane.sh), (6) `awaiting-human` is never set for a consensus-ineligible category even in consensus mode, (7) `walter-os mode consensus off` restores normal behavior.
- Depends on: T-36, T-36b
- Verify: `bats tests/agents/consensus.bats` passes all 7 test cases.

---

## Phase U — Control Tower UI

**Estimated effort**: 30–44 hours (was 28–40h; +2h for 3-phase Council Chat split and consensus mode UI in T-43/T-54)
**Depends on**: T-1 (metrics), T-5 (spend report), T-8 (alerts), T-25 (trust tiers), T-26 (gate.lock), T-32 (mode.sh)

---

### T-35: Next.js 15 project scaffold [AC-9 of Part B]

- File: `apps/control-tower/` (new directory — all Tower files live here)
- Change: `pnpm create next-app@latest control-tower --typescript --tailwind --app --no-src-dir`. Verify App Router. Add `package.json` scripts. Add `.dockerignore` and `Dockerfile` (multi-stage: builder + runner image based on `node:22-alpine`). Add to root `.gitignore` exclusions for `.next/`, `node_modules/`.
- Verify: `pnpm --filter control-tower build` completes without errors. `docker build -f apps/control-tower/Dockerfile .` produces an image. `docker run -p 3000:3000 <image>` serves the Next.js default page.

### T-U36: Docker Compose integration for walter-vm [AC-1 of Part B]

Note: renamed to T-U36 to avoid collision with Phase T's T-36 (consensus eligibility check). All "Depends on: T-36" references in Phase U tasks below refer to this task.

- File: `setup/vm/services/control-tower/compose.yml` (new)
- Change: Service definition for control-tower container. Mounts `/var/lib/walter-council` and `/var/log/walter-council` as read-only volumes. Exposes port 3000 internally. Cloudflare Tunnel routes `tower.${WALTER_DOMAIN}` to this container. Tailscale access via CF Tunnel config (no direct public exposure). Env vars: `PLANE_API_URL`, `PLANE_API_TOKEN`, `LITELLM_BASE_URL`, `LITELLM_API_KEY`, `GRAFANA_URL` — all from Infisical at runtime.
- Depends on: T-35
- Verify: `docker compose -f setup/vm/services/control-tower/compose.yml up -d` starts the container. `curl localhost:3000` returns 200.

### T-37: WebSocket server for real-time agent state [AC-2 of Part B]

- File: `apps/control-tower/app/api/ws/route.ts` (new) + `apps/control-tower/lib/metrics-reader.ts` (new)
- Change: Next.js route handler using WebSocket (via `ws` package in a custom server, or via Server-Sent Events as simpler fallback). `metrics-reader.ts` reads `/var/lib/walter-council/metrics.prom` every 2 seconds (Node.js `fs.watchFile` or polling) and parses the `walter_council_agent_state` and `walter_council_heartbeat_age_seconds` metrics. Pushes state changes to connected WebSocket clients. SSE is the recommended approach (simpler with App Router, no custom server needed).
- Depends on: T-U36, T-1
- Verify: Open `tower.${WALTER_DOMAIN}/api/ws` in browser. Start a test agent run. Verify the SSE stream emits an event within 2 seconds. Event payload has `{agent, state, current_issue, since}`.

### T-38: Agent Status Board component [AC-2 of Part B]

- File: `apps/control-tower/app/components/AgentStatusBoard.tsx` (new) + `apps/control-tower/app/page.tsx` (modify — add AgentStatusBoard)
- Change: React component that subscribes to the SSE endpoint from T-37. Renders 6 agent cards in a grid. Each card: agent name, colored state badge (idle=gray, working=green, blocked=yellow), current issue ID with link to Plane, time in current state. Uses Tailwind for styling. Graceful degradation if SSE disconnects (shows last known state with a "disconnected" indicator).
- Depends on: T-37
- Verify: Open Control Tower in browser with a test agent running. The card for that agent shows green "working" badge and the Plane issue ID. Stop the agent. Within 2 seconds the card returns to gray "idle".

### T-39: Decision Timeline component [AC-3 of Part B]

- File: `apps/control-tower/app/api/timeline/route.ts` (new) + `apps/control-tower/app/components/DecisionTimeline.tsx` (new)
- Change: API route reads `/var/log/walter-council/events.log` JSONL (last 50 lines) and returns parsed JSON. Component renders a scrollable timeline: timestamp, agent name, event type, message, optional link to Plane issue. Refreshes every 30 seconds (no real-time needed here). Color-coded by tier.
- Depends on: T-U36, T-8 (events.log is written by alerts.sh)
- Verify: After running an agent task (which generates events), reload the Control Tower. Timeline shows at least one entry with correct timestamp, agent, and message.

### T-40: Metrics Dashboard — Grafana embed [AC-4 of Part B]

- File: `apps/control-tower/app/components/MetricsDashboard.tsx` (new) + `apps/control-tower/app/page.tsx` (modify)
- Change: Simple component that renders the Grafana "Walter Council" dashboard (from T-4) as a signed iframe using Grafana's panel URL with `&kiosk=true`. Uses a Grafana service account token (read-only, stored as env var `GRAFANA_SA_TOKEN`) embedded in the URL for auth. No Grafana login prompt for the user.
- Depends on: T-4, T-U36
- Verify: Control Tower page shows the Grafana dashboard panels without a login prompt. Panels are interactive (zoom, hover for values).

### T-41: Cost Dashboard component [AC-5 of Part B]

- File: `apps/control-tower/app/api/spend/route.ts` (new) + `apps/control-tower/app/components/CostDashboard.tsx` (new)
- Change: API route calls the LiteLLM `/spend/tags` endpoint (same logic as `spend.sh` from T-7 but in TypeScript). Returns spend by agent for the last 7 days. Component renders a table + sparklines (using `recharts`). Shows daily budget usage as a percentage bar per agent.
- Depends on: T-U36, T-7 (same LiteLLM endpoint)
- Verify: Cost Dashboard loads in ≤ 3 seconds. Shows a row per agent with realistic values (including $0 rows). Budget percentage bars are visible.

### T-42: HA Status component [AC-6 of Part B]

- File: `apps/control-tower/app/api/ha-status/route.ts` (new) + `apps/control-tower/app/components/HAStatus.tsx` (new)
- Change: API route polls the same health check endpoints that CF Load Balancer uses (e.g., `GET https://plane.${WALTER_DOMAIN}/api/health` and the standby homelab node equivalent). Returns `{service, primary_healthy, standby_healthy}` for each Tier-A service. Component renders a grid: each service as a row with green/red indicators for primary and standby. Refreshes every 60 seconds.
- Depends on: T-U36
- Verify: With walter-vm running normally, all primary indicators are green. Simulate a failed health check (return 503 from the health endpoint) and verify the indicator turns red within 60 seconds.

### T-43: Alert Feed + Mode Indicator components [AC-1, AC-6 of Part B]

- File: `apps/control-tower/app/components/AlertFeed.tsx` (new) + `apps/control-tower/app/components/ModeIndicator.tsx` (new) + `apps/control-tower/app/api/alerts/route.ts` (new) + `apps/control-tower/app/api/mode/route.ts` (new)
- Change: Alert feed: reads recent events from `/var/log/walter-council/events.log`, filters for warn/critical/panic, renders with tier color coding and an "Acknowledge" button (POST to `/api/alerts/ack` which appends to an acks file). Mode indicator: reads `~/.config/walter-os/mode.json`, shows consensus mode status (ON/OFF) with a toggle that calls `walter-os mode consensus on|off` via a server-side exec. Shows count of tasks auto-approved since consensus mode was activated (reads `consensus-votes.log`).
- Depends on: T-36c (consensus mode tasks), T-32, T-8
- Verify: Emit a `critical` alert manually. Alert Feed shows the entry with red styling. Click Acknowledge — entry is marked as acknowledged. Mode Indicator shows consensus mode status. Clicking toggle changes mode (verify `mode.json` changes). When consensus mode has processed votes, the auto-approved count is non-zero.

### T-44a: Council Chat — Round 1 (parallel groupthink) API [AC-7 of Part B]

- File: `apps/control-tower/app/api/council-chat/round1/route.ts` (new) + `apps/control-tower/lib/council-personas.ts` (new)
- Change: POST endpoint that accepts `{message: string, session_id: string}` and fans out to 6 parallel LLM calls via LiteLLM, one per agent persona. `council-personas.ts` exports the system prompt for each agent (adapted from `agents/*.md` but shortened to ≤ 300 tokens) with an explicit instruction to respond in ≤ 300 tokens without seeing other agents' responses. Uses `Promise.allSettled` so one agent failing doesn't block others. Response is a streaming NDJSON: each line is `{agent, chunk, done, round: 1}`. Timeout per agent: 25 seconds. Persists Round 1 responses to `council-chat-history.jsonl` under the session_id.
- Depends on: T-U36 (compose wired), T-6 (LiteLLM integration pattern)
- Verify: POST to `/api/council-chat/round1` with `{"message": "what should we prioritize this week?", "session_id": "test-001"}`. Verify 6 responses arrive within 30 seconds, each tagged `round: 1`. Verify each response is ≤ 300 tokens. Verify calls appear in LiteLLM logs (not direct Anthropic). Verify session is persisted to history file.

### T-44b: Council Chat — Round 2 (sequential deliberation) + Synthesis API [AC-7 of Part B]

- File: `apps/control-tower/app/api/council-chat/round2/route.ts` (new) + `apps/control-tower/app/api/council-chat/synthesis/route.ts` (new)
- Change: Round 2 endpoint: accepts `{session_id: string}`. Reads the 6 Round 1 responses from history. Invokes agents **sequentially** in trust-tier-descending order (reviewer → triage → researcher → coder → liaison → janitor, mapping high → medium → low per ADR-0009). Each agent receives all 6 R1 responses + its own R1 response and is instructed to: (a) refine its position, (b) cite or refute other agents by name, (c) propose explicit trade-offs. No token cap on R2 responses. Streams NDJSON with `{agent, chunk, done, round: 2}`. Sequential means each R2 response is kicked off only after the prior one completes (not parallel). Synthesis endpoint: accepts `{session_id: string}`. Reads 12 responses (R1+R2). Invokes the `liaison` agent with a synthesis prompt. Returns `{summary: string, convergences: string[], disagreements: string[], recommended_path: string, next_steps: string[]}`. Timeout: 30 seconds.
- Depends on: T-44a
- Verify: Call round2 endpoint with a valid session_id that has R1 responses. Verify responses arrive in order: reviewer first, janitor last. Verify each R2 response references at least one other agent by name (check in response text). Call synthesis endpoint. Verify response has all 5 fields populated with non-empty strings.

### T-45: Council Chat UI — 3-phase flow [AC-7 of Part B]

- File: `apps/control-tower/app/council/page.tsx` (new) + `apps/control-tower/app/components/CouncilChat.tsx` (new)
- Change: Chat interface. Input: text area + Send button. After send, the UI runs 3 phases with visible progress: (1) "Round 1: gathering perspectives..." — 6 agent cards show spinners, populate as streaming arrives. (2) "Round 2: deliberating..." — same 6 cards update with longer deliberative responses in trust-tier order (reviewer card updates first, janitor last). (3) "Synthesis..." — a seventh card labeled "liaison" shows the synthesis result. All phases show elapsed time. A "Spin as spec + plan" button appears below the synthesis. History is stored server-side in `council-chat-history.jsonl` (not just localStorage, given the multi-round state).
- Depends on: T-44a, T-44b
- Verify: Type a message and click Send. Round 1 cards populate within 30s. Round 2 cards update sequentially within 75s. Synthesis card appears within 90s. "Spin as spec + plan" button is visible after synthesis. Page reload shows previous conversations from history.

### T-46: Ideation Session UI + spec creation flow [AC-8 of Part B]

- File: `apps/control-tower/app/ideation/page.tsx` (new) + `apps/control-tower/app/api/ideation/route.ts` (new) + `apps/control-tower/app/api/ideation/spin-spec/route.ts` (new)
- Change: Ideation page: same Council Chat UI but with a guided header ("describe your idea"). After the Council responds, shows a summary card generated by a final LLM call ("synthesize these 6 perspectives into 3 bullet points"). Add a "Spin this as spec + plan" button. That button calls `spin-spec` API route, which creates a Plane issue in `lane:code` with the ideation summary as description and label `type:spec-request`. The architect agent picks this up on the next polling cycle.
- Depends on: T-45, T-22
- Verify: Complete an ideation session. "Spin as spec" button appears after the summary. Click it. A Plane issue appears in the Council's `lane:code` queue. Issue has the ideation summary in the description.

### T-47: Conversation history search [AC-9 of Part B — implied]

- File: `apps/control-tower/app/api/history/route.ts` (new) + `apps/control-tower/app/history/page.tsx` (new)
- Change: History is already persisted to `~/.config/walter-os/council-chat-history.jsonl` by T-44a (one entry per session with R1, R2, and synthesis responses). Search API accepts `?q=<query>` and returns matching sessions (simple grep, no embeddings). History page renders sessions chronologically with expandable sections for R1, R2, and synthesis. Session shows which phase is present (some may only have R1 if they were abandoned mid-flow).
- Depends on: T-44a, T-44b
- Verify: After 3 chat sessions (each completing all 3 phases), history page shows all 3. Search for a term from one message — only that session appears. A session that was abandoned after R1 shows R1 only.

### T-48: Tailscale-only access enforcement [AC-1 of Part B]

- File: `setup/vm/services/control-tower/compose.yml` (modify) + `apps/control-tower/middleware.ts` (new)
- Change: Two layers: (1) Cloudflare Tunnel is configured to reject connections from non-Tailscale IPs (CF Access policy or mTLS client cert). (2) Next.js middleware checks the `X-Forwarded-For` or `CF-Connecting-IP` header and rejects requests not originating from the Headscale CGNAT range (`100.64.0.0/10`). Returns 403 with a plain-text error message.
- Depends on: T-U36
- Verify: Access `tower.${WALTER_DOMAIN}` from a browser NOT on the Tailscale network → 403. Access from a device on the Tailscale network → 200.

### T-49: Control Tower smoke test suite [AC-1 through AC-10 of Part B]

- File: `tests/control-tower/smoke.spec.ts` (new) — Playwright test suite
- Change: Playwright tests covering: (1) page loads in < 5s, (2) Agent Status Board renders 6 cards, (3) SSE connection is established, (4) Council Chat receives 6 responses for a test message, (5) Timeline shows entries, (6) Cost Dashboard loads without errors, (7) HA Status shows green indicators for all services when stack is healthy, (8) Mode toggle works.
- Depends on: T-38 through T-47
- Verify: `pnpm --filter control-tower test` runs the Playwright suite against a locally running instance. All 8 tests pass.

### T-50: Control Tower Docker image CI [tech-debt prevention]

- File: `.github/workflows/control-tower.yml` (new)
- Change: GitHub Actions workflow: on PR touching `apps/control-tower/**`, run `pnpm build`, `pnpm lint`, `pnpm typecheck`, and the Playwright smoke tests against a locally started server. Fails PR if any step fails.
- Depends on: T-35, T-49
- Verify: Open a PR that modifies a Control Tower file. GitHub Actions runs the workflow and passes.

### T-51: Docs update — Control Tower runbook [non-AC, but required by DoD]

- File: `docs/operational/control-tower-runbook.md` (new)
- Change: Runbook covering: how to start/stop the container, how to update it, what to do if SSE disconnects, how to recover from a panic lock, how to toggle consensus mode on/off, how to interpret the 3-phase Council Chat output, how to access the Grafana dashboards from the Tower.
- Depends on: T-U36 (compose), T-43 (alerts/mode), T-45 (council chat UI)
- Verify: Runbook is reviewed for accuracy by running through each step manually on walter-vm.

### T-52: Memory + patterns update [architect maintenance]

- File: `.claude/agent-memory/architect/patterns.md` (modify) + `.claude/agent-memory/architect/decisions-log.md` (modify)
- Change: Record: Control Tower uses Next.js 15 App Router + SSE + LiteLLM fan-out pattern. The trust-tiers pattern (YAML config + shell gate). The alert_emit tier pattern. The 3-phase Council Chat pattern (parallel groupthink → sequential deliberation → liaison synthesis). The consensus mode voting pattern (vote.sh + Plane state machine). Pointer to ADR-0008 and ADR-0009.
- Depends on: all prior tasks
- Verify: Memory files are updated with the patterns used in this implementation.

### T-53: Ideation Session — 3-phase flow upgrade [AC-8 of Part B]

- File: `apps/control-tower/app/ideation/page.tsx` (modify) + `apps/control-tower/app/api/ideation/route.ts` (modify)
- Change: Update the Ideation Session to use the same 3-phase flow as Council Chat (via the shared T-44a/T-44b endpoints with a different `session_type: ideation` tag). The synthesis result is used as the content for the "Spin as spec + plan" button. This replaces the original single-round fan-out. The "guided header" prompt is passed to Round 1; R2 deliberates; the liaison synthesis drives the spec creation.
- Depends on: T-44b, T-46
- Verify: Complete an ideation session. Verify all 3 phases occur (Round 1 perspectives, Round 2 deliberation, Synthesis). "Spin as spec + plan" button uses the synthesis output as the Plane issue body.

### T-54: Consensus mode live count in Control Tower [AC-6 of Improvement 9]

- File: `apps/control-tower/app/api/consensus-status/route.ts` (new) + `apps/control-tower/app/components/ModeIndicator.tsx` (modify — extend to show consensus stats)
- Change: API route reads `/var/log/walter-council/consensus-votes.log` and returns `{mode_on: bool, since: string, approved: N, failed: N, pending: N}`. ModeIndicator component (from T-43) is extended: when consensus mode is ON, shows a mini-dashboard: "N tasks auto-approved, M awaiting human, K in vote". Refreshes every 60 seconds. The toggle button calls T-32's CLI via server-side exec.
- Depends on: T-43, T-36c (consensus voting log exists)
- Verify: Activate consensus mode and run 2 votes (1 pass, 1 fail). The ModeIndicator shows "Consensus: ON | 1 approved | 1 awaiting human". Toggling consensus off updates the indicator within 60 seconds.

---

## Effort summary by phase

| Phase | Tasks | Estimated hours | Parallelizable with |
|---|---|---|---|
| F — Foundation | T-1 to T-8 | 10–14h | Nothing (critical path) |
| M — Memory | T-M-0, T-M-1, T-9 to T-16 | 14–20h | R (after F) |
| R — Resilience | T-17 to T-24 | 14–20h | M (after F) |
| T — Trust/Controls | T-25 to T-36c | 14–18h | M and R (after F) |
| U — Control Tower | T-35, T-U36 to T-54 | 30–44h | Can start T-35/T-U36 after F; full UI after T |
| **Total** | **62 tasks** | **82–116h** | |

Note: Previous total was 52 tasks / 74–106h. Delta: +10 tasks (+2 wiki normalization, +5 consensus mode, +2 Council Chat phases split, +1 ideation upgrade, +T-54). Hours: +8–10h net.

## Critical path for v0 usable Control Tower

Minimum viable path to "I can open the browser and see something useful":

```
T-1 (metrics) → T-3 (node exporter) → T-4 (grafana dashboard)
T-1 → T-5 (status cmd)
T-8 (alerts) →
T-25 (trust yaml) → T-35 (Next.js scaffold) → T-U36 (compose) → T-37 (SSE) → T-38 (agent board) → T-39 (timeline) → T-40 (grafana embed) → T-48 (auth)
```

That path is approximately 30–38 hours. Everything else (council chat 3-phase, consensus mode, ideation, cost dashboard, HA status) adds value but isn't blocking "v0 usable".

Council Chat 3-phase (T-44a → T-44b → T-45) adds approximately 4–6 hours to the chat milestone specifically. Critical path to "v0 Council Chat working" is unchanged in sequence but the endpoint is now two routes instead of one.
