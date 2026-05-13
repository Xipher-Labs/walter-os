# Plane State Machine — Walter Council

Documents all Plane issue states used by the Walter Council agent runner.

## Standard states (present by default in Plane)

| State | Description |
|---|---|
| `backlog` | Issue not yet ready for work |
| `ready` | Ready to be claimed by an agent |
| `claimed` | Claimed by an agent (assignee set) |
| `in-progress` | Agent is actively working |
| `review` | Work done, awaiting review |
| `done` | Completed |

## Walter Council extended states (operator must create in Plane UI)

### `awaiting-consensus` (T-prereq-1)

**Purpose**: Issue is blocked pending a council vote in consensus mode.

**Flow**:
```
needs-operator → awaiting-consensus → (vote pass) ready
                                    → (vote fail) awaiting-human
```

**When set**: `approval-gate.sh` returns exit 8 (consensus-eligible category,
consensus mode ON). The runner puts the issue in this state while `vote_council`
runs.

**Watchdog behavior**: Issues in `awaiting-consensus` are NOT declared zombies.
The watchdog skips them (vote may take up to 45 seconds).

### `awaiting-human` (T-prereq-2)

**Purpose**: Issue failed council consensus or requires explicit operator action.

**Flow**:
```
awaiting-consensus → (vote fail) awaiting-human
needs-operator     → awaiting-human (direct escalation for non-consensus-eligible ops)
```

**When set**: `plane_issue_set_state_awaiting_human` — either after a failed
consensus vote, or when an operation is not consensus-eligible and the operator
must manually approve.

**Resolution**: Operator reviews the vote discussion in Plane comments, then
manually moves the issue back to `ready` (or `backlog` if rejected).

**Watchdog behavior**: Issues in `awaiting-human` are NOT declared zombies.
They require human action by design.

## Operator setup instructions

Before enabling consensus mode (`walter-os mode consensus on`):

1. Open Plane → project settings → States.
2. Create state: `awaiting-consensus` (type: backlog or custom).
3. Create state: `awaiting-human` (type: backlog or custom).
4. Verify: `plane_issues_list_by_state awaiting-consensus` returns without error.

These are referenced in `docs/operational/council-v2-prereqs.md` as T-prereq-1
and T-prereq-2.

## State transition diagram

```
backlog
  │
  ▼
ready ◄─────────────────────────── (consensus vote passes)
  │                                                │
  ▼                                                │
claimed                               awaiting-consensus
  │                                                │
  ▼                                  (consensus vote fails)
in-progress                                        │
  │                                                ▼
  ├──(result: done/review)──────────► done/review awaiting-human
  │                                   (operator resolves)
  └──(approval-gate exit 8)──────────► awaiting-consensus
  └──(approval-gate exit 7)──────────► needs-operator
```
