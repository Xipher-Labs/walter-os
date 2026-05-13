# Future Implementations Roadmap

**Generated**: 2026-05-11
**Branch**: `docs/future-roadmap` (audit pass — read-only, no code changes)

---

## Sources audited

- `docs/specs/multi-agent-autonomy.md` (Phase O1–O5)
- `docs/specs/secrets-runtime-architecture.md` (Phase A–D)
- `docs/specs/karpathy-llm-wiki-compliance.md` (Phase WK1–WK4)
- `docs/specs/homelab-topology.md` (Phase Z1–Z6)
- `docs/specs/archive/local-llm-node.md` (Phase L1–L4)
- `docs/specs/archive/standby-node-replication.md` (Phase R1–R8)
- `.claude/worktrees/pr-31-fixes/docs/specs/walter-council-v2.md` (Improvements 1–9 + Control Tower) — **in-flight, not merged**
- `.claude/worktrees/pr-31-fixes/docs/specs/devrel-analytics-stack.md` — **proposal, not approved**
- `docs/operational/onboarding-checklist.md`
- `docs/operational/operator-setup-runbook.md`
- `docs/operational/known-issues.md`
- `.claude/projects/…/memory/project_walter_os_backlog.md`
- `skills/` — grep for TODO/FIXME/deferred
- `scripts/` — grep for TODO/FIXME
- `skills/infisical-agent/SKILL.md`, `skills/deepsec-integration/SKILL.md`

---

## Total deferred items: 62

---

## 1. Operator setup — pending first-time actions (P0)

These items are documented and scripted; only operator-time blocks them.

| Item | Source | Time |
|---|---|---|
| Secrets runtime cutover (Yubikey → Keychain → Infisical, no more secrets.env) | `operator-setup-runbook.md` step 1 | 15 min |
| `ANTHROPIC_ENTERPRISE_KEY` pushed to Infisical, wired to work/ context | step 2 | 5 min |
| Codex enterprise login for `~/.codex-work/auth.json` | step 3 | 5 min |
| Tailscale via Headscale — Mac enrolled in the mesh | step 4 | 10 min |
| First wiki `/ingest` + private `walter-wiki` Forgejo repo creation | step 5 | 15 min |
| Restic → B2 offsite backup (rclone config + repo init + cron + restore test) | step 6 | 45 min |
| Grafana community dashboards import (IDs: 1860, 14282, 179, 13639) | step 7 | 10 min |
| CCR design decision: Mac-local proxy vs API-key-only; remove or configure walter-vm CCR container | `onboarding-checklist.md` CCR section | 15 min (decision) |

**Blockers**: operator availability only. All scripts and docs are written.
**Total**: ~2 hours operator time.

---

## 2. Secrets runtime (specs approved, implementation pending)

Spec: `docs/specs/secrets-runtime-architecture.md`. Status: Approved. Implementation = follow-up PR.

| Phase | What | Effort |
|---|---|---|
| **A** | Create Infisical Machine Identity; write JSON blob to macOS Keychain with Yubikey ACL | 2h |
| **B** | Add `walter_secrets_load` zsh function + `85-secrets-runtime.zsh` template; deprecate `80-secrets.zsh` direct source; add `walter-os secrets-status` / `secrets-clear` subcommands | 3h |
| **C** | Cutover: `srm secrets.env`; update `install.sh` to stop generating the template | 1h |
| **D** | Second device (future second Mac): per-device Machine Identity | 1h (when device exists) |
| Linux equivalence | `pass` + GPG smartcard on standby homelab node/Z440; out of scope for v1 | deferred |

**Effort total (A–C)**: ~6h implementer + 30min operator.

---

## 3. Walter Council — multi-agent autonomy (Phase O1–O5)

Spec: `docs/specs/multi-agent-autonomy.md`. Status: Approved, decisions locked. **Nothing implemented yet beyond primitives.**

