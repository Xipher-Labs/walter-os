# Walter-OS — Tier IV install via agent

> **For**: operators who already ran Tier III and want the full agent
> autonomy layer — Walter Council (6 specialized agents), n8n
> workflows, Plane workspace structure, Control Tower dashboard.
>
> **Time**: ~2–3 hours on top of Tier III.
>
> **Costs money**: ~$10–$50/month additional LLM API spend (depends
> on agent activity). Per-agent virtual keys cap this.
>
> **Prereqs**:
> - Tier I + II + III installed and verified.
> - Plane admin user created (manual, via UI).
> - Forgejo admin user created.
> - LiteLLM at https://llm.${WALTER_DOMAIN} reachable.
> - At least one LLM provider key (Anthropic / OpenAI / Gemini) in
>   Infisical at `walter-shared/prod/`.
>
> **How to use**: paste the entire fenced block below.

---

```
================================================================================
WALTER-OS TIER IV INSTALL — Council + automation

You are wiring the Walter Council, n8n workflows, Plane workspace,
and Control Tower on top of Tier III.

What gets configured:
  - 6 Council agents with per-agent LiteLLM virtual keys + trust tiers:
      reviewer    (high trust — read-only audits)
      triage      (medium  — Plane label routing)
      researcher  (medium  — wiki writes)
      coder       (medium  — PR drafts)
      liaison     (low     — public communication, gated)
      janitor     (low     — destructive cleanup, gated)
  - Plane workspace `agents` per docs/specs/multi-agent-autonomy.md
    with TWO label dimensions:
      context:{work,projects-personal,personal,medical}
      lane:{research,code,review,janitor,digest,triage}
  - n8n workflows:
      - Daily 08:30 audit trigger (calls daily-supply-chain-audit)
      - Plane webhook → agent dispatch
      - Weekly OKR digest → Telegram
      - PR opened → reviewer agent
  - Control Tower dashboard (apps/control-tower/) deployed at
    https://tower.${WALTER_DOMAIN} via `docker compose --profile tier4
    up -d` (added on top of the Tier III profile selection).
  - approval-gate.sh hook policy live for destructive actions.

GROUND RULES — autonomy increases here
- Council agents can act unattended on Plane issues with the right
  label.
- Every action in the "blocked for ALL tiers" list (see AGENTS.md)
  goes through approval-gate.sh regardless of agent trust tier.
- The agent installing Tier IV does NOT run any Council agent. It
  only CONFIGURES them. First runs are manually triggered by the
  operator from Control Tower → New Task.

================================================================================
PRECHECK

  walter-os doctor --tier 3                  # expect all ✓
  curl -sf https://llm.${WALTER_DOMAIN}/health  # expect 200 (LiteLLM)
  curl -sf https://plane.${WALTER_DOMAIN} -o /dev/null \
       -w '%{http_code}\n'
  # expect: 302 (CF Access login redirect)

================================================================================
STEP 1 — LITELLM VIRTUAL KEYS PER COUNCIL AGENT

The operator opens https://llm.${WALTER_DOMAIN} (Tailscale or CF
Access) and creates 6 virtual keys via the UI. Each key has:
  - Name: <agent-name>-agent
  - Budget: per-agent cap (default $20/mo coder, $10/mo each for
    others)
  - Models: per-tier allowlist (high-trust agents get more powerful
    models; low-trust agents get cheaper/faster)
  - TPM/RPM limits matching budget

Ask the operator to create the 6 keys and paste each one back:
  → LITELLM_REVIEWER_KEY
  → LITELLM_TRIAGE_KEY
  → LITELLM_RESEARCHER_KEY
  → LITELLM_CODER_KEY
  → LITELLM_LIAISON_KEY
  → LITELLM_JANITOR_KEY

Push all 6 to Infisical at:
  walter-vm-internal/prod/council/LITELLM_<AGENT>_KEY

================================================================================
STEP 2 — PLANE WORKSPACE STRUCTURE

The operator creates (via Plane UI, manual):
  - Workspace named `agents`
  - Inside it, ONE project per life/work area (these align with the
    `context:*` labels from docs/specs/multi-agent-autonomy.md):
      * work
      * projects-personal      ← canonical form, NOT "personal-projects"
      * personal
      * medical                ← optional, only if operator has medical
                                  projects (auto-loads
                                  medical-data-compliance skill)
  - Labels — TWO dimensions per the spec:
      Dimension A (context):  context:work, context:projects-personal,
                              context:personal, context:medical
      Dimension B (lane):     lane:research, lane:code, lane:review,
                              lane:janitor, lane:digest, lane:triage

Ask the operator to confirm the workspace + projects + labels are
created.

Walter-OS does NOT ship a CLI subcommand for bootstrapping Plane
labels today. The real `walter-os agents` dispatcher only supports
`{list|run-once|pause|resume|status}` (see `scripts/agents/main.sh`).
The operator creates the labels by hand from the Plane settings UI,
or via direct API calls using `curl` + the token in Infisical at
`walter-vm-internal/prod/plane/PLANE_API_TOKEN`.

If you want to script it inline, here's the minimum:

  # Fetch the token from Infisical via its CLI. `walter-os secrets-pull`
  # is a Bitwarden helper and doesn't fetch a specific Infisical key
  # — use the `infisical` CLI directly (installed in Tier I prereqs).
  TOKEN=$(infisical secrets get PLANE_API_TOKEN \
            --env=prod --path=/plane --plain 2>/dev/null)
  for ctx in work projects-personal personal medical; do
    curl -sS -X POST "https://plane.${WALTER_DOMAIN}/api/v1/workspaces/agents/labels/" \
      -H "x-api-key: $TOKEN" -H "Content-Type: application/json" \
      -d "{\"name\": \"context:${ctx}\"}"
  done
  for lane in research code review janitor digest triage; do
    curl -sS -X POST "https://plane.${WALTER_DOMAIN}/api/v1/workspaces/agents/labels/" \
      -H "x-api-key: $TOKEN" -H "Content-Type: application/json" \
      -d "{\"name\": \"lane:${lane}\"}"
  done

A dedicated CLI subcommand for label bootstrapping is a reasonable
future enhancement; not in scope for this tier.

================================================================================
STEP 3 — TRUST TIERS

Write the trust tier config:

  ~/.config/walter-os/trust-tiers.yml:
    reviewer:   high
    triage:     medium
    researcher: medium
    coder:      medium
    liaison:    low
    janitor:    low

Ask if the operator wants to override any. Recommended: accept
defaults on first install, adjust later after seeing behavior.

Verify the trust tiers loaded — no dedicated subcommand exists for
this today, so just read the file:
  cat ~/.config/walter-os/trust-tiers.yml
  # expect: a 6-row YAML with one line per agent (reviewer, triage,
  # researcher, coder, liaison, janitor) each mapped to a tier
  # (high|medium|low).

================================================================================
STEP 4 — APPROVAL GATE

The approval-gate.sh hook is the safety floor for ALL agents
regardless of trust tier. It hard-blocks:
  - push to main/staging/release
  - merge PRs
  - force-push any branch
  - modify hooks/, AGENTS.md, install.sh, mcp/servers.json
  - modify agent definitions
  - destructive shell (rm -rf, dd)
  - SQL destructive (DROP, TRUNCATE, DELETE FROM)
  - money-spending actions
  - public communication
  - auth/crypto/PHI files
  - production DB migrations

Verify it's installed (the install.sh --upgrade step from Tier I-II
should already have done this):
  ./hooks/approval-gate.sh --self-test
  # expect: "OK (N test cases)"

If it returns errors or the file is missing, re-run install.sh
--upgrade from the walter-os clone.

================================================================================
STEP 5 — n8n WORKFLOWS

Three default workflows ship in
setup/walter-host/services/n8n/workflows/:
  1. daily-audit-trigger.json     — cron 08:30 → daily-supply-chain-audit
  2. plane-webhook-dispatch.json  — Plane issue webhook → agent claim
  3. weekly-okr-digest.json       — Friday 17:00 → OKR retro → Telegram

Import them via the n8n CLI script on the VM:
  ssh root@<vm-ip>
  cd /opt/walter-os
  ./setup/walter-host/services/n8n/import-workflows.sh

The script reads each JSON, creates the workflow via the n8n API, and
activates it. Credentials it expects in Infisical:
  - n8n_telegram_bot       (for OKR digest → Telegram)
  - n8n_plane_api          (for Plane webhook validation)
  - n8n_walter_council     (HTTP call into Council dispatcher)

Verify after import:
  curl -sf -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "https://n8n.${WALTER_DOMAIN}/api/v1/workflows" \
    | jq '.data | length'
  # expect: ≥ 3

================================================================================
STEP 6 — CONTROL TOWER (gated behind --profile tier4)

control-tower has `profiles: [tier4]` in compose.yml. Tier III's
`docker compose --profile core up -d` intentionally did NOT bring it
up. Now we add it.

  6.1  Generate admin token: `openssl rand -hex 32` → push to
       Infisical at walter-vm-internal/prod/tower/CONTROL_TOWER_ADMIN_TOKEN.
  6.2  Mint Plane API token via Plane UI → push to Infisical at
       walter-vm-internal/prod/tower/PLANE_API_TOKEN.
  6.3  Mint Grafana service account token (Viewer role) via Grafana
       UI → push to Infisical at
       walter-vm-internal/prod/tower/GRAFANA_SA_TOKEN.
  6.4  Mint LiteLLM virtual key `control-tower` ($20/mo budget) →
       push to Infisical at
       walter-vm-internal/prod/tower/LITELLM_API_KEY.

Build the image locally (Control Tower isn't published to a registry):
  cd <walter-os-clone>
  docker build --platform linux/amd64 \
    -t walter-control-tower:v0.4.1 \
    -f apps/control-tower/Dockerfile .

Ship the image to the VM:
  docker save walter-control-tower:v0.4.1 | \
    ssh root@<vm-ip> "sudo docker load"

Bring it up — add tier4 to the existing profile set:
  ssh root@<vm-ip> 'cd /opt/walter-os && \
    docker compose --profile core --profile tier4 up -d'
  # add any other profiles you had enabled in Tier III after --profile core

Verify:
  curl -sf -m 5 https://tower.${WALTER_DOMAIN} -o /dev/null \
       -w '%{http_code}\n'
  # expect: 302 (CF Access)
  # then open in browser, paste admin token on first visit

================================================================================
STEP 7 — FIRST AGENT RUN

From Control Tower → Council → New Task:
  Task: "ping: write a one-sentence summary of the walter-os repo purpose"
  Lane: review
  Context: projects-personal

The reviewer agent should claim the task within 30 sec, post the
summary to the Plane issue, and close. If not:
  ssh root@<vm-ip> 'cd /opt/walter-os && \
    docker compose logs --tail=200 control-tower'

Common first-run issues:
  - LITELLM_REVIEWER_KEY budget exhausted → top up via Infisical +
    restart
  - approval-gate.sh rejecting the action → check the rule that fired
  - Plane API token expired → remint + push to Infisical

================================================================================
STEP 8 — REPORT

Print to the operator:

  ✓ Walter-OS Tier IV installed.
  ✓ Council: 6 agents configured with virtual keys + trust tiers
  ✓ Plane: workspace `agents` with 4×6 label dimensions
  ✓ n8n: 3 workflows imported + active
  ✓ Control Tower: live at https://tower.${WALTER_DOMAIN}
                  (--profile tier4 in your compose profile set)
  ✓ approval-gate.sh: active for all destructive actions
  ✓ First Council ping task: <success|failed — debug pointer>

  Final doctor check:
    walter-os doctor --tier 4
    # expect all ✓ across tiers 1–4

  Next steps:
    - From Control Tower, file your first real task with the
      appropriate `context:*` + `lane:*` labels. Watch the Decision
      Timeline tab to see how the assigned agent reasoned about it.
    - Tune trust tiers if any agent's auto-approvals feel too loose
      or too tight (~/.config/walter-os/trust-tiers.yml).
    - Set up alerting: setup/walter-host/services/alerting/ —
      Telegram bot notifications for spend, downtime, audit findings.

  Operator action items:
    - ROTATE every credential you pasted into chat during this
      install. List: <enumerate the keys>
    - Adjust per-agent budgets after a week of real traffic.

================================================================================
END
```

