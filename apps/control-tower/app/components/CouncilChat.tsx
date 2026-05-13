"use client";

import { useState, useRef, useCallback } from "react";
import { COUNCIL_PERSONAS, COUNCIL_R2_ORDER } from "@/lib/council-personas";
import type { SynthesisResult } from "@/server/council/history";

/**
 * Council Chat UI — 3-phase deliberation interface.
 *
 * Phase 1: Round 1 — 6 parallel perspectives (spinners → populate as NDJSON streams)
 * Phase 2: Round 2 — sequential deliberation in trust-tier order
 * Phase 3: Synthesis — liaison summary with "Spin as spec + plan" CTA
 *
 * Refs: docs/specs/walter-council-v2.md (Part B, AC-7)
 * Task: T-45
 */

type Phase = "idle" | "round1" | "round2" | "synthesis" | "done";

interface AgentResponse {
  agent: string;
  r1?: string;
  r2?: string;
  loading: boolean;
}

function formatElapsed(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function AgentCard({
  persona,
  response,
  phase,
}: {
  persona: (typeof COUNCIL_PERSONAS)[0];
  response?: AgentResponse;
  phase: Phase;
}) {
  const [expanded, setExpanded] = useState<"r1" | "r2" | null>(null);
  const isLoading = response?.loading ?? false;
  const hasR1 = !!response?.r1;
  const hasR2 = !!response?.r2;

  return (
    <div className="rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="font-medium text-sm text-zinc-900 dark:text-zinc-100 capitalize">
          {persona.id}
        </span>
        <span
          className={`text-xs rounded-full px-2 py-0.5 ${
            persona.trustTier === "high"
              ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400"
              : persona.trustTier === "medium"
              ? "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-400"
              : "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400"
          }`}
        >
          {persona.trustTier}
        </span>
      </div>

      {/* Phase 1: Round 1 */}
      {(phase === "round1" || phase === "round2" || phase === "synthesis" || phase === "done") && (
        <div>
          <button
            onClick={() => setExpanded(expanded === "r1" ? null : "r1")}
            disabled={!hasR1}
            className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 disabled:opacity-40"
          >
            Round 1
            {isLoading && phase === "round1" ? " ..." : hasR1 ? " ▾" : " —"}
          </button>
          {expanded === "r1" && hasR1 && (
            <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300 leading-relaxed whitespace-pre-wrap">
              {response?.r1}
            </p>
          )}
        </div>
      )}

      {/* Phase 2: Round 2 */}
      {(phase === "round2" || phase === "synthesis" || phase === "done") && (
        <div>
          <button
            onClick={() => setExpanded(expanded === "r2" ? null : "r2")}
            disabled={!hasR2}
            className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 disabled:opacity-40"
          >
            Round 2
            {isLoading && phase === "round2" ? " ..." : hasR2 ? " ▾" : " —"}
          </button>
          {expanded === "r2" && hasR2 && (
            <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300 leading-relaxed whitespace-pre-wrap">
              {response?.r2}
            </p>
          )}
        </div>
      )}

      {/* Loading indicator */}
      {isLoading && (
        <div className="flex gap-1 mt-1">
          {[0, 1, 2].map((i) => (
            <span
              key={i}
              className="h-1.5 w-1.5 rounded-full bg-zinc-400 animate-bounce"
              style={{ animationDelay: `${i * 150}ms` }}
            />
          ))}
        </div>
      )}
    </div>
  );
}

interface SynthesisCardProps {
  synthesis: SynthesisResult;
  onSpinSpec: () => void;
  spinning: boolean;
}

function SynthesisCard({ synthesis, onSpinSpec, spinning }: SynthesisCardProps) {
  return (
    <div className="rounded-xl border-2 border-violet-300 dark:border-violet-700 bg-violet-50 dark:bg-violet-950/20 p-5 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold text-violet-800 dark:text-violet-300">
          Liaison Synthesis
        </h3>
      </div>

      <p className="text-sm text-zinc-700 dark:text-zinc-300 leading-relaxed">
        {synthesis.summary}
      </p>

      {synthesis.convergences.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-1">
            Convergences
          </h4>
          <ul className="list-disc list-inside space-y-0.5">
            {synthesis.convergences.map((c, i) => (
              <li key={i} className="text-sm text-zinc-600 dark:text-zinc-400">
                {c}
              </li>
            ))}
          </ul>
        </div>
      )}

      {synthesis.disagreements.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-1">
            Open Disagreements
          </h4>
          <ul className="list-disc list-inside space-y-0.5">
            {synthesis.disagreements.map((d, i) => (
              <li key={i} className="text-sm text-zinc-600 dark:text-zinc-400">
                {d}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div>
        <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-1">
          Recommended Path
        </h4>
        <p className="text-sm text-zinc-700 dark:text-zinc-300">
          {synthesis.recommended_path}
        </p>
      </div>

      {synthesis.next_steps.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-1">
            Next Steps
          </h4>
          <ol className="list-decimal list-inside space-y-0.5">
            {synthesis.next_steps.map((s, i) => (
              <li key={i} className="text-sm text-zinc-600 dark:text-zinc-400">
                {s}
              </li>
            ))}
          </ol>
        </div>
      )}

      <button
        onClick={onSpinSpec}
        disabled={spinning}
        className="mt-2 self-start rounded-lg bg-violet-600 hover:bg-violet-700 text-white text-sm font-medium px-4 py-2 transition-colors disabled:opacity-50"
      >
        {spinning ? "Creating spec..." : "Spin as spec + plan"}
      </button>
    </div>
  );
}

interface CouncilChatProps {
  sessionType?: "chat" | "ideation";
  guidedHeader?: string;
}

export default function CouncilChat({
  sessionType = "chat",
  guidedHeader,
}: CouncilChatProps) {
  const [message, setMessage] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [phaseStartTime, setPhaseStartTime] = useState<number>(0);
  const [elapsed, setElapsed] = useState(0);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [responses, setResponses] = useState<Map<string, AgentResponse>>(
    new Map()
  );
  const [synthesis, setSynthesis] = useState<SynthesisResult | null>(null);
  const [spinning, setSpinning] = useState(false);
  const [spinResult, setSpinResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const timerRef = useRef<NodeJS.Timeout | null>(null);

  const startTimer = useCallback((startMs: number) => {
    timerRef.current = setInterval(() => {
      setElapsed(Math.floor((Date.now() - startMs) / 1000));
    }, 1000);
  }, []);

  const stopTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const initResponses = useCallback(() => {
    const initial = new Map<string, AgentResponse>();
    for (const p of COUNCIL_PERSONAS) {
      initial.set(p.id, { agent: p.id, loading: false });
    }
    return initial;
  }, []);

  const runChat = useCallback(async () => {
    if (!message.trim()) return;
    setError(null);
    setSynthesis(null);
    setSpinResult(null);

    const sid = `${sessionType}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    setSessionId(sid);

    const newResponses = initResponses();
    // Mark all as loading for R1
    for (const [key, val] of newResponses) {
      newResponses.set(key, { ...val, loading: true });
    }
    setResponses(new Map(newResponses));

    const start = Date.now();
    setPhaseStartTime(start);
    setPhase("round1");
    startTimer(start);

    // --- Round 1 ---
    try {
      const r1Res = await fetch("/api/council-chat/round1", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, session_id: sid, session_type: sessionType }),
      });

      if (!r1Res.ok || !r1Res.body) {
        throw new Error(`Round 1 failed: ${r1Res.status}`);
      }

      const reader = r1Res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const event = JSON.parse(line) as {
              agent: string;
              content: string;
              round: number;
            };
            setResponses((prev) => {
              const next = new Map(prev);
              const existing = next.get(event.agent) ?? { agent: event.agent, loading: false };
              next.set(event.agent, { ...existing, r1: event.content, loading: false });
              return next;
            });
          } catch {
            // ignore malformed line
          }
        }
      }
    } catch (err) {
      stopTimer();
      setError(`Round 1 error: ${String(err)}`);
      setPhase("idle");
      return;
    }

    // --- Round 2 ---
    setPhase("round2");
    // Mark R2-order agents as loading sequentially (we simulate by marking all upfront)
    setResponses((prev) => {
      const next = new Map(prev);
      for (const p of COUNCIL_R2_ORDER) {
        const existing = next.get(p.id) ?? { agent: p.id, loading: false };
        next.set(p.id, { ...existing, loading: true });
      }
      return next;
    });

    try {
      const r2Res = await fetch("/api/council-chat/round2", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session_id: sid }),
      });

      if (!r2Res.ok || !r2Res.body) {
        throw new Error(`Round 2 failed: ${r2Res.status}`);
      }

      const reader = r2Res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const event = JSON.parse(line) as {
              agent: string;
              content: string;
            };
            setResponses((prev) => {
              const next = new Map(prev);
              const existing = next.get(event.agent) ?? { agent: event.agent, loading: false };
              next.set(event.agent, { ...existing, r2: event.content, loading: false });
              return next;
            });
          } catch {
            // ignore malformed line
          }
        }
      }
    } catch (err) {
      stopTimer();
      setError(`Round 2 error: ${String(err)}`);
      setPhase("idle");
      return;
    }

    // --- Synthesis ---
    setPhase("synthesis");

    try {
      const synthRes = await fetch("/api/council-chat/synthesis", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session_id: sid }),
      });

      if (!synthRes.ok) {
        throw new Error(`Synthesis failed: ${synthRes.status}`);
      }

      const synth = (await synthRes.json()) as SynthesisResult;
      setSynthesis(synth);
    } catch (err) {
      setError(`Synthesis error: ${String(err)}`);
    }

    stopTimer();
    setPhase("done");
  }, [message, sessionType, initResponses, startTimer, stopTimer]);

  const handleSpinSpec = async () => {
    if (!synthesis || !sessionId) return;
    setSpinning(true);
    try {
      const res = await fetch("/api/ideation/spin-spec", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          session_id: sessionId,
          synthesis,
          original_message: message,
        }),
      });
      if (res.ok) {
        const data = (await res.json()) as { issue_url?: string };
        setSpinResult(data.issue_url ?? "Spec created in Plane.");
      }
    } finally {
      setSpinning(false);
    }
  };

  const phaseLabel: Record<Phase, string> = {
    idle: "",
    round1: "Round 1: gathering perspectives...",
    round2: "Round 2: deliberating...",
    synthesis: "Synthesis...",
    done: "Complete",
  };

  return (
    <div className="flex flex-col gap-6">
      {guidedHeader && (
        <div className="rounded-xl bg-violet-50 dark:bg-violet-950/20 border border-violet-200 dark:border-violet-800 p-4">
          <p className="text-sm text-violet-700 dark:text-violet-300">
            {guidedHeader}
          </p>
        </div>
      )}

      {/* Input */}
      <div className="flex flex-col gap-3">
        <textarea
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          disabled={phase !== "idle" && phase !== "done"}
          placeholder={
            sessionType === "ideation"
              ? "Describe your idea..."
              : "Ask the Council a question or describe a decision to deliberate..."
          }
          rows={3}
          className="w-full rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-3 text-sm text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 resize-none focus:outline-none focus:ring-2 focus:ring-violet-500 disabled:opacity-50"
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey) && phase === "idle") {
              runChat();
            }
          }}
        />
        <div className="flex items-center gap-3">
          <button
            onClick={runChat}
            disabled={!message.trim() || (phase !== "idle" && phase !== "done")}
            className="rounded-lg bg-zinc-900 hover:bg-zinc-700 text-white text-sm font-medium px-5 py-2 transition-colors disabled:opacity-40"
          >
            {phase === "done" ? "Ask again" : "Send to Council"}
          </button>
          {phase !== "idle" && (
            <span className="text-sm text-zinc-500 dark:text-zinc-400">
              {phaseLabel[phase]}
              {phase !== "done" && (
                <span className="ml-2 font-mono text-zinc-400">{elapsed}s</span>
              )}
            </span>
          )}
        </div>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-950/20 p-3">
          <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
        </div>
      )}

      {/* Agent cards — only show during/after a session */}
      {phase !== "idle" && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {COUNCIL_PERSONAS.map((persona) => (
            <AgentCard
              key={persona.id}
              persona={persona}
              response={responses.get(persona.id)}
              phase={phase}
            />
          ))}
        </div>
      )}

      {/* Synthesis */}
      {synthesis && (
        <SynthesisCard
          synthesis={synthesis}
          onSpinSpec={handleSpinSpec}
          spinning={spinning}
        />
      )}

      {spinResult && (
        <div className="rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-950/20 p-3">
          <p className="text-sm text-emerald-700 dark:text-emerald-400">
            Spec created: {spinResult}
          </p>
        </div>
      )}
    </div>
  );
}
