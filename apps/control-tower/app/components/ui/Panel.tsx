import type { ReactNode } from "react";

/**
 * Panel + SectionTitle — the shared surface chrome for dashboard cards.
 *
 * SectionTitle replaces the old per-component uppercase-eyebrow heading (an
 * impeccable absolute ban: "uppercase eyebrow on every section"). Titles are
 * sentence case and carry an optional trailing slot for live meta (timestamp,
 * connection indicator) so every surface aligns its header the same way.
 */

export function SectionTitle({
  children,
  meta,
  as: As = "h2",
}: {
  children: ReactNode;
  meta?: ReactNode;
  as?: "h2" | "h3";
}) {
  return (
    <div className="mb-3 flex items-center justify-between gap-3">
      <As className="text-sm font-semibold text-foreground">{children}</As>
      {meta && <div className="flex items-center gap-2 text-xs">{meta}</div>}
    </div>
  );
}

/**
 * Panel — an elevated card surface. `tone` lets a high-priority surface read
 * heavier than its neighbours (D-3: vary card weight, no identical grid).
 */
export function Panel({
  children,
  className = "",
  tone = "default",
  padded = true,
}: {
  children: ReactNode;
  className?: string;
  tone?: "default" | "raised" | "flush";
  padded?: boolean;
}) {
  const toneClass =
    tone === "raised"
      ? "bg-surface-2 border-border-strong"
      : tone === "flush"
        ? "bg-transparent border-border"
        : "bg-surface-1 border-border";
  return (
    <div
      className={`rounded-xl border ${toneClass} ${padded ? "p-4" : ""} ${className}`}
    >
      {children}
    </div>
  );
}
