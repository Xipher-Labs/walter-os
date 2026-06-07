# Persistent Feature-State Ledger

**Issue**: #227
**Roadmap**: AD-2 in `docs/specs/autonomous-delivery-roadmap.md`

## Problem

Autonomous delivery work currently spreads feature state across chat context,
Plane tickets, heartbeats, pause flags, and PR comments. That makes long-running
work brittle: when conversation context disappears, agents can lose the current
idea, acceptance criteria, tasks, risks, PR links, and post-merge status.

## Decision

Walter-OS stores feature runtime state in a repository-local ledger:

```text
.walter/features/<id>/state.yaml
```

The ledger is state, not policy. It must not authorize auto-merge, bypass
approval gates, raise capability tiers, relax hard limits, or configure
destructive actions. Per-repo policy remains in `walter-repo-config.yaml`.

## Initial CLI Contract

`walter-os feature-state init <id>` creates a ledger with these sections:

- `idea`
- `brief`
- `spec`
- `acceptance_criteria`
- `tasks`
- `decisions`
- `risks`
- `prs`
- `post_merge`

`walter-os feature-state validate [repo-or-state-file]` validates generated
ledgers and rejects policy-like override keys.

`walter-os feature-state record-post-merge <id>` appends a bounded post-merge
event so AD-13 can record health classifications without mutating external
systems.

## Acceptance Criteria

- [ ] `init` creates `.walter/features/<id>/state.yaml` with every AD-2 section.
- [ ] `validate` accepts generated ledgers and rejects missing required fields.
- [ ] Invalid feature ids cannot escape `.walter/features/`.
- [ ] Existing ledgers are not overwritten unless the caller explicitly forces
      creation.
- [ ] Post-merge classification can be recorded in `post_merge`.
- [ ] State files cannot declare hard-limit or policy override keys.
