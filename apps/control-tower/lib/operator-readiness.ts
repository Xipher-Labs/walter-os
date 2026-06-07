import type { StatusKind } from "@/app/components/ui/status";

export interface ReadinessDoc {
  label: string;
  path: string;
}

export interface ReadinessMode {
  id: "solo" | "second-device" | "teammate";
  label: string;
  status: StatusKind;
  statusLabel: string;
  summary: string;
  primaryCommand: string;
  docs: ReadinessDoc[];
}

export interface ReadinessCheck {
  id: "service-health" | "post-merge" | "model-tools";
  label: string;
  status: StatusKind;
  statusLabel: string;
  summary: string;
  command: string;
  docs: ReadinessDoc[];
}

export const OPERATOR_READINESS_MODES = [
  {
    id: "solo",
    label: "Solo operator",
    status: "ok",
    statusLabel: "baseline",
    summary: "One operator, one Walter domain, local config stays private.",
    primaryCommand: "walter-os doctor",
    docs: [
      {
        label: "Operator setup",
        path: "docs/operational/operator-setup-runbook.md",
      },
      {
        label: "Personal overlay",
        path: "docs/operational/universal-vs-personal-config.md",
      },
    ],
  },
  {
    id: "second-device",
    label: "Second device",
    status: "warn",
    statusLabel: "plan first",
    summary: "Same operator, new machine, synced memory/wiki/overlay.",
    primaryCommand: "walter-os onboard device --dry-run",
    docs: [
      {
        label: "Onboarding planner",
        path: "docs/operational/onboarding-planner.md",
      },
      {
        label: "Multi-device sync",
        path: "docs/operational/multi-device-sync.md",
      },
    ],
  },
  {
    id: "teammate",
    label: "Teammate",
    status: "warn",
    statusLabel: "gate access",
    summary: "Separate identity, least privilege, and explicit role boundary.",
    primaryCommand: "walter-os onboard teammate --dry-run",
    docs: [
      {
        label: "Onboarding planner",
        path: "docs/operational/onboarding-planner.md",
      },
      {
        label: "Authentik SSO",
        path: "docs/operational/authentik-sso.md",
      },
      {
        label: "Knowledge profile",
        path: "docs/operational/knowledge-profile.md",
      },
    ],
  },
] satisfies ReadinessMode[];

export const OPERATIONAL_READINESS_CHECKS = [
  {
    id: "service-health",
    label: "Service health",
    status: "info",
    statusLabel: "diagnose",
    summary: "Use doctor/status before opening high-risk profiles.",
    command: "walter-os doctor",
    docs: [
      {
        label: "Troubleshooting",
        path: "docs/operational/troubleshooting.md",
      },
      {
        label: "Stack overview",
        path: "docs/operational/stack-overview.md",
      },
    ],
  },
  {
    id: "post-merge",
    label: "Post-merge",
    status: "info",
    statusLabel: "read-only",
    summary: "Classify merged commit health before fix or rollback work.",
    command: "walter-os post-merge-check --commit <sha>",
    docs: [
      {
        label: "Post-merge loop",
        path: "docs/specs/post-merge-feedback-loop.md",
      },
    ],
  },
  {
    id: "model-tools",
    label: "Model/tool readiness",
    status: "info",
    statusLabel: "inspect",
    summary: "Check routing and startup degradation before assigning agents.",
    command: "walter-os status --models",
    docs: [
      {
        label: "Model routing",
        path: "docs/operational/multi-model-routing.md",
      },
      {
        label: "Troubleshooting",
        path: "docs/operational/troubleshooting.md",
      },
    ],
  },
] satisfies ReadinessCheck[];
