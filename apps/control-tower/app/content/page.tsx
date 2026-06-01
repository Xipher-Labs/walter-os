import ContentDashboard from "@/app/components/ContentDashboard";
import TopNav from "@/app/components/ui/TopNav";
import { SectionTitle, Panel } from "@/app/components/ui/Panel";

/**
 * DevRel Analytics — Content Performance.
 * Embeds the walter-devrel-analytics Grafana dashboard and surfaces quick CLI
 * hints for the devrel-analyst skill. Re-skinned to tokens (D-2).
 *
 * Refs: docs/specs/devrel-analytics-stack.md (AC-10)
 *       docs/specs/control-tower-redesign.md (AC-4)
 */

const CLI_HINTS: { label: string; cmd: string }[] = [
  {
    label: "Top threads (last 30d)",
    cmd: "python3 skills/devrel-analyst/scripts/query.py top_threads --since 30d --limit 5",
  },
  {
    label: "Pattern match (topic)",
    cmd: 'python3 skills/devrel-analyst/scripts/query.py pattern_match --topic "solana-rpc"',
  },
  {
    label: "Optimal posting hours",
    cmd: "python3 skills/devrel-analyst/scripts/query.py optimal_hours --platform twitter",
  },
  {
    label: "ROI per content piece",
    cmd: "python3 skills/devrel-analyst/scripts/query.py roi_per_content_piece --since 90d",
  },
];

export default function ContentPage() {
  return (
    <div className="min-h-screen bg-background">
      <TopNav active="/content" />
      <main className="mx-auto max-w-[1600px] px-4 py-6 sm:px-6">
        <header className="mb-6">
          <h1 className="text-xl font-semibold text-foreground">
            DevRel Analytics
          </h1>
          <p className="mt-1 text-sm text-muted">
            Content performance, optimal hours, ad ROI. Data from{" "}
            <code className="rounded bg-surface-2 px-1 py-0.5 text-xs text-foreground">
              walter_devrel_analytics
            </code>{" "}
            DB.
          </p>
        </header>

        <div className="flex flex-col gap-8">
          <ContentDashboard />

          <section aria-label="devrel-analyst CLI">
            <SectionTitle>devrel-analyst CLI</SectionTitle>
            <Panel>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                {CLI_HINTS.map((hint) => (
                  <div key={hint.label} className="flex flex-col gap-2">
                    <p className="text-xs text-muted">{hint.label}:</p>
                    <code className="tabular block overflow-x-auto rounded-lg border border-border bg-background p-3 text-xs text-status-ok-fg">
                      {hint.cmd}
                    </code>
                  </div>
                ))}
              </div>
              <p className="mt-4 text-xs text-subtle">
                Add{" "}
                <code className="rounded bg-surface-2 px-1 py-0.5">
                  --dry-run
                </code>{" "}
                to any query for mock output without a DB connection.
              </p>
            </Panel>
          </section>
        </div>
      </main>
    </div>
  );
}
