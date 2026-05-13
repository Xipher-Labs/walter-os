import CouncilChat from "@/app/components/CouncilChat";
import Link from "next/link";

/**
 * Ideation Session page — guided brainstorm using the 3-phase Council flow.
 *
 * Same flow as Council Chat but with a guided header and ideation framing.
 * "Spin as spec + plan" creates a Plane issue for the architect agent.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-8)
 * Task: T-46
 */
export const metadata = {
  title: "Ideation — Walter Control Tower",
};

export default function IdeationPage() {
  return (
    <main className="min-h-screen bg-zinc-50 dark:bg-zinc-950">
      <nav className="border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-6 py-3">
        <div className="max-w-4xl mx-auto flex items-center gap-4 text-sm">
          <Link
            href="/"
            className="text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100"
          >
            ← Dashboard
          </Link>
          <span className="text-zinc-300 dark:text-zinc-600">|</span>
          <span className="font-semibold text-zinc-900 dark:text-zinc-100">
            Ideation Session
          </span>
          <Link
            href="/council"
            className="text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100 ml-4"
          >
            Council Chat
          </Link>
          <Link
            href="/history"
            className="text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100"
          >
            History
          </Link>
        </div>
      </nav>

      <div className="max-w-4xl mx-auto p-6">
        <div className="mb-6">
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-100">
            Ideation Session
          </h1>
          <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
            Describe an idea. The Council deliberates. Turn the synthesis into a
            spec + plan with one click.
          </p>
        </div>

        <CouncilChat
          sessionType="ideation"
          guidedHeader="Describe your idea in 2-3 sentences. What problem does it solve? Who is it for? The Council will deliberate and help you shape it into a formal spec."
        />
      </div>
    </main>
  );
}
