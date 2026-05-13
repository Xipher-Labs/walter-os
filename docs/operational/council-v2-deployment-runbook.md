# Walter Council v2 — Deployment Runbook

**Refs**: `docs/specs/walter-council-v2.md`, `docs/operational/council-v2-prereqs.md`
**Audience**: operator deploying to walter-vm + a local workstation
**Estimated time**: 2–4 hours including prereqs
**PR order (non-negotiable)**: #26 (F) → #27 (M) → #28 (R) → #29 (T) → #30 (U) → Phase V (TBD)

Each branch was cut from the prior, so merging out of order produces conflicts.

---

## Pre-flight checklist

Run these before touching any PR. Most take < 2 minutes. A blocked prereq now
saves a forced revert later.

```bash
# 1. Prometheus + Grafana running on walter-vm
ssh walter-vm "docker compose ps | grep -E 'prometheus|grafana'"
# Expected: both show "Up"

# 2. LiteLLM /spend/tags endpoint reachable
ssh walter-vm "curl -s http://litellm:4000/spend/tags \
  -H 'Authorization: Bearer ${LITELLM_MASTER_KEY}' | jq .total"
# Expected: a number (even 0), not 404

# 3. Plane custom states exist
ssh walter-vm "curl -s \$PLANE_API_URL/api/v1/workspaces/.../states/ \
  -H 'X-Api-Key: \$PLANE_API_TOKEN' | jq '[.[].name]'"
# Expected: includes "awaiting-resume", "awaiting-consensus", "awaiting-human"
# If missing → see prereqs.md Phases R and T sections

# 4. Postgres databases exist
ssh walter-vm "docker compose exec postgres psql -U postgres -c '\l'" \
  | grep -E "walter_lessons|walter_control_tower"
# Expected: both databases listed

# 5. Infisical secrets provisioned
ssh walter-vm "infisical secrets get LESSONS_DB_URL --env dev"
ssh walter-vm "infisical secrets get CONTROL_TOWER_ADMIN_TOKEN --env dev"
# Expected: non-empty values

# 6. Embedding model reachable
ssh walter-vm "curl -s http://litellm:4000/v1/embeddings \
  -H 'Authorization: Bearer ${LITELLM_MASTER_KEY}' \
  -d '{\"model\": \"walter-embed\", \"input\": \"test\"}' | jq .data[0].embedding | head -c 40"
# Expected: starts with "[" (float array)

# 7. Local: install.sh --upgrade was run after Phase M merge
jq '.hooks.PreToolUse' ~/.claude/settings.json | grep wiki-validator
# Expected: wiki-validator path appears. If not → run ./install.sh --upgrade after PR #27 merges
```

If any check fails, complete that prereq from `docs/operational/council-v2-prereqs.md`
before proceeding. Do not merge a phase until its own row of prereqs is green.

---

## Step 1 — Merge PR #26 (Phase F: Foundation)

**What it adds**: Prometheus metrics writer, Node Exporter wiring, Grafana dashboard,
`walter-os status` metrics section, LLM metadata tags, `walter-os spend report`,
and the `alerts.sh` unified tier system.

**Pre-merge** (confirm all Phase F prereqs from `council-v2-prereqs.md` are done):
- Grafana datasource `walter-prometheus` exists (F-prereq-2)
- Prometheus scrape config includes `walter_council_.*` filter (F-prereq-3)
- LiteLLM spend tracking enabled (F-prereq-4)

**Merge**:

```bash
gh pr merge 26 --squash --delete-branch \
  --subject "feat(council-v2): Phase F — observability + cost attribution + alert tiers"
git checkout main && git pull
```

**Post-merge verification** (~5 min):

```bash
# Smoke: metrics file is created after a dry-run agent invocation
ssh walter-vm "WALTER_AGENT_NAME=researcher walter-os agents run-once \
  --issue TEST-001 --dry-run"
ssh walter-vm "grep walter_council_tasks_total \
  /var/lib/walter-council/metrics.prom"
# Expected: line like: walter_council_tasks_total{agent="researcher",result="success"} 1

# Smoke: spend report endpoint
walter-os spend report --by-agent --last 7d
# Expected: table with headers (agent | model | tokens_in | tokens_out | cost_usd)
# May have all zeros if no real runs yet — that's fine

# Smoke: status shows council section
walter-os status | grep -A 5 "Council (today)"
# Expected: section present with tasks_completed and tokens_total fields

# Smoke: alerts.sh — info tier stays silent
ssh walter-vm "source scripts/agents/lib/alerts.sh && \
  alert_emit info 'deploy-test' '{}'"
ssh walter-vm "tail -1 /var/log/walter-council/events.log"
# Expected: JSONL entry with tier=info; no Telegram message

# Smoke: panic tier creates gate.lock
ssh walter-vm "source scripts/agents/lib/alerts.sh && \
  alert_emit panic 'deploy-test-panic' '{}'"
ssh walter-vm "ls -la ~/.config/walter-os/gate.lock"
# Expected: file exists
# Cleanup immediately:
walter-os agents unlock --reason "deploy verification test"
ssh walter-vm "ls ~/.config/walter-os/gate.lock 2>&1"
# Expected: "No such file or directory"
```

