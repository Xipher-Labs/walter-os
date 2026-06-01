import CouncilChat from "@/app/components/CouncilChat";
import TopNav from "@/app/components/ui/TopNav";

/**
 * Ideation Session page — guided brainstorm using the 3-phase Council flow.
 * "Spin as spec + plan" creates a Plane issue for the architect agent.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-8)
 *       docs/specs/control-tower-redesign.md (AC-4)
 * Task: T-46
 */
export const metadata = {
  title: "Ideation — Walter Control Tower",
};

export default function IdeationPage() {
  return (
    <div className="min-h-screen bg-background">
      <TopNav active="/ideation" />
      <main className="mx-auto max-w-4xl px-4 py-6 sm:px-6">
        <header className="mb-6">
          <h1 className="text-xl font-bold text-foreground">Ideation Session</h1>
          <p className="mt-1 text-sm text-muted">
            Describe an idea. The Council deliberates. Turn the synthesis into a
            spec + plan with one click.
          </p>
        </header>
        <CouncilChat
          sessionType="ideation"
          guidedHeader="Describe your idea in 2-3 sentences. What problem does it solve? Who is it for? The Council will deliberate and help you shape it into a formal spec."
        />
      </main>
    </div>
  );
}
