/**
 * Metrics Dashboard — embeds the Grafana "Walter Council" dashboard.
 * Uses kiosk mode to hide Grafana chrome. Auth via service account token
 * embedded in the URL (Grafana anonymous embedding with SA token).
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-4)
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
      <section>
        <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-3">
          Metrics
        </h2>
        <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900 p-6 text-center">
          <p className="text-sm text-zinc-400 italic">
            GRAFANA_URL not configured. Set it in .env.local.
          </p>
        </div>
      </section>
    );
  }

  // Build Grafana embed URL
  // Dashboard UID is "walter-council" (provisioned by T-4)
  // kiosk=true hides the top navbar
  //
  // NOTE: The SA token is intentionally NOT added to the URL query string.
  // Tokens in iframe src URLs are exposed in browser history, server access
  // logs, and Referer headers sent to third parties. Grafana authentication
  // for embedded dashboards should use network-level controls (Tailscale,
  // same-origin proxy, or Grafana anonymous access with IP allowlist).
  // The `token` prop is accepted for forward-compatibility but not used here.
  void token; // suppress unused-variable warning
  const params = new URLSearchParams({
    kiosk: "true",
    theme: "dark",
  });

  const embedUrl = `${grafanaUrl}/d/walter-council/walter-council?${params.toString()}`;

  return (
    <section>
      <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-3">
        Metrics
      </h2>
      <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 overflow-hidden">
        <iframe
          src={embedUrl}
          width="100%"
          height="600"
          frameBorder="0"
          title="Walter Council Grafana Dashboard"
          sandbox="allow-same-origin allow-scripts allow-forms"
          className="block"
        />
      </div>
      <p className="text-xs text-zinc-400 dark:text-zinc-500 mt-2">
        Opens in Grafana: {grafanaUrl}
      </p>
    </section>
  );
}
