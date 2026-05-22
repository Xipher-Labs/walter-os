#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hooks/external-pr-merge-gate.sh
#
# Advisory pre-merge gate for external PRs. Refuses to confirm the merge
# of an external contributor's PR until the Xipher Labs legal entity is
# constituted + the CLA is active (per ADR-0022 + ADR-0019).
#
# This hook is OPT-IN: it is not registered in .claude/settings.json by
# default. Operators who want enforcement add it to their personal
# overlay's hook config. The intent is to make the gate visible without
# imposing it on every Walter-OS adopter (some adopters may not care about
# the IdeaOS commercial path).
#
# Usage (manual, for testing):
#   ./hooks/external-pr-merge-gate.sh <pr-number>
#
# Usage (Claude Code PreToolUse hook for `gh pr merge`):
#   Add the path to .claude/settings.json or the overlay equivalent.
#
# Exit codes:
#   0 — gate clear (either the entity is formed OR the PR author is the
#       operator/an allowlisted bot)
#   1 — gate engaged (entity not formed + PR is external) — refuse merge
#   2 — usage error
#
# Environment:
#   WALTER_OPERATOR_GH_LOGIN — the operator's GitHub login. Read from
#     overlay's personal.env. If unset, the hook refuses with exit 2.
#   WALTER_ENTITY_FORMED_MARKER — path to a marker file the operator
#     creates after entity formation. Defaults to
#     ~/.config/walter-os/overlay/entity-formed
#
# Allowlisted bot logins (do not need to sign CLA, do not block the gate):
#   - dependabot[bot]
#   - renovate[bot]
#   - copilot-pull-request-reviewer[bot]
#   - github-actions[bot]

set -euo pipefail

ENTITY_MARKER="${WALTER_ENTITY_FORMED_MARKER:-$HOME/.config/walter-os/overlay/entity-formed}"

# If the marker exists, the gate is permanently open.
if [[ -f "$ENTITY_MARKER" ]]; then
  exit 0
fi

# Marker does not exist — check whether the PR is external.

if [[ $# -lt 1 ]]; then
  cat <<'USAGE' >&2
external-pr-merge-gate.sh: missing argument

Usage:
  ./hooks/external-pr-merge-gate.sh <pr-number-or-url>

The hook checks the PR's author and refuses the merge if:
  - The Xipher Labs entity-formed marker is absent, AND
  - The PR author is not the operator or an allowlisted bot.
USAGE
  exit 2
fi

PR_REF="$1"

# Resolve the PR author via gh CLI. gh handles both "123" and full URLs.
if ! command -v gh >/dev/null 2>&1; then
  echo "external-pr-merge-gate.sh: gh CLI not found. Install gh first." >&2
  exit 2
fi

PR_AUTHOR=$(gh pr view "$PR_REF" --json author --jq '.author.login' 2>/dev/null || echo "")
if [[ -z "$PR_AUTHOR" ]]; then
  echo "external-pr-merge-gate.sh: failed to resolve PR author for '$PR_REF'." >&2
  exit 2
fi

OPERATOR_LOGIN="${WALTER_OPERATOR_GH_LOGIN:-}"
if [[ -z "$OPERATOR_LOGIN" ]]; then
  echo "external-pr-merge-gate.sh: WALTER_OPERATOR_GH_LOGIN unset." >&2
  echo "Set it in your overlay's personal.env to enable the gate." >&2
  exit 2
fi

# Allowlist of bot authors.
case "$PR_AUTHOR" in
  "$OPERATOR_LOGIN" | \
  "dependabot[bot]" | "dependabot" | \
  "renovate[bot]" | "renovate" | \
  "copilot-pull-request-reviewer[bot]" | "Copilot" | \
  "github-actions[bot]")
    # Not external. Gate clear.
    exit 0
    ;;
esac

# External author + no entity marker => refuse.
cat <<EOF >&2
external-pr-merge-gate.sh: REFUSING MERGE OF EXTERNAL PR

PR:           $PR_REF
PR author:    $PR_AUTHOR
Operator:     $OPERATOR_LOGIN

The Xipher Labs legal entity has not been marked as formed:
  $ENTITY_MARKER (missing)

Per ADR-0022, external PRs cannot be merged until:
  1. The entity is constituted (creates the marker file).
  2. The CLA gate is active (WALTER_CLA_ACTIVE=true repo variable).
  3. The contributor has signed the CLA.

Runbook: docs/operational/xipher-labs-entity-formation.md
ADRs:    docs/decisions/0022-xipher-labs-legal-entity.md
         docs/decisions/0019-contributor-license-agreement.md
EOF
exit 1
