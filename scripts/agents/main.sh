#!/usr/bin/env bash
# scripts/agents/main.sh — operator-facing CLI for the Walter Council.
# Wired into bin/walter-os as the `agents` subcommand.
#
# Subcommands:
#   list                       List known agents + their lanes
#   run-once <agent> --issue <id>  Run one agent on one Plane issue
#   pause                      Pause all agent workers (creates pause flag)
#   resume                     Resume from pause
#   status                     Report pause-state + recent audit summary
#
# Spec: docs/specs/multi-agent-autonomy.md §11

set -uo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?must be set}"
WALTER_CONFIG="${WALTER_CONFIG:-$HOME/.config/walter-os}"
PAUSE_FLAG="$WALTER_CONFIG/agents.paused"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

AGENTS_KNOWN=(triage researcher coder reviewer janitor liaison)

cmd="${1:-help}"
shift || true

case "$cmd" in
  list)
    echo "Walter Council — known agents"
    echo
    printf "  %-12s %-12s %s\n" "AGENT" "LANE" "PURPOSE"
    printf "  %-12s %-12s %s\n" "─────" "────" "───────"
    printf "  %-12s %-12s %s\n" "triage"     "triage"   "Classify incoming events; create downstream issues"
    printf "  %-12s %-12s %s\n" "researcher" "research" "Wiki ingest, web search, fact-check"
    printf "  %-12s %-12s %s\n" "coder"      "code"     "Small diffs, RED-GREEN-REFACTOR, opens PRs"
    printf "  %-12s %-12s %s\n" "reviewer"   "review"   "Read-only diff review; security/perf check"
    printf "  %-12s %-12s %s\n" "janitor"    "janitor"  "Lint, audit, dep bumps, DR drill, stale-PR sweep"
    printf "  %-12s %-12s %s\n" "liaison"    "digest"   "Daily digest synthesis to Telegram + Plane"
    echo
    echo "See: docs/specs/multi-agent-autonomy.md §4"
    ;;

  run-once)
    if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
      cat <<RUN_USAGE
Usage: walter-os agents run-once <agent> --issue <plane-issue-id> [options]

Args:
  <agent>           One of: ${AGENTS_KNOWN[*]}
  --issue <id>      Plane issue ID (UUID)
  --dry-run         Print plan without claiming or invoking the LLM
  --max-runtime N   Max seconds per task (default: 1800)

Example:
  walter-os agents run-once researcher --issue 5fa1b2c3-... --dry-run

