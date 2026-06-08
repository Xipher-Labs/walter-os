import AgentStatusBoard from "@/app/components/AgentStatusBoard";
import DecisionTimeline from "@/app/components/DecisionTimeline";
import MetricsDashboard from "@/app/components/MetricsDashboard";
import CostDashboard from "@/app/components/CostDashboard";
import HAStatus from "@/app/components/HAStatus";
import AlertFeed from "@/app/components/AlertFeed";
import ModeIndicator from "@/app/components/ModeIndicator";
import PreviewEvidencePanel from "@/app/components/PreviewEvidencePanel";
import OperatorReadiness from "@/app/components/OperatorReadiness";
import TopNav from "@/app/components/ui/TopNav";

export const dynamic = "force-dynamic";

/**
 * Walter Council Control Tower — overview.
 *
 * Server Component shell; the surfaces are client components that stream/poll
 * their own data. Layout is a dense overview grid (D-3): on desktop (>=1280px)
 * every surface is visible at once without scrolling for the signal; on tablet
 * (768-1279px) it collapses to two columns; below that, a single column.
 *
 * Card weight varies by information priority rather than a uniform grid
 * (impeccable: no identical card grid). Mode + alerts lead, the agent board is
 * the wide centrepiece, health + spend pair, the timeline is the tall feed,
 * and the Grafana metrics embed anchors the bottom full-width.
 */
export default function DashboardPage() {
  return (
    <div className="min-h-screen bg-background">
      <a
        href="#overview"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-lg focus:bg-surface-2 focus:px-3 focus:py-2 focus:text-sm focus:text-foreground"
      >
        Skip to overview
      </a>

      <TopNav active="/" />

      <main
        id="overview"
        className="mx-auto max-w-[1600px] px-4 py-6 sm:px-6"
      >
        <h1 className="sr-only">Walter Council — Control Tower overview</h1>

        {/* xl: 12-col masthead so weight varies; md: 2-col; base: stacked. */}
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-12">
          {/* Lead row: consensus mode (compact) + alerts (wide). */}
          <div className="md:col-span-1 xl:col-span-4">
            <ModeIndicator />
          </div>
          <div className="md:col-span-1 xl:col-span-8">
            <AlertFeed />
          </div>

          {/* Centrepiece: the agent board spans full width. */}
          <div className="md:col-span-2 xl:col-span-12">
            <AgentStatusBoard />
          </div>

          {/* Read-only operating paths and verification commands. */}
          <div className="md:col-span-2 xl:col-span-12">
            <OperatorReadiness />
          </div>

          {/* Operational pair: service health + spend. */}
          <div className="md:col-span-1 xl:col-span-5">
            <HAStatus />
          </div>
          <div className="md:col-span-1 xl:col-span-7">
            <CostDashboard />
          </div>

          {/* Review readiness: per-PR preview plans, captures, and bundles. */}
          <div className="md:col-span-2 xl:col-span-12">
            <PreviewEvidencePanel />
          </div>

          {/* Tall feed: decision timeline. */}
          <div className="md:col-span-2 xl:col-span-12">
            <DecisionTimeline />
          </div>

          {/* Anchor: Grafana metrics embed, full width. */}
          <div className="md:col-span-2 xl:col-span-12">
            <MetricsDashboard />
          </div>
        </div>
      </main>
    </div>
  );
}
