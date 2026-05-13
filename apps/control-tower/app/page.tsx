import AgentStatusBoard from "@/app/components/AgentStatusBoard";
import DecisionTimeline from "@/app/components/DecisionTimeline";
import MetricsDashboard from "@/app/components/MetricsDashboard";
import CostDashboard from "@/app/components/CostDashboard";
import HAStatus from "@/app/components/HAStatus";
import AlertFeed from "@/app/components/AlertFeed";
import ModeIndicator from "@/app/components/ModeIndicator";
import VersionBadge from "@/app/components/VersionBadge";
import Link from "next/link";

/**
 * Walter Council Control Tower — Main Dashboard
 *
 * Server Component shell. Client components handle real-time updates.
 */
export default function DashboardPage() {
  return (
    <main className="min-h-screen bg-zinc-50 dark:bg-zinc-950">
      {/* Accessible page title — visually hidden, used by tests and screen readers */}
      <h1 className="sr-only">Walter Council</h1>

      {/* Top nav */}
      <nav className="border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-6 py-3">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <span className="font-bold text-zinc-900 dark:text-zinc-100">
            Walter Council — Control Tower
          </span>
          <div className="flex items-center gap-4 text-sm text-zinc-500 dark:text-zinc-400">
            <Link href="/council" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Council Chat
            </Link>
            <Link href="/ideation" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Ideation
            </Link>
            <Link href="/history" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              History
            </Link>
            <Link href="/content" className="hover:text-zinc-900 dark:hover:text-zinc-100">
              Content Analytics
            </Link>
            <VersionBadge />
          </div>
        </div>
      </nav>

      {/* Dashboard grid */}
      <div className="max-w-6xl mx-auto p-6 flex flex-col gap-8">
        {/* Row 1: Mode + Alerts */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-1">
            <ModeIndicator />
          </div>
          <div className="lg:col-span-2">
            <AlertFeed />
          </div>
        </div>

        {/* Row 2: Agent Status Board */}
        <AgentStatusBoard />

        {/* Row 3: HA Status + Cost */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <HAStatus />
          <CostDashboard />
        </div>

        {/* Row 4: Decision Timeline */}
        <DecisionTimeline />

        {/* Row 5: Grafana embed */}
        <MetricsDashboard />
      </div>
    </main>
  );
}