| Phase | What | Effort | Blockers |
|---|---|---|---|
| **O1** — Foundation | `walter-os agents` CLI; agent-worker runner (`scripts/agents/run.sh`); LiteLLM virtual keys per agent; `hooks/approval-gate.sh`; max-runtime watchdog; Plane `agent-tasks` workspace | 1 week | Plane workspace + labels (operator action, 15 min) |
| **O2** — Specialists | `triage`, `researcher`, `coder`, `reviewer` agents as SKILL.md + wrapper scripts; label-driven dispatch | 3–5 days | O1 done |
| **O3** — Triggers | n8n workflows: cron, GitHub webhook, email, Telegram, Plane webhook; janitor cron | 3–5 days | n8n first-run (operator, 5 min); GitHub webhook secrets (operator, 10 min/repo) |
| **O4** — Operator UX | `liaison` agent + daily 08:30 digest; Telegram interactive reply routing; `walter-os agents status` dashboard | 3 days | O3 done |
| **O5** — Cross-machine + subscription pool | Workstation-side coder in worktree loop; macOS subscription host CCR containers (7 proxies); per-context auth selection; sensitive projects → local Ollama routing | 1 week | Subscription host on Headscale; browser sessions per subscription; ToS acknowledgement doc |

**Effort total**: ~4 weeks implementer. Operator overhead: ~1.5h one-time setup.

---

## 4. Walter Council v2 (in-flight spec, not yet merged)

Spec: `.claude/worktrees/pr-31-fixes/docs/specs/walter-council-v2.md`. Status: Draft (PR not merged). Depends on O1–O5 being live.

### Improvement 1: Council Observability (Prometheus + Grafana)
- Prometheus metrics from agent runner; Grafana "Walter Council" dashboard (6 panels)
- **Effort**: 3h. **Blocker**: Grafana datasource prereq (F-prereq-1/2/3 in `council-v2-prereqs.md`, operator, 15 min)

### Improvement 2: Cost attribution per agent
- Add `task_id`, `context` tags to every LiteLLM call; `walter-os spend report` command
- **Effort**: 4h. **Blocker**: I1 done.

### Improvement 3: Wiki weekly consolidation job
- Cron job: embedding-based dedupe proposals, contradiction detection, stale page marking
- **Effort**: 8h. **Blocker**: standby homelab node Ollama running (for embeddings). Wiki with ≥20 pages.

### Improvement 4: Cross-agent learning broker
- `lessons.db` SQLite; `lesson_write`/`lesson_query` in `scripts/agents/lib/lessons.sh`; system-prompt injection of top-5 lessons per task
- **Effort**: 8h. **Blocker**: embedding service on standby homelab node or Walter-VM.

### Improvement 5: Heartbeat + zombie watchdog
- Agent writes heartbeat JSONL every 60s; watchdog cron re-enqueues zombie issues
- `files_touched` and `tests_run` fields are **PARTIAL stub only** — full instrumentation requires Claude Code tool-call hooks not yet exposed
- **Effort**: 6h (partial, ~2h for stub fields when hooks exist). **Blocker**: Plane `awaiting-resume` state (operator, 5 min).

### Improvement 6: Project induction skill
- `walter new project <type> <name>` interactive interview; generates repo `AGENTS.md`, charter spec, Plane epic
- `financial-data-compliance` skill referenced in AC-5 is **explicitly deferred** (spec TBD at `docs/specs/financial-data-compliance.md`)
- **Effort**: 8h (skill implemented); financial-data-compliance skill separately 16h.

### Improvement 7: Trust calibration per agent
- `trust-tiers.yml`; `approval-gate.sh` reads trust tier before block/allow; `ADR-0009-agent-trust-tiers.md`
- **Effort**: 4h.

### Improvement 8: Hierarchical failure mode signaling
- `alert_emit <tier> <msg>` in `scripts/agents/lib/alerts.sh`; 4 tiers (info/warn/critical/panic); panic auto-pauses Council
- **Effort**: 5h.

### Improvement 9: Council consensus mode
- `walter-os mode consensus on/off`; Council vote for routine tasks when operator away; `awaiting-consensus` Plane state
- **Effort**: 8h. **Blocker**: Plane states (operator, 10 min); I7 done (trust tiers inform voting).

### Control Tower (Part B)
- Next.js 15 app on walter-vm: Agent Status Board, Decision Timeline, Grafana embed, Cost Dashboard, HA Status, Alert Feed, Council Chat (3-phase deliberation), Ideation Session
- **Effort**: 3–4 weeks implementer. **Blocker**: I1–I9 done; Postgres `control_tower` DB + session secret (operator, 10 min); Tailscale ACL update (operator, 10 min).

**v2 total effort**: ~10–12 weeks implementer (all improvements + Control Tower). Parallelizable across 4–5 weeks with multiple agents.