If Grafana dashboard doesn't appear: restart the Grafana container
(`docker compose restart grafana`) — file-based provisioning re-runs on start.

---

## Step 2 — Merge PR #27 (Phase M: Memory + Intelligence)

**What it adds**: wiki frontmatter normalization, AGENTS.md wiki integrity amendment,
`lessons.db` schema, embedding helper, `lesson_write`/`lesson_query`, lesson injection
into agent system prompts, `walter-os lessons` subcommand, wiki consolidation job + cron.

**Pre-merge**:
- `walter_lessons` DB exists with `lessons_writer` user (M-prereq-3)
- `LESSONS_DB_URL` in Infisical (M-prereq-3)
- Embedding model `walter-embed` reachable (M-prereq-4)

**Merge**:

```bash
gh pr merge 27 --squash --delete-branch \
  --subject "feat(council-v2): Phase M — memory, wiki normalization, lessons broker"
git checkout main && git pull
```

**Post-merge actions** (required, not optional):

```bash
# 1. Run wiki normalization pass (one-time)
ssh walter-vm "bash scripts/wiki/normalize-frontmatter.sh"
# Expected: outputs summary of pages fixed vs. pages needing review
# Review the report:
cat ~/.config/walter-os/wiki-normalize-report.txt
# Approve and commit any auto-fixed pages if the report looks clean

# 2. Activate wiki-validator hook locally
cd "${WALTER_OS_HOME}"
./install.sh --upgrade
jq '.hooks.PreToolUse' ~/.claude/settings.json | grep wiki-validator
# Expected: path to wiki-validator.sh appears in the hook config

# 3. Install wiki consolidation cron on walter-vm
ssh walter-vm "cd ~/walter-os && bash setup/walter-host/install-cron.sh"
ssh walter-vm "crontab -l | grep wiki-consolidation"
# Expected: "0 2 * * 0 /usr/local/bin/walter-run wiki-consolidation"

# 4. Lessons DB smoke test
ssh walter-vm "source scripts/agents/lib/lessons.sh && lessons_init && \
  sqlite3 ~/.config/walter-os/lessons.db '.schema'"
# Expected: CREATE TABLE lessons (...) with all columns including embedding BLOB

# 5. Lesson round-trip
ssh walter-vm "source scripts/agents/lib/lessons.sh && lessons_init && \
  lesson_write 'reviewer' 'Never use raw string concat in SQL' \
  'Use parameterized queries always' '[\"security\",\"sql\"]'"
walter-os lessons list --agent reviewer --last 1d
# Expected: one row with the headline above
```

**Failure mode**: if `lesson_write` hangs for > 10s, the embedding service is
unreachable. Check M-prereq-4. The system falls back to FTS5 text search
automatically, but resolve the embedding service before Phase M is considered done.

---

## Step 3 — Merge PR #28 (Phase R: Resilience)

**What it adds**: heartbeat writer, heartbeat library, zombie watchdog script,
watchdog cron, zombie count in `agents status`, `plane_issue_create` helper,
`project-induction` skill, `walter new project` CLI.

**Pre-merge**:
- Plane state `awaiting-resume` exists (R-prereq-1)
- User `walter` can run crontab on walter-vm (R-prereq-2)

**Merge**:

```bash
gh pr merge 28 --squash --delete-branch \
  --subject "feat(council-v2): Phase R — heartbeat, zombie watchdog, project induction"
git checkout main && git pull
```

**Post-merge actions**:

