#!/usr/bin/env bash
# Print read-only onboarding plans for additional devices and teammates.

set -euo pipefail

usage() {
  printf '%s\n' \
    "Usage: walter-os onboard {device|teammate} --dry-run" \
    "" \
    "Print a read-only onboarding checklist. This command never creates" \
    "users, tokens, secrets, access rules, or optional modules."
}

print_device_plan() {
  printf '%s\n' \
    "Second-device onboarding -- dry run" \
    "" \
    "Use this when the same operator is adding another laptop, desktop, or workstation to an existing Walter domain." \
    "" \
    "Checklist:" \
    "1. Confirm the device OS and shell match the operator overlay preferences." \
    "2. Initialize the secrets identity; do not print tokens or secret material." \
    "3. Run profile bootstrap for the intended client set: claude, codex, or all." \
    "4. Wire agent memory to the synchronized folder and verify ownership." \
    "5. Join Syncthing to the Walter-VM hub and wait for the expected folders." \
    "6. Join Headscale or Tailscale and confirm the device can reach Walter-VM services." \
    "7. Run doctor/status checks before enabling high-risk MCP profiles." \
    "" \
    "Suggested commands to review, not run automatically:" \
    "- walter-os secrets-identity-init" \
    "- walter-os profile-bootstrap init all" \
    "- walter-os agent-memory setup" \
    "- walter-os syncthing-bootstrap" \
    "- walter-os doctor" \
    "- walter-os status --models" \
    "" \
    "Docs:" \
    "docs/operational/onboarding-planner.md" \
    "docs/operational/operator-setup-runbook.md" \
    "docs/operational/multi-device-sync.md"
}

print_teammate_plan() {
  printf '%s\n' \
    "Teammate onboarding -- dry run" \
    "" \
    "Use this when a second person will share the same Walter-VM but needs separate identity, access, and role boundaries." \
    "" \
    "Checklist:" \
    "1. Decide the teammate role boundaries before granting access." \
    "2. Add Cloudflare Access or Authentik identity gates for every exposed subdomain." \
    "3. Grant Forgejo access with least privilege and avoid admin by default." \
    "4. Grant Plane workspace/project access only to the projects they need." \
    "5. Configure ntfy notifications for operational events without exposing secrets." \
    "6. Review optional modules before installation; keep the base stack small." \
    "7. Run doctor/status checks and capture any missing prerequisites." \
    "" \
    "Optional modules:" \
    "Module | When it helps | Default stance" \
    "Authentik | Central SSO and app-level identity | Optional" \
    "Forgejo Actions Runner | CI for self-hosted repositories | Optional" \
    "Renovate | Automated dependency update PRs | Optional" \
    "Langfuse | LLM tracing and prompt observability | Optional" \
    "Listmonk | Email newsletter and lightweight campaigns | Optional" \
    "ntfy | Push notifications for operators and teammates | Optional" \
    "knowledge/bookmarking | Outline, Linkwarden, or Obsidian-style knowledge capture | Optional" \
    "" \
    "Docs:" \
    "docs/operational/onboarding-planner.md" \
    "docs/operational/onboarding-checklist.md" \
    "docs/operational/authentik-sso.md" \
    "docs/operational/stack-overview.md" \
    "docs/operational/knowledge-profile.md" \
    "docs/operational/renovate-self-hosted.md" \
    "docs/operational/langfuse.md"
}

target="${1:-}"
dry_run="${2:-}"

if [[ "$target" == "-h" || "$target" == "--help" || "$target" == "help" ]]; then
  usage
  exit 0
fi

if [[ "$dry_run" != "--dry-run" || -n "${3:-}" ]]; then
  usage >&2
  exit 2
fi

case "$target" in
  device)
    print_device_plan
    ;;
  teammate)
    print_teammate_plan
    ;;
  *)
    printf 'walter-os onboard: unknown target: %s\n\n' "${target:-<missing>}" >&2
    usage >&2
    exit 2
    ;;
esac
