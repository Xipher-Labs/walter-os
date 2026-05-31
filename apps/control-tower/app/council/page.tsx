import CouncilChat from "@/app/components/CouncilChat";
import TopNav from "@/app/components/ui/TopNav";

/**
 * Council Chat page — 3-phase deliberation UI.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-7)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-45
 */
export const metadata = {
  title: "Council Chat — Walter Control Tower",
};

export default function CouncilChatPage() {
  return (
    <div className="min-h-screen bg-background">
      <TopNav active="/council" />
      <main className="mx-auto max-w-4xl px-4 py-6 sm:px-6">
        <header className="mb-6">
          <h1 className="text-xl font-bold text-foreground">Council Chat</h1>
          <p className="mt-1 text-sm text-muted">
            3-phase deliberation: parallel groupthink → sequential discussion →
            liaison synthesis.
          </p>
        </header>
        <CouncilChat sessionType="chat" />
      </main>
    </div>
  );
}