---

## What the operator sees

After Tier IV, in addition to Tier I+II+III:

| Concern | Where it lives |
|---|---|
| Council agents | Configured via `~/.config/walter-os/trust-tiers.yml` + per-agent virtual keys in Infisical |
| Approval gate | `hooks/approval-gate.sh` enforces hardcoded "blocked for ALL" rules |
| Plane workspace | `agents` workspace at `https://plane.${WALTER_DOMAIN}` with 4 projects (`work`, `projects-personal`, `personal`, `medical`) and 4×6 labels |
| n8n workflows | `https://n8n.${WALTER_DOMAIN}` — 3 default workflows active |
| Control Tower | `https://tower.${WALTER_DOMAIN}` — admin-token-gated, Tailscale-only by default, `--profile tier4` in compose |
| Per-agent telemetry | Cost (7D) + Decision Timeline tabs in Control Tower |

## When agents start acting unattended

The Council does NOT act on its own without an input signal. Triggers:
- **Plane label assigned** by the operator → n8n webhook → agent claim.
- **n8n cron** for scheduled work (daily audit, weekly digest).
- **Manual** from Control Tower → New Task.
- **Webhook** from external systems (PR opened, CI failed, etc.) if
  you wire it.

The agent installing Tier IV does **not** trigger any of these. First
runs are manual from Control Tower so the operator sees behavior
before turning on auto-dispatch.

## Re-running Tier IV

Re-paste to:
- Rotate per-agent virtual keys (recommended quarterly).
- Add a new agent to the Council (requires definition file in
  `agents/`).
- Re-import n8n workflows after pulling a new walter-os version.
- Adjust trust tiers based on observed behavior.

## Closing the loop

You now have the full stack. From here:
- Read `docs/operational/operator-contexts.md` for the cascade diagram.
- Run `walter-os audit` daily (the wrapper has no `run` subcommand
  — it just execs the full audit script; or let the launchd job /
  cron from Tier II do it).
- File issues in Plane with the appropriate `context:*` + `lane:*`
  labels and watch the Council pick them up.

There is no Tier V. You are done.