---

## 5. Karpathy wiki (approved spec, not implemented)

Spec: `docs/specs/karpathy-llm-wiki-compliance.md`. Status: Approved. Implementation = follow-up phases.

| Phase | What | Effort |
|---|---|---|
| **WK1** | Create `wiki/` dir, `SCHEMA.md`, `index.md`, `log.md`; gitignore from public repo; Forgejo private mirror | 3h |
| **WK2** | Skills: `wiki-ingest`, `wiki-query`, `wiki-lint` implemented + symlinked | 1–2 days |
| **WK3** | `/ingest` slash command; `walter-os wiki {ingest,query,lint,status}` subcommands | 1 day |
| **WK4** | `contexts/wiki/AGENTS.md` overlay; `wiki-validity-gate.sh` hook; `memory` MCP indexing | 1 day |

**Effort total**: ~4–5 days implementer. Operator action: create `walter-wiki` Forgejo repo (15 min).

---

## 6. Hardware deployments

### standby homelab node — optional rack server profile

Spec: `docs/specs/archive/local-llm-node.md`.

| Phase | What | Operator time | Agent time |
|---|---|---|---|
| **L1** | Proxmox VE 8 install; ZFS RAIDZ2 pool; Headscale join; restic-target LXC | ~3h | 0 |
| **L2** | HomeAssistant OS VM; Whisper/Piper add-ons; Zigbee dongle migration | ~5h | 0 |
| **L3** | Ollama LXC (models: llama3.3:70b, qwen2.5-coder:32b, nomic-embed-text); HA Ollama integration; Jarvis tool palette | ~4h + 4h implementer | 4h |
| **L4** | Restic primary repo + cron; DR drill (restore walter-vm from standby homelab node to fresh CX53) | ~3h | 2h |

**Total**: ~15h operator + 6h implementer. Open questions: GPU-now-or-later; deployment location for the rack unit.

### Z440-class GPU inference box

Spec: `docs/specs/homelab-topology.md` §4–6.

| Phase | What | Effort |
|---|---|---|
| **Z1** | Parts acquisition: Z440-class chassis (~€500), 2× RTX 3090 (~€700–900 each used), 1200W PSU (~€200), 64–128 GB DDR4 ECC, 2× NVMe 2TB | ~€2000–2500 spend + sourcing time |
| **Z2** | Ubuntu 22.04 LTS + NVIDIA 550+ driver + CUDA 12.4 + Tailscale | ~4h operator |
| **Z3** | vLLM serving Qwen-Coder-32B AWQ; OpenAI-compat API on :8000; benchmark ~80–100 tok/s | ~2h |
| **Z4** | LiteLLM integration: `coder` + `local-fast` routes to Z440 | ~1h |
| **Z5** | Two vLLM systemd units (coder-32B + llama-70B-on-demand) | ~2h |
| **Z6** | Redis cache on walter-vm for LiteLLM response deduplication | ~30 min |

**Total**: ~€2000–2500 hardware + ~10h operator. **Blocker**: hardware acquisition (operator decision on used 3090 vs new 4090; PSU wattage; NVLink bridge).

### standby homelab node ↔ Walter-VM active replication + CF Load Balancer

Spec: `docs/specs/archive/standby-node-replication.md`.

| Phase | What | Effort |
|---|---|---|
| **R1** | Walter-VM Postgres primaries: `wal_level=replica`, replication user, pg_hba | 30 min |
| **R2** | standby homelab node standby init: `pg_basebackup` for Infisical, Plane, Forgejo | 2h |
| **R3** | App warm-standby containers on standby homelab node (read-only mode) | 3h |
| **R4** | standby homelab node cloudflared tunnel + service hostname mapping | 1h |
| **R5** | Cloudflare Load Balancers × 5 (Infisical, Plane, Forgejo, LiteLLM, Synapse) | 2h |
| **R6** | `walter-os ha promote/failback` scripts with split-brain checks | 4h |
| **R7** | Failover drill + timing documentation + `docs/operational/dr-runbook.md` | 2h |
| **R8** | Tier-B (Synapse, OpenClaw, LiteLLM) | 4h |

**Total**: ~18h implementer. **Cost delta**: ~$25/mo CF Load Balancer. **Blocker**: standby homelab node online (L1 done).

---