```bash
# 1. Install watchdog cron
ssh walter-vm "cd ~/walter-os && bash setup/walter-host/install-cron.sh"
ssh walter-vm "crontab -l | grep watchdog"
# Expected: "*/5 * * * * /usr/local/bin/walter-run watchdog"

# 2. Watchdog smoke (manual trigger)
ssh walter-vm "/usr/local/bin/walter-run watchdog"
ssh walter-vm "tail -5 /var/log/walter-council/watchdog.log"
# Expected: JSONL entries, no "command not found" or uncaught errors
# If no claimed issues exist, log shows: {"event":"watchdog_run","zombies_found":0}

# 3. Heartbeat smoke — needs a running agent
# Start a test task and watch heartbeats accumulate:
ssh walter-vm "WALTER_AGENT_NAME=researcher walter-os agents run-once \
  --issue TEST-002 --dry-run &"
sleep 65
ssh walter-vm "ls /var/lib/walter-council/heartbeats/researcher/"
# Expected: TEST-002.heartbeat file exists

# 4. agents status shows zombie section
walter-os agents status | grep -A 2 "Zombies"
# Expected: "Zombies detected (last 7d): 0" (or N if real zombies exist)
```

**Failure mode**: if the watchdog cron errors on `plane_issues_list_by_state`,
the Plane `awaiting-resume` state is missing. Add it via the Plane UI (R-prereq-1)
and re-run manually.

---

## Step 4 — Merge PR #29 (Phase T: Trust + Consensus)

**What it adds**: `trust-tiers.yml` with per-agent tiers, trust enforcement in
`approval-gate.sh`, `walter-os agents trust` subcommand, hot-reload of trust config,
`alerts.sh` wired into agent runner (replacing direct Telegram calls), gate.lock
enforcement, `walter-os agents unlock`, `mode.json` + consensus mode CLI,
consensus voting library, consensus eligibility in approval-gate, Plane state machine
for `awaiting-consensus`/`awaiting-human`, full consensus vote trigger in runner,
`walter-os agents summary`, and the consensus e2e bats suite.

**Pre-merge**:
- Plane states `awaiting-consensus` and `awaiting-human` exist (T-prereq-1, T-prereq-2)
- Consensus bats suite passing on the feature branch:
  ```bash
  cd /path/to/feature/council-v2-trust && bats tests/agents/consensus.bats
  # All 7 tests pass
  ```

**Merge**:

```bash
gh pr merge 29 --squash --delete-branch \
  --subject "feat(council-v2): Phase T — trust tiers, alert hierarchy, consensus mode"
git checkout main && git pull
```

**Post-merge actions**:

```bash
# 1. Review and confirm trust-tiers.yml initial values
cat ~/.config/walter-os/trust-tiers.yml
# Confirm: reviewer=high, triage=medium, researcher=medium,
#          coder=medium, liaison=low, janitor=low
# If you want changes, edit now — after this it's a governed change (needs a PR)

# 2. Test trust tier enforcement
WALTER_AGENT_NAME=reviewer \
  hooks/approval-gate.sh check "git push origin feature/test" --tool Bash
# Expected: exit 0 (allow — reviewer has high trust, git-push-feature is auto-approved)

WALTER_AGENT_NAME=janitor \
  hooks/approval-gate.sh check "git push origin feature/test" --tool Bash
# Expected: exit 7 (block)

# 3. Test hot-reload (no restart needed)
# Temporarily set janitor to high trust:
yq e '.agents.janitor.tier = "high"' -i ~/.config/walter-os/trust-tiers.yml
WALTER_AGENT_NAME=janitor \
  hooks/approval-gate.sh check "git push origin feature/test" --tool Bash
# Expected: exit 0
# Revert:
yq e '.agents.janitor.tier = "low"' -i ~/.config/walter-os/trust-tiers.yml

# 4. Verify consensus mode CLI
walter-os mode consensus status
# Expected: "Consensus mode: OFF"
walter-os mode consensus on
cat ~/.config/walter-os/mode.json | jq .consensus
# Expected: true
walter-os mode consensus off

# 5. Consensus bats suite on main
bats tests/agents/consensus.bats
# Expected: 7/7 pass

# 6. agents summary baseline
walter-os agents summary --since "$(date -u +%Y-%m-%dT00:00:00Z)"
# Expected: three sections present even if all zeros
```

**Failure mode**: if `yq` is not installed on walter-vm, the trust tier hot-reload
test will error. Install: `snap install yq` or `brew install yq` locally.
The `approval-gate.sh` depends on `yq` for YAML parsing.

**Consensus mode**: do NOT activate `walter-os mode consensus on` in production
until you've reviewed the bats suite output and are comfortable with the voting
flow. It's off by default for good reason. Enable it intentionally.

---

## Step 5 — Merge PR #30 (Phase U: Control Tower)

**What it adds**: Next.js 15 Control Tower app in `apps/control-tower/`, Docker
Compose service, SSE-based agent state board, decision timeline, Grafana embed,
cost dashboard, HA status panel, alert feed, mode indicator with consensus stats,
Council Chat 3-phase flow, Ideation Session, conversation history, Tailscale-only
auth middleware, Playwright smoke suite, and CI workflow.

