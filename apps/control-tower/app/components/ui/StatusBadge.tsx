import { STATUS_TOKENS, type StatusKind } from "./status";

/**
 * StatusBadge — a pill that pairs the status dot with its label on a subtle
 * token-tinted background (D-4). Used for agent state, consensus mode, alert
 * tiers, and history flags. The label text is always present, so the badge is
 * legible without colour (WCAG 1.4.1).
 *
 * Gray-on-colour is avoided: the foreground is a shade of the same hue as the
 * background wash, per the impeccable colour rules.
 */
export default function StatusBadge({
  status,
  label,
  pulse,
  className = "",
}: {
  status: StatusKind;
  /** Override the default label (e.g. "panic", "ON"). */
  label?: string;
  pulse?: boolean;
  className?: string;
}) {
  const token = STATUS_TOKENS[status];
  const text = label ?? token.label;
  const shouldPulse = pulse ?? token.pulse;

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium ${token.bg} ${token.fg} ${className}`}
    >
      <span
        aria-hidden="true"
        className={`h-1.5 w-1.5 shrink-0 rounded-full bg-current ${
          shouldPulse ? "status-pulse" : ""
        }`}
      />
      {text}
    </span>
  );
}
