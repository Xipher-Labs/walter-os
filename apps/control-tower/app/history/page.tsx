import TopNav from "@/app/components/ui/TopNav";
import HistoryClient from "./HistoryClient";

/**
 * Conversation History shell.
 *
 * Keep this page as a Server Component so the shared TopNav can render
 * VersionBadge with server-only env vars. The searchable session list lives in
 * HistoryClient.
 */

export default function HistoryPage() {
  return (
    <div className="min-h-screen bg-background">
      <TopNav active="/history" />
      <main className="mx-auto max-w-4xl px-4 py-6 sm:px-6">
        <HistoryClient />
      </main>
    </div>
  );
}
