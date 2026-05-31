/**
 * Status vocabulary — the single source of truth for the Control Tower's
 * status language (D-4). Agent state, service health, and alert tiers all map
 * onto this one set of tokens so a colour never means two things and so the
 * StatusDot / StatusBadge primitives can render any of them.
 *
 * Each kind carries token class names (defined in app/globals.css) and a human
 * label so the UI never relies on colour alone (WCAG 1.4.1, AC-5).
 *
 * Refs: docs/specs/control-tower-redesign.md (AC-2, AC-4, D-4)
 */

export type StatusKind =
  | "idle"
  | "working"
  | "blocked"
  | "ok"
  | "warn"
  | "critical"
  | "info"
  | "na";

export interface StatusToken {
  /** Default human-readable label. */
  label: string;
  /** Foreground (text + dot) utility class. */
  fg: string;
  /** Subtle background wash for badge backgrounds. */
  bg: string;
  /** Whether the dot should pulse to signal live/urgent activity. */
  pulse: boolean;
}

export const STATUS_TOKENS: Record<StatusKind, StatusToken> = {
  idle: {
    label: "idle",
    fg: "text-status-idle-fg",
    bg: "bg-status-idle-bg",
    pulse: false,
  },
  working: {
    label: "working",
    fg: "text-status-working-fg",
    bg: "bg-status-working-bg",
    pulse: true,
  },
  blocked: {
    label: "blocked",
    fg: "text-status-blocked-fg",
    bg: "bg-status-blocked-bg",
    pulse: true,
  },
  ok: {
    label: "ok",
    fg: "text-status-ok-fg",
    bg: "bg-status-ok-bg",
    pulse: false,
  },
  warn: {
    label: "warn",
    fg: "text-status-warn-fg",
    bg: "bg-status-warn-bg",
    pulse: false,
  },
  critical: {
    label: "critical",
    fg: "text-status-critical-fg",
    bg: "bg-status-critical-bg",
    pulse: true,
  },
  info: {
    label: "info",
    fg: "text-status-info-fg",
    bg: "bg-status-info-bg",
    pulse: false,
  },
  na: {
    label: "n/a",
    fg: "text-subtle",
    bg: "bg-status-info-bg",
    pulse: false,
  },
};

/** Alert/timeline tiers from lib/events-reader.ts map 1:1 except "panic". */
export type AlertTierLike = "info" | "warn" | "critical" | "panic";

export function tierToStatus(tier: AlertTierLike): StatusKind {
  // "panic" is the most severe alert tier; it shares the critical token but is
  // labelled distinctly by callers. Treat it as critical for colour.
  return tier === "panic" ? "critical" : tier;
}

/** Agent state from lib/metrics-reader.ts is already a StatusKind subset. */
export type AgentStateLike = "idle" | "working" | "blocked";

/**
 * Service health → status. `null` means no standby configured (N/A), which is
 * neither healthy nor unhealthy and must not render green (HA route contract).
 */
export function healthToStatus(healthy: boolean | null): StatusKind {
  if (healthy === null) return "na";
  return healthy ? "ok" : "critical";
}
