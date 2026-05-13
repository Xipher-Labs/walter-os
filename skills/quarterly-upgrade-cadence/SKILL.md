---
name: quarterly-upgrade-cadence
description: Walter-OS update workflow — quarterly version bumps + monthly audits + weekly Renovate dashboard review. Replaces ad-hoc upgrades with predictable cadence. Use this skill when the user asks "let's run the quarterly update", "audit my stack", "what's outdated", or "time to bump versions". Includes pre-bump snapshot, tier-by-tier rollout, smoke tests, rollback procedure.
---

# Walter-OS upgrade cadence

Predictable schedule replaces ad-hoc upgrades. Aligns with Renovate
auto-PR + Walter-VM service inventory + restic backup safety net.

## Schedule

```
Weekly  (Monday 08:00 BA)
  → Renovate dashboard review (5 min)
  → Mergeable patch updates → merge to main
  → Major bumps → review release notes, defer or schedule

Monthly (1st of month, 30 min)
  → walter audit                    (supply chain scan)
  → walter status                   (service health snapshot)
  → Read /var/log/walter-watchdog.log for any silent issues
  → Check Hetzner spend trend (cron summary in Telegram)

Quarterly (1st Mon of Jan/Apr/Jul/Oct, half-day)
  → Full upgrade wave: minor + safe-major versions
  → Pre-snapshot Hetzner safety net
  → Tier-by-tier rollout w/ smoke tests
  → Post-quarter doc + changelog

Yearly (Jan)
  → Stack architecture review
  → Drop services that haven't been used 6+ months
  → Re-evaluate trust scores on all MCPs / skills (deferred backlog)
  → Rotate root credentials (all bot tokens, machine identities)
  → DR drill: restore Walter-VM from restic backup to a test VM
```

## Quarterly update — the actual flow

### Day 0 (Sunday before — prep)

```bash
# 1. Read changelogs for major bumps queued in Renovate
gh pr list --repo "${WALTER_OS_UPDATE_REPO:-<your-fork>/walter-os}" --label "major-review-needed"

# 2. Audit current versions
walter doctor                # should be all green
walter status                # all services healthy?

# 3. Take pre-quarter snapshot
walter vm snapshot pre-quarterly-$(date +%Y%m%d)
```

### Day 1 (Monday morning — Tier 1: minor patches)

Low-risk: minor + patch versions of well-known images.

```bash
# Update walter-os repo's compose files via Renovate-merged PRs
# Then push + redeploy:
walter deploy observability   # Grafana, Loki, Prometheus, etc.
walter deploy litellm
walter deploy n8n
walter deploy syncthing

# Verify each:
walter status                 # all up?
walter logs n8n 50           # any new warnings/errors?

# Smoke test:
- Send "test" to alerting bot
- Run `walter alert test` — should arrive
- Open Grafana, see 1 dashboard load
- Open Plane, create 1 throwaway issue
```

### Day 1 (Monday afternoon — Tier 2: well-known major bumps)

Major bumps where vendor docs say "drop-in safe":

```bash
walter deploy infisical       # major bump? read changelog first
walter deploy plane
walter deploy forgejo

# After each: full smoke test (above) + 30 min observation
```

### Day 2 (Tuesday — Tier 3: schema-changing majors)

Major bumps with DB migrations or breaking-change risk:

```
- Postgres major (16 → 17 → ...): pg_upgrade or dump+restore
- Synapse major: read release notes carefully, run synapse-admin to migrate
- Plane major across DB schemas: validated by Plane's own migration tool
```

For each, ALWAYS:
1. Take pre-bump snapshot (`walter vm snapshot pre-<svc>-<ver>`)
2. Read full changelog
3. Apply
4. Wait 24h, monitor

If any step fails: `hcloud server image-restore` from pre-quarter snapshot,
investigate offline.

### Day 3 (Wednesday — verification + doc)

```bash
# Full smoke test:
walter alert test              # → Telegram
walter status                  # → all healthy
ssh walter-vm 'sudo /opt/walter-vm/services/restic/restic-backup.sh daily'
                               # → backup completes, Telegram alerts ✅

# Run deepsec quick on most-changed repo (optional)
walter audit deep --quick [project-a]-web

# Document
echo "$(date +%Y-%m-%d): Quarterly upgrade complete." >> CHANGELOG.md
git add CHANGELOG.md && git commit -m "chore: quarterly upgrade $(date +%Y-Q%q)"
gh pr create --title "Quarterly upgrade $(date +%Y-Q%q)" ...

# Delete pre-quarter snapshot (only if all green for 7+ days)
hcloud image delete <pre-quarterly-id>
```

## Tier-by-tier safety classification

When deciding which tier a version bump goes to:

```
Tier 1 (minor + patch):
  - Same major, ≤ 4 minor jumps, vendor docs no breaking-change list
  - Example: postgres:16.3-alpine → 16.5-alpine
  - Verification: container starts + healthcheck passes

Tier 2 (well-known major):
  - Major bump with vendor's published "1.x → 2.x migration is auto"
  - Example: uptime-kuma 1.x → 2.x (auto-migrates DB on first 2.x boot)
  - Verification: full smoke test + 30 min observation

Tier 3 (schema-breaking):
  - DB schema migration required
  - Or: API contract change that downstream services depend on
  - Example: Postgres 16 → 17 (needs pg_upgrade)
  - Verification: 24h monitoring + smoke test all consumers
```

If you can't classify → assume Tier 3 (safer).

## Rollback procedure

If a bump breaks something:

```bash
# Quick rollback via image tag
walter deploy <svc>            # if compose has new tag, edit back to old
                               # then walter deploy applies

# Catastrophic rollback via VM-level snapshot
hcloud server poweroff walter-os
hcloud server image-restore --image <pre-quarter-snapshot-id> walter-os
hcloud server poweron walter-os
# All data restored, including running services + DBs.
# Operator: investigate offline, retry bump in next quarter.
```

## Tools used in this flow

| Tool | Where | What |
|---|---|---|
| Renovate | GH App on your walter-os fork | Auto-PR for image bumps |
| Hetzner snapshots | `hcloud server create-image` | Atomic VM rollback |
| Walter watchdog | cron on VM | Catches silent post-bump issues |
| Restic | nightly | Last-resort data recovery (separate from VM snapshot) |
| Walter doctor | local Mac CLI | Pre/post bump install validation |

## What this skill does NOT cover

- Hot-swap upgrades (zero-downtime). Walter-VM is single-host; we accept
  brief downtime per upgrade.
- Multi-region failover. Single VM, single region.
- Database query optimization post-bump. Use Grafana + Postgres slow-query
  log if perf regresses.

## References

- skills/data-migration-safety/ — when DB schema changes
- skills/daily-supply-chain-audit/ — the daily side
- skills/deepsec-integration/ — quarterly deep audit option
- .github/renovate.json — Renovate config in the repo
