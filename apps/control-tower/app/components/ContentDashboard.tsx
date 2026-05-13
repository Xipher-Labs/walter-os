/**
 * ContentDashboard — embeds the Grafana "Walter DevRel Analytics" dashboard.
 *
 * Phase V Part C — AC-10, AC-11
 * Embeds walter-devrel-analytics Grafana dashboard in kiosk mode.
 * Mirrors the pattern from MetricsDashboard.tsx (Phase U, T-40).
 *
 * Refs: docs/specs/devrel-analytics-stack.md (AC-10, AC-11)
 */

interface ContentDashboardProps {
  grafanaUrl?: string;
  token?: string;
  /** Override the dashboard UID (default: walter-devrel-analytics) */
  dashboardUid?: string;
  /** iframe height in px (default: 800) */
  height?: number;
}

export default function ContentDashboard({
  grafanaUrl = process.env.GRAFANA_URL ?? "http://grafana:3000",
  token = process.env.GRAFANA_SA_TOKEN,
  dashboardUid = "walter-devrel-analytics",
  height = 800,
}: ContentDashboardProps) {
  if (!grafanaUrl) {
    return (
      <section>
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-3">
          Content Analytics
        </h2>
        <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900 p-6 text-center">
          <p className="text-sm text-zinc-400 italic">
            GRAFANA_URL not configured. Set it in .env.local.
          </p>
        </div>
      </section>
    );
  }

  // Build Grafana embed URL for DevRel analytics dashboard
  const params = new URLSearchParams({
    kiosk: "true",
    theme: "dark",
    from: "now-30d",
    to: "now",
    ...(token ? { auth_token: token } : {}),
  });

  const embedUrl = `${grafanaUrl}/d/${dashboardUid}/walter-devrel-analytics?${params.toString()}`;

  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
          Content Analytics
        </h2>
        <a
          href={`${grafanaUrl}/d/${dashboardUid}/walter-devrel-analytics`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200"
        >
          Open in Grafana
        </a>
      </div>
      <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 overflow-hidden">
        <iframe
          src={embedUrl}
          width="100%"
          height={height}
          frameBorder="0"
          title="Walter DevRel Analytics Dashboard"
          sandbox="allow-same-origin allow-scripts allow-forms"
          className="block"
        />
      </div>
      <p className="text-xs text-zinc-400 dark:text-zinc-500 mt-2">
        Data source: walter_devrel_analytics DB. Refreshes every 1h.
        Last ingestion visible in Grafana panel.
      </p>
    </section>
  );
}