## 7. Operator-pending known issues

From `docs/operational/known-issues.md`:

| Issue | Impact | Fix complexity |
|---|---|---|
| CCR daemon on walter-vm won't bind TCP:3456 reliably | Subscription proxy unusable until fixed | Small: replace `ccr start` with direct `node cli.js` invocation |
| Headscale admin UI at `/admin/` not `/` | Inconvenient URL | Tiny: Caddy/nginx 301 redirect or cloudflared originRequest path rewrite |
| OpenAI / Google / Claude subscription proxies not implemented | O5 subscription pool blocked | Medium: OpenAI alternatives unstable; blocked until stable proxy exists |

---

## 8. Inline TODO markers (code)

| File | TODO | Category |
|---|---|---|
| `skills/infisical-agent/SKILL.md` (line 306–309) | deploy.sh agent integration, GitHub Actions examples, n8n workflow templates | Docs/examples |
| `skills/deepsec-integration/SKILL.md` (line 97) | `scripts/walter/subcommands/audit-deep.sh` not implemented | P1 security |
| `skills/project-induction/scripts/induction.sh` (pr-31 worktree, lines 300–304) | `financial-data-compliance` skill stub + spec TBD | P2 compliance |

---

## 9. Deferred skills (backlog memory — 27 items)

From `project_walter_os_backlog.md` + AGENTS.md context files. Intentionally not written until a concrete trigger event occurs.

### Engineering / [Company] (6)
`ansible-playbook-review`, `baremetal-runbook`, `incident-postmortem`, `sre-on-call`, `runbook-writer`, `release-notes`

### DevRel (8)
`devrel-content-pipeline`, `competitor-watch-helius-quicknode`, `video-script-solana`, `youtube-seo-shorts`, `youtube-thumbnail-prompt`, `content-calendar-builder`, `seo-keyword-research`, `social-media-thread-writer`

### Product / business (5)
`prd-writer`, `pitch-deck`, `landing-page-fast` (partially done), `gtm-strategy`, `customer-interview-synthesizer`

### Branding (2)
`brand-manual`, `logo-iteration`

### Cross-cutting (6)
`elevenlabs-voiceover`, `remotion-video`, `n8n-workflow-design`, `gdrive-asset-upload`, `obsidian-note-format`, `financial-data-compliance`

**Policy**: write on-demand, not proactively. See backlog memory file for trigger criteria.

---

## 10. DevRel analytics stack (proposal, not approved)

Spec: `.claude/worktrees/pr-31-fixes/docs/specs/devrel-analytics-stack.md`. Status: **PROPOSAL — awaiting operator approval.**

- Postgres `analytics_events` table + cron adapters (Twitter/X, YouTube, Plausible, GitHub, Postiz)
- Twitter/X cost decision blocked (Option A: $200/mo official API; Option B: socialdata.tools $50/mo; Option C: manual export for 4-week validation)
- `analyst` agent as 7th Council member — upgrade from skill if proactive value proven after 1 month of data
- **Effort**: 2–3 weeks implementer (Phase 1: Twitter+YouTube+Plausible+GitHub). **Blocker**: operator approves proposal + decides Twitter API spend tier.

---

## 11. Infrastructure stubs / partial implementations

| Item | Status | Effort |
|---|---|---|
| `walter-os enable-hook` / `disable-hook` subcommands | Stubbed, not built | Small (3h) |
| Tool-definition drift check in `audit.sh` | Placeholder — needs MCP introspection plumbing | Medium (8h) |
| Bulk pre-install snapshot in `install.sh` | Deferred; per-file backup via `link_safe` is adequate | Low priority |
| `docs/operational/dr-restore.md` (DR recovery procedure doc) | Referenced in runbook step 6h but not yet written | Small (2h) |
| Grafana dashboards exported to `setup/walter-host/services/observability/grafana/provisioning/dashboards/` | Manually imported; not committed | Small (1h) |
| `setup/local-llm-node.md` superseded notice | Old file still exists; spec says replace with thin pointer | Tiny (15 min) |
| Postiz analytics export configuration | Mentioned in homelab topology; no implementation | Medium (depends on Postiz API) |
| Singer LinkedIn tap workflow | devrel-analytics spec Phase 2; LinkedIn API approval pending | Deferred |

---

## Priority categorization

