# docs/operational — Runbooks and Operational Docs

These docs are for the operator, not for readers of the codebase. Each one has
commands, expected outputs, and troubleshooting. The audience is a technical operator
(or at 3am).

| Doc | Description |
|---|---|
| [`requirements.md`](requirements.md) | Minimum local tools, optional profile dependencies, and the manifest map for macOS, Node, Python, and Docker surfaces |
| [`council-v2-prereqs.md`](council-v2-prereqs.md) | Manual operator prereqs required before each Council v2 phase can land: Grafana datasources, Plane custom states, Postgres databases, Infisical secrets, Tailscale ACL. Includes status board (`[ ]` / `[x]` per phase) |
| [`council-v2-deployment-runbook.md`](council-v2-deployment-runbook.md) | Step-by-step merge order (F→M→R→T→U→V), pre-merge checklist, post-merge verification commands, rollback per phase, and maintenance cadence |
| [`control-tower-runbook.md`](control-tower-runbook.md) | Control Tower ops: start/stop, update container, SSE disconnect recovery, panic lock recovery, Council Chat troubleshooting, Grafana embed issues |
| [`phase-v-tools-availability.md`](phase-v-tools-availability.md) | DevRel analytics tools availability: which Twitter/LinkedIn/Meta API approvals are pending, current workarounds, expected timelines |
| [`operator-setup-runbook.md`](operator-setup-runbook.md) | Fresh operator setup walkthrough: OS credential-store secrets bootstrap, Infisical auth, Claude Code auth, multi-account bootstrap, cross-device sync wiring |
| [`onboarding-planner.md`](onboarding-planner.md) | Read-only planner for adding a second device or teammate to an existing Walter domain |
| [`repo-config.md`](repo-config.md) | `walter-repo-config.yaml` validation, safe defaults, and non-overridable autonomy policy limits |
| [`onboarding-checklist.md`](onboarding-checklist.md) | One-page checklist for the operator: what to do in order on a new machine. Companion to `operator-setup-runbook.md`. <!-- TODO: stale, verify --> Service health snapshot is dated 2026-05-05; does not include Control Tower, analytics Postgres, or Council v2 Plane states. Update after Council v2 PRs merge. |
| [`postiz-analytics-export.md`](postiz-analytics-export.md) | How to export Postiz analytics for manual ingestion into the DevRel analytics Postgres (Phase V workaround while Twitter API approval is pending) |
| [`known-issues.md`](known-issues.md) | Active known issues on Walter-VM: claude-code-router daemon bind issue, headscale-admin `/admin/` path quirk, subscription proxy status |
| [`v0.6.2-release-notes.md`](v0.6.2-release-notes.md) | Patch-release notes for immutable v0.6.1 tag reconciliation, Headscale routing/diagnostics, Cloudflare CI routing, and local preview adapter |
| [`v0.6.1-release-notes.md`](v0.6.1-release-notes.md) | Patch-release notes for provider selection, audit-chain hardening, upgrade commands, and remaining security follow-ups |
| [`ai-capability-profiles.md`](ai-capability-profiles.md) | Operator AI runtime availability profiles, `walter ai configure`, and private capability metadata |
| [`multi-model-routing.md`](multi-model-routing.md) | Task-domain model routing, `WALTER_MODEL_*` preferences, override rules, and PHI/local safeguards |
| [`scorecard-hygiene.md`](scorecard-hygiene.md) | OpenSSF Scorecard alert disposition for project hygiene, including code-visible fixes and manual GitHub settings |
| [`openssf-badge-filing-runbook.md`](openssf-badge-filing-runbook.md) | Manual OpenSSF Best Practices badge filing steps, approval evidence capture, and post-approval README/Scorecard updates |
| [`pinned-dependency-alerts.md`](pinned-dependency-alerts.md) | Documented dispositions for pinned dependency, release action, and upstream workflow warnings |
| [`capability-tokens.md`](capability-tokens.md) | Capability-token runtime state, daily-audit hygiene checks, and operator recovery steps |
| [`enforcement-mode.md`](enforcement-mode.md) | `walter doctor --enforcement`, hook visibility, wrapper checks, and policy-only vs enforced modes |
| [`anthropic-skills-delta-audit.md`](anthropic-skills-delta-audit.md) | Delta audit for upstream `anthropics/skills` versus plugin-exposed Anthropic skills |
| [`hosting-providers-comparison.md`](hosting-providers-comparison.md) | VPS/cloud provider comparison for Walter-OS v0.2.0 adopters: specs, pricing, gotchas, and portability notes. Hetzner is default reference; 10 alternatives documented. |
| [`knowledge-profile.md`](knowledge-profile.md) | Decision guide for Outline + Linkwarden versus Obsidian in personal, startup, and small-team installs |
| [`universal-vs-personal-config.md`](universal-vs-personal-config.md) | What lives in the public repo vs your personal overlay (`~/.config/walter-os/overlay/`). Includes full decision table and upgrade semantics. |
| [`multi-device-sync.md`](multi-device-sync.md) | Syncthing setup walkthrough for multi-device operators. What to sync, conflict resolution, alternative mechanisms, and hub topology. |
| [`langfuse.md`](langfuse.md) | Optional Langfuse profile runbook: traces, evals, backups, retention, and when the operational cost is worth it. |

> **Note**: `phase-v-tools-availability.md` and `postiz-analytics-export.md` live in
> the `feature/council-v2-analytics` branch. They will land in `docs/operational/`
> when Phase V merges. <!-- TODO: stale, verify --> Confirm both files exist after the Phase V PR merges.
