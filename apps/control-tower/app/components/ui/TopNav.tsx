import Link from "next/link";
import VersionBadge from "@/app/components/VersionBadge";

/**
 * TopNav — the shared dashboard header.
 *
 * Every page previously re-declared its own nav inline with slightly different
 * markup and link sets (drift). This consolidates them: one wordmark, one link
 * set, and an `active` marker so the current section reads as current instead
 * of as a dead link. Keyboard focus rings come from the global :focus-visible.
 */

const LINKS = [
  { href: "/", label: "Overview" },
  { href: "/council", label: "Council" },
  { href: "/ideation", label: "Ideation" },
  { href: "/history", label: "History" },
  { href: "/content", label: "Content" },
] as const;

export default function TopNav({
  active,
  showVersion = true,
}: {
  active?: string;
  showVersion?: boolean;
}) {
  return (
    <nav className="border-b border-border bg-surface-1/80 backdrop-blur-sm">
      <div className="mx-auto flex max-w-[1600px] flex-col items-stretch gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4 sm:px-6">
        <Link
          href="/"
          className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 font-semibold text-foreground transition-colors hover:text-accent"
        >
          <span
            aria-hidden="true"
            className="h-2 w-2 rounded-full bg-accent status-pulse"
          />
          Walter Council
          <span className="text-subtle font-normal">Control Tower</span>
        </Link>
        <div className="flex min-w-0 flex-wrap items-center gap-1 text-sm">
          {LINKS.map((link) => {
            const isActive = active === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                aria-current={isActive ? "page" : undefined}
                className={`rounded-lg px-2.5 py-1 transition-colors ${
                  isActive
                    ? "bg-accent-bg text-accent"
                    : "text-muted hover:bg-surface-2 hover:text-foreground"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
          {showVersion && (
            <span className="ml-1 min-w-0 max-w-full border-l border-border pl-3 sm:ml-2">
              <VersionBadge />
            </span>
          )}
        </div>
      </div>
    </nav>
  );
}