**Pre-merge**:
- `walter_control_tower` DB exists (U-prereq-1)
- `CONTROL_TOWER_ADMIN_TOKEN` in Infisical (U-prereq-2)
- Tailscale ACL verified — port 3000 not publicly exposed (U-prereq-3)
- Grafana embed mode enabled (U-prereq-4)
- `GRAFANA_SA_TOKEN` (read-only service account) set in Infisical

**Verify build on the branch before merging**:

```bash
# On the feature branch locally or in CI:
pnpm --filter control-tower build
# Expected: build completes, no TypeScript errors

pnpm --filter control-tower test
# Expected: Playwright smoke suite — 8/8 pass
```

**Merge**:

```bash
gh pr merge 30 --squash --delete-branch \
  --subject "feat(council-v2): Phase U — Control Tower UI"
git checkout main && git pull
```

**Post-merge deployment on walter-vm**:

```bash
# 1. Pull and start the container
ssh walter-vm "cd ~/walter-os && git pull"
ssh walter-vm "cd ~/walter-os && \
  docker compose -f setup/walter-host/services/control-tower/compose.yml up -d --build"
ssh walter-vm "docker compose \
  -f setup/walter-host/services/control-tower/compose.yml ps"
# Expected: control-tower container status "Up"

# 2. Cold start check
ssh walter-vm "time curl -s -o /dev/null -w '%{http_code}' http://localhost:3000"
# Expected: 200 in < 5 seconds

# 3. Tailscale access check (from Mac on Tailscale)
curl -s -o /dev/null -w '%{http_code}' https://tower.${WALTER_DOMAIN}
# Expected: 200

# 4. Access check from internet (should 403)
# Use a phone not on Tailscale or a VPS:
# curl https://tower.${WALTER_DOMAIN} → Expected: 403

# 5. Operator account first-run setup
# Open https://tower.${WALTER_DOMAIN} in browser
# Complete the one-time profile setup (layout + theme preferences)

# 6. Agent Status Board smoke
# Start a test agent while watching the board:
ssh walter-vm "WALTER_AGENT_NAME=researcher walter-os agents run-once \
  --issue TEST-003 --dry-run &"
# Open Control Tower → Agent board should show researcher as "working" within 2s

# 7. Council Chat smoke
# Type "what should we prioritize this week?" in Council Chat
# Round 1: 6 cards populate within 30s
# Round 2: cards update sequentially within 75s (reviewer first)
# Synthesis: liaison card appears within 90s
# Verify in LiteLLM logs (not direct Anthropic):
ssh walter-vm "grep TEST-003 /var/log/litellm/access.log | tail -5"
# Expected: log entries showing model calls tagged with agent IDs
```

**Failure mode — Grafana panels empty/CORS error**: Grafana embed mode wasn't
enabled (U-prereq-4). Enable via Grafana UI and set `GRAFANA_SA_TOKEN` in
Infisical, then restart the control-tower container.

**Failure mode — Council Chat times out**: one or more agent personas is hitting
LiteLLM timeout. Check `LITELLM_BASE_URL` in the container env and verify
LiteLLM is healthy: `curl http://litellm:4000/health`.

---

## Step 6 — Phase V (DevRel analytics, when ready)

Phase V spec lives at `docs/specs/devrel-analytics-stack.md`. Dispatch is pending.
When the PR is opened, it will follow the same merge pattern: verify prereqs,
merge squash, verify post-merge.

Placeholder tasks:
- Provision any new Postgres databases before the PR merges
- Add Phase V to the status board in `council-v2-prereqs.md`
- Run smoke tests after merge following the same pattern

This section will be filled when the Phase V PR is created.

---

## Rollback procedures

> See also `council-v2-prereqs.md` → "Rollback plan global" for the high-level
> procedure. Here are the per-phase specifics.

### Rollback Phase F (PR #26)

```bash
git revert <merge-commit-hash> -m 1
# Metrics file stops being written — Grafana shows "No data", that's expected
# alerts.sh reverts to prior Telegram-direct calls
# No DB state to clean up
```

### Rollback Phase M (PR #27)

```bash
git revert <merge-commit-hash> -m 1
# lessons.db survives — orphaned but harmless. Drop if desired:
ssh walter-vm "rm ~/.config/walter-os/lessons.db"
# Remove wiki-consolidation cron:
ssh walter-vm "crontab -l | grep -v wiki-consolidation | crontab -"
# Re-run install.sh to remove wiki-validator hook:
./install.sh --upgrade
```

### Rollback Phase R (PR #28)

