# Audit telemetry → Grafana / Loki (OSS Trust B-3) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer B item B-3 (in PR #83 — not yet on `main` at the time of this spec's writing)
**Target release**: v0.6.0 (after B-1 + B-2 audit-chain lands in v0.5.x)
**Depends on**: `docs/specs/audit-chain-merkle-and-receipts.md` (B-1 + B-2 — in PR #90, also not yet on `main`; provides the JSONL source). This spec assumes that PR merges first or in the same release cycle. If you read this on `main` and the dependency hasn't landed, B-3 is blocked.

## Problem

The audit chain (B-1 + B-2) gives integrity-protected per-row logs at `~/.config/walter-os/audit/chain-YYYY-MM-DD.jsonl`, but it's per-host, per-day, file-based. Operators running Walter-OS across multiple machines (laptop + walter-vm + hackathon Linode) can't get a unified view without manually rsync'ing the JSONL files. And `cat $file | jq` is not a substitute for "show me every BLOCKED Bash op in the last 7 days, broken down by reason."

B-3 wires the chain into the existing walter-host observability stack (Grafana + Loki via Promtail) so the operator gets:
- Cross-host aggregation
- Time-series queries via LogQL
- Pre-built dashboards for the common questions

## Non-goals

- Replacing the local JSONL chain (B-1 stays the source of truth; Loki is a derived view).
- Anonymized telemetry to a central Xipher Labs service. **Operator owns their data.** No outbound aggregation.
- Real-time alerting on every block. Grafana alerting on specific patterns is opt-in via dashboard.
- Cross-operator analytics. Single-operator-per-install remains the model.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Promtail tails the operator's audit chain.** The chain lives on the host at `~/.config/walter-os/audit/chain-*.jsonl`; when Promtail runs in a container (the default in the walter-host observability stack), the operator bind-mounts that host dir to `/var/log/walter-audit/` inside the container, and Promtail's `__path__` is the container-side path. AC-1 below pins both halves of the mount. | Promtail is already in the stack. No new agent. |
| D-2 | **Per-host label**: `host=<short-hostname>` added to every shipped row. | Cross-host queries can filter. |
| D-3 | **Loki retention = 30d default**, operator-configurable via `WALTER_AUDIT_LOKI_RETENTION_DAYS`. | 30d covers most "what happened last week" queries. Operator can extend for compliance reasons. |
| D-4 | **Walter-OS audit dashboard** at `setup/walter-host/services/observability/grafana/provisioning/dashboards/walter-audit.json` (this is the actual Grafana-provisioning directory in this repo — sibling to `walter-council.json` and `walter-devrel-analytics.json`; earlier drafts of this spec referenced the non-existent `.../grafana/dashboards/` path). Provisioned automatically. **7 pre-built panels**: | Operator gets useful queries out of the box. The 7-panel count matches the enumeration immediately below; AC-2 mirrors the same set. |
|   | - Tool-call rate (events/sec, 5-min sliding window)        |  |
|   | - Block rate (events/sec, 5-min sliding, by `decision_source`) |  |
|   | - Top 10 blocked tools (week)                              |  |
|   | - Top 10 block reasons (week)                              |  |
|   | - Audit-event count by host (24h)                          |  |
|   | - Distinct sessions seen by host (24h)                     |  |
|   | - Active sessions (≥ 1 call in last 30 min)                |  |
| D-5 | **Local-only mode**: when `WALTER_AUDIT_LOKI_DISABLE=1`, Promtail tails for the audit chain are disabled. Operator who doesn't want telemetry even to their own walter-host can opt out. | Same posture as Rekor opt-in. Walter-OS doesn't push telemetry the operator hasn't accepted. |
| D-6 | **Promtail config lives in repo**: `setup/walter-host/services/observability/promtail/walter-audit-tail.yml`. Operator can edit (or extend) but won't be regenerated. | Mirrors the existing observability provisioning pattern. |
| D-7 | **Integrity preserved in Loki**: Promtail forwards the row VERBATIM including `prev_hash` + `sig`. Loki stores the line as-is. `walter-os audit verify-chain --from-loki <range>` reconstructs the chain from Loki and re-verifies. | Telemetry is a derived view, NOT a re-format. Original integrity is reproducible from the stored log. |

## Acceptance criteria

### AC-1 — Promtail tail config
- [ ] `setup/walter-host/services/observability/promtail/walter-audit-tail.yml` (new):
  - `__path__: /var/log/walter-audit/chain-*.jsonl` (operator bind-mounts `~/.config/walter-os/audit/` to `/var/log/walter-audit/` in their docker-compose overlay)
  - Adds labels: `host`, `app: walter-os`, `kind: audit-chain`
  - Forwards verbatim (no JSON re-parse — preserves `prev_hash`, `sig`, all fields)
- [ ] `setup/walter-host/services/observability/promtail/compose.yml.example` — operator instructions for mounting the audit chain dir.

### AC-2 — Grafana dashboard JSON
- [ ] `setup/walter-host/services/observability/grafana/provisioning/dashboards/walter-audit.json` (matches the existing dashboard-provisioning layout — `walter-council.json` lives in the same dir):
  - Tool-call rate: `rate({app="walter-os", kind="audit-chain"}[5m])`
  - Block rate by `decision_source`:
    `sum by (decision_source) (rate(({app="walter-os", kind="audit-chain"} | json | decision="block")[5m]))`
    — note the **parens around the entire log-stream-pipeline** before the
    range selector `[5m]`. LogQL requires the range selector to attach to
    the parenthesized pipeline, not to a single label-filter expression
    inside the pipeline.
  - Top blocked tools (instant query):
    `topk(10, sum by (tool) (rate(({app="walter-os", kind="audit-chain"} | json | decision="block")[7d])))`
  - Top block reasons: same shape on `decision_reason` label.
  - Audit-event count per host (24h): `count by (host) (count_over_time({app="walter-os", kind="audit-chain"}[24h]))` — note this is total audit-chain rows per host, NOT distinct sessions. Use the next panel for distinct sessions.
  - Distinct sessions per host (24h):
    `count by (host) (count by (host, session_id) (count_over_time(({app="walter-os", kind="audit-chain"} | json | __error__="")[24h])))`
    — wraps the log-stream-pipeline in parens before `[24h]`, same as the
    Block-rate query above. Outer `count by (host)` collapses the inner
    `(host, session_id)` grouping into a count of unique `session_id`s
    seen on each host. The previous draft had `[24h]` with a leading
    space and no surrounding parens — LogQL would error on that.
  - Active sessions (last activity ≤ 30 min ago):
    `count by (session_id) (last_over_time({app="walter-os", kind="audit-chain"} | json | unwrap ts [30m]))`
- [ ] Dashboard auto-provisioned by Grafana's `provisioning/dashboards/` directory (already wired in the existing stack).

### AC-3 — `walter-os audit verify-chain --from-loki <range>`
- [ ] New flag on the existing `verify-chain` command.
- [ ] Queries Loki for the given range (defaults to last 24h), reconstructs the chain in memory.
- [ ] Same prev_hash + sig verification as the local path.
- [ ] Fails with helpful error if Loki is unreachable OR returns truncated data (e.g. retention dropped some rows).
- [ ] bats coverage in `tests/walter/audit-chain-verify-from-loki.bats` (uses a Loki mock or `--mock-loki <fixture>` flag).

### AC-4 — Operator opt-out
- [ ] When `WALTER_AUDIT_LOKI_DISABLE=1` is set in `personal.env`, Promtail config does NOT tail the audit chain (tail rule is conditional on the env var).
- [ ] Existing rows already shipped stay in Loki; opt-out only blocks future shipping.
- [ ] `walter-os audit status` shows whether Loki shipping is active.

### AC-5 — Retention configuration
- [ ] Loki config (`setup/walter-host/services/observability/loki/loki.yml` — actual filename in the repo; earlier draft of this spec used the non-existent `loki-config.yml`) gains a labeled retention stanza for `app=walter-os, kind=audit-chain` using `WALTER_AUDIT_LOKI_RETENTION_DAYS` env var (default 30).
- [ ] Documented in `docs/operational/audit-telemetry.md`.

### AC-6 — Documentation + CHANGELOG
- [ ] `docs/operational/audit-telemetry.md` (new):
  - Setup steps for the bind-mount
  - Default dashboard tour
  - LogQL query examples for common questions
  - Opt-out via `WALTER_AUDIT_LOKI_DISABLE=1`
  - Cross-host workflow (configure each Walter-OS host's Promtail to ship to the SAME Loki)
  - Operator-data-ownership statement: "Loki runs on YOUR walter-host. Xipher Labs has no access."
- [ ] CHANGELOG entry under `[Unreleased] → Added (observability)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Compromised host ships fake audit rows to Loki | Loki stores verbatim including `sig`; verifier rejects on sig mismatch. Attacker can spam rows but can't forge valid sigs (session key local to that host). |
| Loki tampered to drop rows post-shipping | Local JSONL is still source of truth. AC-3 specifies `verify-chain --from-loki` reconstructs from Loki ONLY; the broader cross-check against the local JSONL is a follow-up enhancement (operator runs `verify-chain` twice — once `--from-loki <range>` and once against the local file — and compares the resulting chain heads). |
| Operator opts out then opts back in; chain has a gap in Loki | Local JSONL is intact; operator can backfill via `promtail --once /path/to/chain-YYYY-MM-DD.jsonl` (documented). |
| Loki disk fills up; new rows dropped | Operator-side disk monitoring (existing). 30d retention is the default ceiling. |

## Out of scope

- Telemetry to external services (Xipher Labs cloud, etc.). Operator-owned only.
- Real-time SIEM integration (Elastic, Splunk). Operator can pipe Loki → external via Promtail if desired; not in v0.6.0.
- Cross-operator audit-chain unification.
- Anomaly detection / ML-based alerting on the chain. Future work.

## Recommended PR ordering

1. AC-1 — Promtail config + compose example
2. AC-2 — Grafana dashboard JSON
3. AC-3 — `verify-chain --from-loki` subcommand
4. AC-4 — opt-out env var
5. AC-5 — Loki retention configuration
6. AC-6 — docs + CHANGELOG

Each ≤200 LOC. 3-round review.

## Open questions for the operator

1. **Loki retention default**: 30d (proposal), 90d, or operator-configurable from day 1? Proposal: 30d default, `WALTER_AUDIT_LOKI_RETENTION_DAYS` overrides.
2. **Bind-mount path**: `/var/log/walter-audit/` inside Promtail container (proposal — FHS convention) or `/walter-audit/` (shorter)? Proposal: `/var/log/walter-audit/`.
3. **Pre-built dashboard panel count**: 6 (proposal — covers common questions without overwhelming a fresh operator) or more? Proposal: 6; operator adds panels for their specific workflows.

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` Layer B B-3
- Sibling: `docs/specs/audit-chain-merkle-and-receipts.md` (B-1 + B-2 — source of truth)
- `setup/walter-host/services/observability/` (existing Grafana + Loki + Promtail stack)
- LogQL docs: <https://grafana.com/docs/loki/latest/logql/>
