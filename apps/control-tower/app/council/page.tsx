import CouncilChat from "@/app/components/CouncilChat";
import Link from "next/link";

/**
 * Council Chat page — 3-phase deliberation UI.
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-7)
 * Task: T-45
 */
export const metadata = {
  title: "Council Chat — Walter Control Tower",
};

export default function CouncilChatPage() {
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
            Council Chat
          </span>
          <Link
            href="/ideation"
            className="text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100 ml-4"
          >
            Ideation Session
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
            Council Chat
          </h1>
          <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
            3-phase deliberation: parallel groupthink → sequential discussion →
            liaison synthesis
          </p>
        </div>

        <CouncilChat sessionType="chat" />
      </div>
    </main>
  );
}