Spec: docs/specs/multi-agent-autonomy.md §4-5
RUN_USAGE
      exit 0
    fi
    if [[ -f "$PAUSE_FLAG" ]]; then
      echo "agents: paused. Resume with: walter-os agents resume" >&2
      exit 1
    fi
    [[ $# -lt 1 ]] && { echo "Usage: walter-os agents run-once <agent> --issue <id> [--dry-run]" >&2; exit 2; }
    AGENT="$1"
    shift
    case " ${AGENTS_KNOWN[*]} " in
      *" $AGENT "*) ;;
      *) echo "agents: unknown agent '$AGENT'. Known: ${AGENTS_KNOWN[*]}" >&2; exit 2 ;;
    esac
    exec "$SCRIPT_DIR/run.sh" "$AGENT" "$@"
    ;;

  pause)
    mkdir -p "$WALTER_CONFIG"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$PAUSE_FLAG"
    echo "✓ Paused at $(cat "$PAUSE_FLAG"). New run-once invocations will refuse."
    echo "  In-flight workers continue until current task completes."
    ;;

  resume)
    if [[ ! -f "$PAUSE_FLAG" ]]; then
      echo "agents: not currently paused."
      exit 0
    fi
    paused_at=$(cat "$PAUSE_FLAG")
    rm -f "$PAUSE_FLAG"
    echo "✓ Resumed. (Was paused since $paused_at.)"
    ;;

  unlock)
    reason=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --reason)
          if [[ $# -lt 2 ]]; then
            echo "Error: --reason requires a value" >&2
            echo "Usage: walter-os agents unlock --reason '<why you are unlocking>'" >&2
            exit 2
          fi
          reason="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    if [[ -z "$reason" ]]; then
      echo "ERROR: --reason required" >&2
      echo "Usage: walter-os agents unlock --reason '<why you are unlocking>'" >&2
      exit 2
    fi
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/alerts.sh"
    alert_unlock "$reason"
    ;;

  trust)
    TRUST_TIERS="${WALTER_TRUST_TIERS:-${WALTER_CONFIG}/trust-tiers.yml}"
    trust_subcmd="${1:-show}"
    shift || true

    # Subcommands: list, show <agent>, set <agent> <tier>
    case "$trust_subcmd" in
      list)
        json_mode=0
        if [[ "${1:-}" == "--json" ]]; then json_mode=1; shift; fi

        if ! command -v yq >/dev/null 2>&1; then
          echo "agents trust list: yq required but not installed" >&2
          exit 3
        fi
        if [[ ! -f "$TRUST_TIERS" ]]; then
          echo "agents trust list: trust-tiers.yml not found at $TRUST_TIERS" >&2
          exit 3
        fi

        if [[ "$json_mode" -eq 1 ]]; then
          # Output JSON for Phase U (Control Tower) consumption
          yq -o=json '.agents' "$TRUST_TIERS" 2>/dev/null
        else
          printf "%-14s %-8s %s\n" "AGENT" "TIER" "OVERRIDES"
          printf "%-14s %-8s %s\n" "─────" "────" "─────────"
          yq '.agents | to_entries[] | [.key, .value.tier, (.value.overrides // {} | to_entries | map(.key + "=" + .value) | join(","))] | join("|")' \
            "$TRUST_TIERS" 2>/dev/null | while IFS='|' read -r agent tier overrides; do
            printf "%-14s %-8s %s\n" "$agent" "$tier" "${overrides:-(none)}"
          done
        fi
        ;;

      set)
        agent_name="${1:-}"
        new_tier="${2:-}"
        if [[ -z "$agent_name" || -z "$new_tier" ]]; then
          echo "Usage: walter-os agents trust set <agent> <tier>" >&2
          echo "  tier must be one of: low | medium | high" >&2
          exit 2
        fi
        case "$new_tier" in
          low|medium|high) ;;
          *)
            echo "agents trust set: invalid tier '$new_tier'" >&2
            echo "  Valid tiers: low | medium | high" >&2
            exit 2
            ;;
        esac
        if ! command -v yq >/dev/null 2>&1; then
          echo "agents trust set: yq required but not installed" >&2
          exit 3
        fi
        if [[ ! -f "$TRUST_TIERS" ]]; then
          echo "agents trust set: trust-tiers.yml not found at $TRUST_TIERS" >&2
          exit 3
        fi
        yq -i ".agents.${agent_name}.tier = \"${new_tier}\"" "$TRUST_TIERS" 2>/dev/null
        echo "trust: set ${agent_name} → ${new_tier} (in $TRUST_TIERS)"
        ;;

      *)
        # Treat as `show <agent>`
        agent_name="$trust_subcmd"
        # Default "show" means no subcommand was given — print usage.
        if [[ "$agent_name" == "show" || -z "$agent_name" ]]; then
          echo "Usage: walter-os agents trust <agent|list|set>" >&2
          echo "  walter-os agents trust <agent-name>   Show trust tier + effective permissions" >&2
          echo "  walter-os agents trust list [--json]  List all agents" >&2
          echo "  walter-os agents trust set <agent> <tier>  Update tier" >&2
          exit 2
        fi

        if ! command -v yq >/dev/null 2>&1; then
          echo "agents trust: yq required but not installed" >&2
          exit 3
        fi
        if [[ ! -f "$TRUST_TIERS" ]]; then
          echo "agents trust: trust-tiers.yml not found at $TRUST_TIERS" >&2
          exit 3
        fi

        tier=$(yq ".agents.${agent_name}.tier // \"\"" "$TRUST_TIERS" 2>/dev/null)
        if [[ -z "$tier" || "$tier" == "null" ]]; then
          echo "agents trust: agent '${agent_name}' not found in $TRUST_TIERS" >&2
          exit 2
        fi

        echo "Agent:  ${agent_name}"
        echo "Tier:   ${tier}"
        echo

        # Print effective category decisions
        declare -A TIER_ALLOWS_MEDIUM=(
          [git-push-feature-branch]=1 [gh-pr-create]=1 [gh-pr-comment]=1
          [run-tests-linters]=1 [write-source-files-feature-branch]=1
          [write-wiki-pages]=1 [create-plane-issue]=1 [read-any-file]=1
        )
        declare -A TIER_ALLOWS_HIGH=(
          [git-push-feature-branch]=1 [gh-pr-create]=1 [gh-pr-comment]=1
          [gh-pr-review-approve]=1 [run-tests-linters]=1
          [write-source-files-feature-branch]=1 [write-wiki-pages]=1
          [create-plane-issue]=1 [read-any-file]=1
        )
        declare -A TIER_ALLOWS_LOW=(
          [read-any-file]=1 [run-tests-linters]=1
          [gh-pr-comment]=1 [create-plane-issue]=1
        )

        # Read overrides
        override_pairs=$(yq ".agents.${agent_name}.overrides // {} | to_entries[] | .key + \"=\" + .value" \
          "$TRUST_TIERS" 2>/dev/null || echo "")

        printf "%-38s %s\n" "CATEGORY" "DECISION"
        printf "%-38s %s\n" "────────" "────────"

        for cat in git-push-feature-branch gh-pr-create gh-pr-comment gh-pr-review-approve \
                   run-tests-linters write-source-files-feature-branch write-wiki-pages \
                   create-plane-issue read-any-file; do
          # Check override first
          override_val=""
          while IFS='=' read -r k v; do
            [[ "$k" == "$cat" ]] && override_val="$v" && break
          done <<< "$override_pairs"

          if [[ -n "$override_val" ]]; then
            decision_str="${override_val} (tier-override)"
          else
            # Apply tier defaults
            case "$tier" in
              high)   [[ -n "${TIER_ALLOWS_HIGH[$cat]:-}" ]] && decision_str="allow" || decision_str="block" ;;
              medium) [[ -n "${TIER_ALLOWS_MEDIUM[$cat]:-}" ]] && decision_str="allow" || decision_str="block" ;;
              low)    [[ -n "${TIER_ALLOWS_LOW[$cat]:-}" ]] && decision_str="allow" || decision_str="block" ;;
              *)      decision_str="block (unknown tier)" ;;
            esac
          fi
          printf "%-38s %s\n" "$cat" "$decision_str"
        done
        ;;
    esac
    ;;

  status)
    if [[ -f "$PAUSE_FLAG" ]]; then
      echo "Walter Council: PAUSED since $(cat "$PAUSE_FLAG")"
    else
      echo "Walter Council: ACTIVE"
    fi
    echo

    AUDIT_DIR="${WALTER_AGENT_AUDIT_DIR:-$HOME/sync/agent-memory/audit}"
    today=$(date '+%Y-%m-%d')
    if [[ -f "$AUDIT_DIR/$today.log" ]]; then
      echo "Today's events ($today):"
      jq -rc 'select(.event != "tool") | "  \(.ts) \(.agent) \(.event) issue=\(.issue) \(.msg | .[0:80])"' \
        "$AUDIT_DIR/$today.log" 2>/dev/null | tail -10
      echo
      echo "Counts (today):"
      jq -rc '.event' "$AUDIT_DIR/$today.log" 2>/dev/null | sort | uniq -c | sed 's/^/  /'
    else
      echo "No audit log for today (yet). Run an agent to populate."
    fi

    # Zombie section: count zombie_detected events in watchdog log from last 7 days.
    WATCHDOG_LOG="${WALTER_WATCHDOG_LOG:-/var/log/walter-council/watchdog.log}"
    echo
    if [[ -f "$WATCHDOG_LOG" ]]; then
      # Cutoff: 7 days ago in epoch seconds
      if date -v-7d >/dev/null 2>&1; then
        # macOS
        cutoff_epoch=$(date -v-7d +%s 2>/dev/null || echo 0)
      else
        # Linux
        cutoff_epoch=$(date -d "7 days ago" +%s 2>/dev/null || echo 0)
      fi
      # R10: pass WATCHDOG_LOG via env var, not source interpolation.
      # A path containing ' would break the open('$WATCHDOG_LOG') literal.
      zombie_count=$(WALTER_WATCHDOG_LOG="$WATCHDOG_LOG" python3 -c "
import os, sys, json
log_path = os.environ['WALTER_WATCHDOG_LOG']
cutoff = $cutoff_epoch
count = 0
try:
    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('event') != 'zombie_detected':
                    continue
                ts_str = entry.get('ts', '')
                if not ts_str:
                    continue
                from datetime import datetime, timezone
                dt = datetime.strptime(ts_str, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                if int(dt.timestamp()) >= cutoff:
                    count += 1
            except Exception:
                pass
except Exception:
    pass
print(count)
" 2>/dev/null || echo 0)
      echo "Zombies detected (last 7d): ${zombie_count}"
    else
      echo "Zombies detected (last 7d): 0  (no watchdog log yet)"
    fi
    ;;

  summary)
    # walter-os agents summary --since <ISO-date>
    # Reads consensus-votes.log since the given timestamp and prints:
    #   - N tasks auto-approved by consensus
    #   - N tasks that failed consensus (awaiting human)
    # Spec: docs/specs/walter-council-v2.md — T-36b
    since_ts=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --since) since_ts="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ -z "$since_ts" ]]; then
      echo "ERROR: --since <ISO-timestamp> required" >&2
      echo "Usage: walter-os agents summary --since <ISO-date>" >&2
      exit 2
    fi

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/mode.sh"
    _summary_json=$(summary_since "$since_ts" 2>/dev/null || \
      echo '{"consensus_approved":0,"awaiting_human":0,"failed_consensus":0,"approved_issues":[],"awaiting_issues":[],"failed_issues":[]}')

    _approved=$(echo "$_summary_json" | jq -r '.consensus_approved // 0' 2>/dev/null || echo 0)
    _failed=$(echo "$_summary_json" | jq -r '.failed_consensus // 0' 2>/dev/null || echo 0)
    _awaiting=$(echo "$_summary_json" | jq -r '.awaiting_human // 0' 2>/dev/null || echo 0)
    _approved_list=$(echo "$_summary_json" | jq -r '.approved_issues[]?' 2>/dev/null || true)
    _failed_list=$(echo "$_summary_json" | jq -r '.failed_issues[]?' 2>/dev/null || true)
    _awaiting_list=$(echo "$_summary_json" | jq -r '.awaiting_issues[]?' 2>/dev/null || true)

    echo "=== Walter Council Summary (since: ${since_ts}) ==="
    echo
    echo "Consensus-approved: ${_approved}"
    if [[ -n "$_approved_list" ]]; then
      echo "$_approved_list" | while IFS= read -r issue; do
        echo "  - ${issue}"
      done
    fi
    echo
    echo "Failed consensus (awaiting human): ${_failed}"
    if [[ -n "$_failed_list" ]]; then
      echo "$_failed_list" | while IFS= read -r issue; do
        echo "  - ${issue}"
      done
    fi
    echo
    echo "Awaiting human (escalated): ${_awaiting}"
    if [[ -n "$_awaiting_list" ]]; then
      echo "$_awaiting_list" | while IFS= read -r issue; do
        echo "  - ${issue}"
      done
    fi
    ;;

  -h|--help|help|"")
    cat <<USAGE
Usage: walter-os agents <subcommand>

Subcommands:
  list                          List known agents + their lanes
  run-once <agent> --issue <id> Run one agent on one Plane issue
                                Args: --dry-run --max-runtime <sec>
  pause                         Pause new agent invocations
  resume                        Lift pause
  status                        Report pause + today's audit summary
  unlock --reason '<reason>'    Remove panic gate.lock (AC-5 Impr 8)
  trust <agent>                 Show trust tier + effective permissions
  trust list [--json]           List all agent tiers
  trust set <agent> <tier>      Update agent tier (low|medium|high)
  summary --since <ISO-date>    Show consensus vote outcomes since timestamp

Spec: docs/specs/multi-agent-autonomy.md
USAGE
    ;;

  *)
    echo "agents: unknown subcommand '$cmd'" >&2
    exit 2
    ;;
esac