```bash
git revert <merge-commit-hash> -m 1
# Remove watchdog cron:
ssh walter-vm "crontab -l | grep -v watchdog | crontab -"
# Heartbeat files are inert — leave them or rm -rf /var/lib/walter-council/heartbeats/
```

### Rollback Phase T (PR #29)

```bash
git revert <merge-commit-hash> -m 1
# trust-tiers.yml stays — harmless without the gate logic reading it
# If Council is in panic lock, unlock first:
walter-os agents unlock --reason "rolling back Phase T"
# mode.json stays — harmless
```

### Rollback Phase U (PR #30)

```bash
git revert <merge-commit-hash> -m 1
ssh walter-vm "docker compose \
  -f setup/walter-host/services/control-tower/compose.yml down"
# DB walter_control_tower survives — drop if desired:
ssh walter-vm "docker compose exec postgres psql -U postgres \
  -c 'DROP DATABASE walter_control_tower;'"
```

---

## Post-deployment verification (all phases together)

Run after Phase U is live to confirm the full stack is integrated.

```bash
# 1. Bats suites
bats tests/agents/metrics.bats
bats tests/agents/alerts.bats
bats tests/agents/consensus.bats
# Expected: all pass

# 2. Full agent run (not dry-run)
ssh walter-vm "WALTER_AGENT_NAME=researcher walter-os agents run-once \
  --issue <a real ready issue from Plane>"
# After completion:

# 3. Metrics updated
ssh walter-vm "grep walter_council_tasks_total \
  /var/lib/walter-council/metrics.prom"
# Expected: counter incremented

# 4. Spend tagged
walter-os spend report --by-agent --last 1d
# Expected: researcher row shows non-zero tokens

# 5. Lesson written
walter-os lessons list --agent researcher --last 1d
# Expected: at least one lesson from the run

# 6. Decision Timeline in Control Tower shows the run events
# Open https://tower.${WALTER_DOMAIN} → Decision Timeline
# Expected: entries for the run with correct agent label and Plane link

# 7. Council Chat 3-phase flow
# Send a message in Council Chat; verify all 3 phases complete < 90s

# 8. agents summary
walter-os agents summary --since "$(date -u +%Y-%m-%dT00:00:00Z)"
# Expected: sections present, shows the run that just completed
```

---

## Troubleshooting quick reference

| Symptom | First check | Fix |
|---|---|---|
| Grafana shows "No data" for council metrics | `curl walter-vm:9100/metrics \| grep walter_council` | If empty: node-exporter textfile collector path mismatch. Verify volume mount in compose |
| `walter-os spend report` returns empty | `curl litellm:4000/spend/tags` returns 404 | Enable `store_model_in_db: true` in litellm/config.yaml, restart |
| Lesson writes hang | `curl litellm:4000/v1/embeddings` times out | Embedding model unreachable. Fix M-prereq-4. System falls back to FTS5 |
| Watchdog deletes non-zombie issues | `cat /var/log/walter-council/watchdog.log \| jq .` | Heartbeat file path mismatch. Check `WALTER_COUNCIL_DATA_DIR` env var |
| Trust gate allows everything | `cat ~/.config/walter-os/trust-tiers.yml` malformed | Re-copy from `setup/templates/trust-tiers.yml` |
| Council panic lock stuck | `ls ~/.config/walter-os/gate.lock` | `walter-os agents unlock --reason "<reason>"` |
| Control Tower 403 on Tailscale | Middleware IP check | Verify Tailscale CGNAT range `100.64.0.0/10` matches your device IP: `tailscale ip -4` |
| Council Chat stuck after Round 1 | LiteLLM timeout on R2 | Check per-agent timeout in `council-personas.ts` — 25s per agent |
| Consensus vote never resolves | Vote log shows abstains | LLM timed out for voting agents (15s limit). Check LiteLLM load |

---

## Maintenance cadence

| Frequency | Task |
|---|---|
| After each merge | Mark the phase row in `council-v2-prereqs.md` status board as `[x]` |
| Weekly | Review wiki consolidation report in Plane (label: `wiki:consolidation`) |
| Weekly | `walter-os agents status` — check zombie count trend |
| Monthly | Review `trust-tiers.yml` — adjust tiers if agent behavior warrants it |
| Monthly | `walter-os lessons list --last 30d` — prune lessons with confidence 0 |
| Quarterly | `walter-os spend report --by-agent --last 90d` — verify no agent is drifting on cost |
| Quarterly | `sqlite3 ~/.config/walter-os/lessons.db "DELETE FROM lessons WHERE confidence < 0.3 AND created_at < date('now','-90 days')"` — prune stale lessons |
