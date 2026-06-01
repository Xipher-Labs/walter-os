import { SectionTitle, Panel } from "@/app/components/ui/Panel";

/**
 * Metrics Dashboard — embeds the Grafana "Walter Council" dashboard in kiosk
 * mode. Re-skinned to tokens (D-2); the embed itself is themed dark via the
 * Grafana `theme=dark` param.
 *
 * SECURITY: the SA token is intentionally NOT placed in the iframe src URL
 * (exposed in history / access logs / Referer). Network-level controls gate the
 * embed. The `token` prop stays for forward-compat but is unused here.
 * (Enforced by tests/unit/metrics-dashboard-token.test.ts.)
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-4)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-40
 */

interface MetricsDashboardProps {
  grafanaUrl?: string;
  token?: string;
}

export default function MetricsDashboard({
  grafanaUrl = process.env.GRAFANA_URL ?? "http://grafana:3000",
  token = process.env.GRAFANA_SA_TOKEN,
}: MetricsDashboardProps) {
  if (!grafanaUrl) {
    return (
      <section aria-label="Metrics">
        <SectionTitle>Metrics</SectionTitle>
        <Panel className="text-center">
          <p className="text-sm text-muted">
            GRAFANA_URL not configured. Set it in .env.local.
          </p>
        </Panel>
      </section>
    );
  }

  // The SA token is deliberately omitted from the URL — see the security note
  // above. The prop is referenced here only to satisfy the unused-var lint.
  void token;
  const params = new URLSearchParams({
    kiosk: "true",
    theme: "dark",
  });

  const embedUrl = `${grafanaUrl}/d/walter-council/walter-council?${params.toString()}`;

  return (
    <section aria-label="Metrics">
      <SectionTitle
        meta={
          <a
            href={`${grafanaUrl}/d/walter-council/walter-council`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent transition-colors hover:text-accent-strong"
          >
            Open in Grafana
          </a>
        }
      >
        Metrics
      </SectionTitle>
      <Panel padded={false} className="overflow-hidden">
        <iframe
          src={embedUrl}
          width="100%"
          height="600"
          title="Walter Council Grafana Dashboard"
          sandbox="allow-same-origin allow-scripts allow-forms"
          className="block"
        />
      </Panel>
    </section>
  );
}
