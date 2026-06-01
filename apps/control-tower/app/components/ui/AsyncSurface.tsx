import type { ReactNode } from "react";

/**
 * AsyncSurface — the shared loading / empty / error triad for every fetching
 * surface (D-5). Callers pass their current state and the three slots; the
 * wrapper guarantees consistent skeletons, a welcoming empty state, and an
 * error state with a retry affordance across the whole dashboard.
 *
 * Precedence: error > loading > empty > children. Error wins over loading so a
 * failed refresh of already-shown data still surfaces (callers that prefer to
 * keep stale data on error simply don't pass `error`).
 *
 * Refs: docs/specs/control-tower-redesign.md (AC-2, AC-4, AC-5, D-5)
 */

export interface AsyncSurfaceProps {
  loading: boolean;
  /** True when the fetch succeeded but returned nothing to show. */
  empty?: boolean;
  /** Non-null message when the last fetch failed. */
  error?: string | null;
  /** Skeleton shown while loading. Falls back to a generic shimmer. */
  skeleton?: ReactNode;
  /** Content shown when empty. */
  emptyState?: ReactNode;
  /** Invoked by the error state's Retry button. */
  onRetry?: () => void;
  children: ReactNode;
}

function DefaultSkeleton() {
  return (
    <div className="flex flex-col gap-2" aria-hidden="true">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="h-9 rounded-lg bg-surface-2/60 animate-pulse"
        />
      ))}
    </div>
  );
}

export default function AsyncSurface({
  loading,
  empty = false,
  error = null,
  skeleton,
  emptyState,
  onRetry,
  children,
}: AsyncSurfaceProps) {
  if (error) {
    return (
      <div
        role="alert"
        className="rounded-xl border border-border bg-surface-1 p-5 text-center"
      >
        <p className="text-sm text-status-critical-fg">{error}</p>
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 rounded-lg bg-accent-bg px-3 py-1.5 text-xs font-medium text-accent transition-colors hover:bg-accent hover:text-on-accent"
          >
            Retry
          </button>
        )}
      </div>
    );
  }

  if (loading) {
    return (
      <div role="status" aria-busy="true" aria-live="polite">
        <span className="sr-only">Loading…</span>
        {skeleton ?? <DefaultSkeleton />}
      </div>
    );
  }

  if (empty) {
    return (
      <div className="rounded-xl border border-dashed border-border bg-surface-1/50 p-6 text-center">
        {emptyState ?? (
          <p className="text-sm text-muted">Nothing to show yet.</p>
        )}
      </div>
    );
  }

  return <>{children}</>;
}
