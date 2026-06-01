import { STATUS_TOKENS, type StatusKind } from "./status";

/**
 * StatusDot — the atom of the Control Tower status language (D-4).
 *
 * A coloured dot that always carries an accessible label so colour is never
 * the sole signal (WCAG 1.4.1). When `label` text is rendered next to the dot
 * by the caller, pass `srOnlyLabel={false}` and supply your own visible text;
 * otherwise the dot ships its own visually-hidden label.
 *
 * Pulsing (working / blocked / critical) is CSS-only and respects
 * prefers-reduced-motion via the global guard in globals.css.
 */
export default function StatusDot({
  status,
  label,
  size = "md",
  pulse,
  srOnlyLabel = true,
  className = "",
}: {
  status: StatusKind;
  /** Override the default label (e.g. "panic", "primary"). */
  label?: string;
  size?: "sm" | "md";
  /** Override the token's default pulse behaviour. */
  pulse?: boolean;
  /** Render the label for screen readers only (default true). */
  srOnlyLabel?: boolean;
  className?: string;
}) {
  const token = STATUS_TOKENS[status];
  const text = label ?? token.label;
  const shouldPulse = pulse ?? token.pulse;
  const dim = size === "sm" ? "h-1.5 w-1.5" : "h-2 w-2";

  return (
    <span className={`inline-flex items-center gap-1.5 ${className}`}>
      <span
        aria-hidden="true"
        className={`${dim} shrink-0 rounded-full bg-current ${token.fg} ${
          shouldPulse ? "status-pulse" : ""
        }`}
      />
      <span className={srOnlyLabel ? "sr-only" : `text-xs ${token.fg}`}>
        {text}
      </span>
    </span>
  );
}