| Priority | Bucket | Count | Notes |
|---|---|---|---|
| **P0** (blocking release or security) | Operator setup steps 1–4 (secrets, enterprise key, Codex login, Headscale); CCR TCP:3456 bug | 5 | Everything downstream depends on secrets runtime being secure |
| **P1** (next 4 weeks) | Secrets runtime implementation (phases A–C); Wiki WK1–WK4; Walter Council O1–O2; `deepsec` audit-deep.sh; DR runbook doc | ~12 | Foundation layer for all agentic work |
| **P2** (next quarter) | Council O3–O5; standby homelab node L1–L4; standby homelab node replication R1–R7; Council v2 improvements 1–5 | ~25 | Requires standby homelab node physical setup + O1 running |
| **P3** (next 6 months) | Z440 hardware + Z1–Z6; Council v2 improvements 6–9; Control Tower; DevRel analytics (post-approval) | ~15 | Hardware acquisition + O5 subscription pool |
| **P4** (backlog, trigger-driven) | 27 deferred skills; infrastructure stubs; LinkedIn tap | ~20 | Write when needed |

---

## Effort estimates aggregate

| Category | Implementer hours | Operator hours | Money |
|---|---|---|---|
| Operator setup (P0) | 0 | ~2h | $0 |
| Secrets runtime (phases A–C) | 6h | 0.5h | $0 |
| Wiki WK1–WK4 | 32h | 0.5h | $0 |
| Council O1–O5 | ~160h (4 weeks) | ~2h | $0 |
| Council v2 (all improvements + Control Tower) | ~280h (7 weeks) | ~1h | $0 |
| standby homelab node L1–L4 (hardware in hand) | 6h | ~15h | $0 |
| standby homelab node replication R1–R8 | 18h | ~1h | ~$25/mo CF LB |
| Z440 hardware + Z1–Z6 | 10h | ~10h | €2000–2500 hardware |
| DevRel analytics Phase 1 (post-approval) | ~80h (2 weeks) | 1h | $0–$200/mo Twitter API |
| **Total** | **~600h (~15 weeks)** | **~33h** | **€2000–2500 + $25–225/mo recurring** |

Applying 30% uncertainty padding: **~800h implementer, ~43h operator**.

---

## Recommended next 3 actions

**1. Execute operator setup P0 in one sitting (~2h)**
Steps 1–4 of `docs/operational/operator-setup-runbook.md`: secrets runtime keychain init, enterprise key, Codex login, Headscale enrollment. These unblock everything downstream and close the plaintext-secrets-on-disk security gap that's been open since May 5.

**2. Implement secrets runtime phases A–C and wiki WK1–WK4 in parallel (~1 week)**
Both are documented specs with locked decisions and zero hardware dependencies. Secrets runtime closes the P0 security item. Wiki bootstrap is the foundation for the cross-agent learning broker (Council v2 Improvement 4) — the longer it's delayed, the less compound knowledge accumulates. Both can be parallelized with git worktrees.

**3. Start Walter Council O1 (Foundation)**
The agent runner, approval gate, LiteLLM virtual keys, and Plane workspace setup are the critical path for everything in sections 3, 4, and 10. Without O1, Council v2 improvements are theoretical. Operator action is minimal (Plane workspace + labels: 15 min). Implementer can start immediately after.

---

## Surprises found during audit

- The `agent-secret-redactor.sh` Perl regex bug (the pipe-delimiter clash) is **already fixed** in main. No chip needed. The fix was the `s{...}{...}` delimiter change documented in the script header.
- "Pin all MCP server versions" chip: the skill file `skills/web-security-baseline/SKILL.md` references this as a best practice, but there is no open chip or TODO in the current `main` codebase. Likely already in the backlog memory context — no active blocker found.
- `walter-council-v2.md` and `devrel-analytics-stack.md` exist only in worktrees (`pr-31-fixes`) — they are not on `main` yet. If those PRs stall or get abandoned, the specs disappear from the repo. They should be merged to `main` as draft specs regardless of implementation status.
- The backlog lists `landing-page-fast` as "deferred" but `skills/landing-page-fast/SKILL.md` already exists (it was written). The backlog is stale on this entry.
- standby homelab node is described as optional future hardware and has 0 phases implemented. It's the single most valuable unblocked hardware item since it unlocks: local Ollama for PHI, Jarvis, Restic primary, and the HA replication spec.
