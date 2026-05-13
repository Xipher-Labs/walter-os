import ContentDashboard from "@/app/components/ContentDashboard";
import Link from "next/link";

/**
 * DevRel Analytics — Content Performance Tab
 *
 * Phase V Part C — AC-10
 * Shows: top 5 pieces/month, optimal hours heatmap, pipeline drafts,
 * total ad spend, ROI per content. Embeds Grafana walter-devrel-analytics
 * dashboard and provides quick-access CLI hints for the devrel-analyst skill.
 *
 * Refs: docs/specs/devrel-analytics-stack.md (AC-10)
 */
export default function ContentPage() {
  return (
    <main className="min-h-screen bg-zinc-50 dark:bg-zinc-950">
      {/* Top nav */}
      <nav className="border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-6 py-3">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <span className="font-bold text-zinc-900 dark:text-zinc-100">
            Walter Council — Control Tower
          </span>
          <div className="flex items-center gap-4 text-sm text-zinc-500 dark:text-zinc-400">
            <Link href="/" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Dashboard
            </Link>
            <Link href="/council" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Council Chat
            </Link>
            <Link href="/ideation" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Ideation
            </Link>
            <Link href="/history" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              History
            </Link>
            <span className="text-zinc-900 dark:text-zinc-100 font-medium">
              Content Analytics
            </span>
          </div>
        </div>
      </nav>

      {/* Content analytics grid */}
      <div className="max-w-6xl mx-auto p-6 flex flex-col gap-8">
        <div>
          <h1 className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">
            DevRel Analytics
          </h1>
          <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
            Content performance, optimal hours, ad ROI. Data from{" "}
            <code className="text-xs bg-zinc-100 dark:bg-zinc-800 px-1 py-0.5 rounded">
              walter_devrel_analytics
            </code>{" "}
            DB.
          </p>
        </div>

        {/* Main Grafana embed */}
        <ContentDashboard />

        {/* CLI quick-access */}
        <section className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-6">
          <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-4">
            devrel-analyst CLI
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs font-mono">
            <div className="space-y-2">
              <p className="text-zinc-400 dark:text-zinc-500 font-sans text-xs mb-2">
                Top threads (last 30d):
              </p>
              <code className="block bg-zinc-950 dark:bg-zinc-900 text-green-400 p-3 rounded text-xs overflow-x-auto border border-zinc-800">
                python3 skills/devrel-analyst/scripts/query.py top_threads --since 30d --limit 5
              </code>
            </div>
            <div className="space-y-2">
              <p className="text-zinc-400 dark:text-zinc-500 font-sans text-xs mb-2">
                Pattern match (topic):
              </p>
              <code className="block bg-zinc-950 dark:bg-zinc-900 text-green-400 p-3 rounded text-xs overflow-x-auto border border-zinc-800">
                python3 skills/devrel-analyst/scripts/query.py pattern_match --topic "solana-rpc"
              </code>
            </div>
            <div className="space-y-2">
              <p className="text-zinc-400 dark:text-zinc-500 font-sans text-xs mb-2">
                Optimal posting hours:
              </p>
              <code className="block bg-zinc-950 dark:bg-zinc-900 text-green-400 p-3 rounded text-xs overflow-x-auto border border-zinc-800">
                python3 skills/devrel-analyst/scripts/query.py optimal_hours --platform twitter
              </code>
            </div>
            <div className="space-y-2">
              <p className="text-zinc-400 dark:text-zinc-500 font-sans text-xs mb-2">
                ROI per content piece:
              </p>
              <code className="block bg-zinc-950 dark:bg-zinc-900 text-green-400 p-3 rounded text-xs overflow-x-auto border border-zinc-800">
                python3 skills/devrel-analyst/scripts/query.py roi_per_content_piece --since 90d
              </code>
            </div>
          </div>
          <p className="text-xs text-zinc-400 dark:text-zinc-500 mt-4">
            Add{" "}
            <code className="bg-zinc-100 dark:bg-zinc-800 px-1 py-0.5 rounded">
              --dry-run
            </code>{" "}
            to any query for mock output without DB connection.
          </p>
        </section>
      </div>
    </main>
  );
}
