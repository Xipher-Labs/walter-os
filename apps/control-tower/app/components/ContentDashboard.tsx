import { SectionTitle, Panel } from "@/app/components/ui/Panel";

/**
 * ContentDashboard — embeds the Grafana "Walter DevRel Analytics" dashboard in
 * kiosk mode. Re-skinned to tokens (D-2). Mirrors MetricsDashboard.
 *
 * Refs: docs/specs/devrel-analytics-stack.md (AC-10, AC-11)
 *       docs/specs/control-tower-redesign.md (AC-4)
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
      <section aria-label="Content analytics">
        <SectionTitle>Content analytics</SectionTitle>
        <Panel className="text-center">
          <p className="text-sm text-muted">
            GRAFANA_URL not configured. Set it in .env.local.
          </p>
        </Panel>
      </section>
    );
  }

  const params = new URLSearchParams({
    kiosk: "true",
    theme: "dark",
    from: "now-30d",
    to: "now",
    ...(token ? { auth_token: token } : {}),
  });

  const embedUrl = `${grafanaUrl}/d/${dashboardUid}/walter-devrel-analytics?${params.toString()}`;

  return (
    <section aria-label="Content analytics">
      <SectionTitle
        meta={
          <a
            href={`${grafanaUrl}/d/${dashboardUid}/walter-devrel-analytics`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent transition-colors hover:text-accent-strong"
          >
            Open in Grafana
          </a>
        }
      >
        Content analytics
      </SectionTitle>
      <Panel padded={false} className="overflow-hidden">
        <iframe
          src={embedUrl}
          width="100%"
          height={height}
          title="Walter DevRel Analytics Dashboard"
          sandbox="allow-same-origin allow-scripts allow-forms"
          className="block"
        />
      </Panel>
      <p className="mt-2 text-xs text-subtle">
        Data source: walter_devrel_analytics DB. Refreshes every 1h.
      </p>
    </section>
  );
}
