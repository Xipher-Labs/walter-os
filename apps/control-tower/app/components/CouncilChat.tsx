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

export function createSessionId(sessionType: "chat" | "ideation"): string {
  const cryptoApi = globalThis.crypto;
  if (typeof cryptoApi?.randomUUID === "function") {
    return `${sessionType}-${cryptoApi.randomUUID()}`;
  }
  if (typeof cryptoApi?.getRandomValues === "function") {
    const bytes = new Uint8Array(16);
    cryptoApi.getRandomValues(bytes);
    return `${sessionType}-${Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")}`;
  }
  throw new Error("Web Crypto is required to create a Council Chat session");
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
    <div className="rounded-xl border border-border bg-surface-1 p-4 flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="font-medium text-sm text-foreground capitalize">
          {persona.id}
        </span>
        <span
          className={`text-xs rounded-full px-2 py-0.5 ${
            persona.trustTier === "high"
              ? "bg-status-ok-bg text-status-ok-fg"
              : persona.trustTier === "medium"
              ? "bg-accent-bg text-accent"
              : "bg-status-idle-bg text-status-idle-fg"
          }`}
        >
          {persona.trustTier}
        </span>
      </div>

      {/* Phase 1: Round 1 */}
      {(phase === "round1" || phase === "round2" || phase === "synthesis" || phase === "done") && (
        <div>
          <button
            type="button"
            onClick={() => setExpanded(expanded === "r1" ? null : "r1")}
            disabled={!hasR1}
            aria-expanded={expanded === "r1"}
            className="text-xs text-muted hover:text-foreground disabled:opacity-40"
          >
            Round 1
            {isLoading && phase === "round1" ? " …" : hasR1 ? " ▾" : " —"}
          </button>
          {expanded === "r1" && hasR1 && (
            <p className="mt-1 text-sm text-muted leading-relaxed whitespace-pre-wrap">
              {response?.r1}
            </p>
          )}
        </div>
      )}

      {/* Phase 2: Round 2 */}
      {(phase === "round2" || phase === "synthesis" || phase === "done") && (
        <div>
          <button
            type="button"
            onClick={() => setExpanded(expanded === "r2" ? null : "r2")}
            disabled={!hasR2}
            aria-expanded={expanded === "r2"}
            className="text-xs text-muted hover:text-foreground disabled:opacity-40"
          >
            Round 2
            {isLoading && phase === "round2" ? " …" : hasR2 ? " ▾" : " —"}
          </button>
          {expanded === "r2" && hasR2 && (
            <p className="mt-1 text-sm text-muted leading-relaxed whitespace-pre-wrap">
              {response?.r2}
            </p>
          )}
        </div>
      )}

      {/* Loading indicator — staggered pulse (reduced-motion safe via globals) */}
      {isLoading && (
        <div className="flex gap-1 mt-1" role="status" aria-label="thinking">
          {[0, 1, 2].map((i) => (
            <span
              key={i}
              className="h-1.5 w-1.5 rounded-full bg-accent status-pulse"
              style={{ animationDelay: `${i * 200}ms` }}
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
    <div className="rounded-xl border border-consensus-fg/40 bg-consensus-bg p-5 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold text-consensus-fg">Liaison synthesis</h3>
      </div>

      <p className="text-sm text-foreground leading-relaxed">
        {synthesis.summary}
      </p>

      {synthesis.convergences.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-muted mb-1">Convergences</h4>
          <ul className="list-disc list-inside space-y-0.5">
            {synthesis.convergences.map((c, i) => (
              <li key={i} className="text-sm text-muted">
                {c}
              </li>
            ))}
          </ul>
        </div>
      )}

      {synthesis.disagreements.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-muted mb-1">
            Open disagreements
          </h4>
          <ul className="list-disc list-inside space-y-0.5">
            {synthesis.disagreements.map((d, i) => (
              <li key={i} className="text-sm text-muted">
                {d}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div>
        <h4 className="text-xs font-semibold text-muted mb-1">
          Recommended path
        </h4>
        <p className="text-sm text-foreground">{synthesis.recommended_path}</p>
      </div>

      {synthesis.next_steps.length > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-muted mb-1">Next steps</h4>
          <ol className="list-decimal list-inside space-y-0.5">
            {synthesis.next_steps.map((s, i) => (
              <li key={i} className="text-sm text-muted">
                {s}
              </li>
            ))}
          </ol>
        </div>
      )}

      <button
        type="button"
        onClick={onSpinSpec}
        disabled={spinning}
        className="mt-2 self-start rounded-lg bg-consensus-fg px-4 py-2 text-sm font-medium text-background transition-colors hover:brightness-110 disabled:opacity-50"
      >
        {spinning ? "Creating spec…" : "Spin as spec + plan"}
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

    let sid: string;
    try {
      sid = createSessionId(sessionType);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setPhase("idle");
      return;
    }
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
        <div className="rounded-xl border border-consensus-fg/40 bg-consensus-bg p-4">
          <p className="text-sm text-consensus-fg">{guidedHeader}</p>
        </div>
      )}

      {/* Input */}
      <div className="flex flex-col gap-3">
        <label className="sr-only" htmlFor="council-message">
          Message for the Council
        </label>
        <textarea
          id="council-message"
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          disabled={phase !== "idle" && phase !== "done"}
          placeholder={
            sessionType === "ideation"
              ? "Describe your idea…"
              : "Ask the Council a question or describe a decision to deliberate…"
          }
          rows={3}
          className="w-full resize-none rounded-xl border border-border bg-surface-1 p-3 text-sm text-foreground placeholder:text-subtle transition-colors hover:border-border-strong disabled:opacity-50"
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey) && phase === "idle") {
              runChat();
            }
          }}
        />
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={runChat}
            disabled={!message.trim() || (phase !== "idle" && phase !== "done")}
            className="rounded-lg bg-accent px-5 py-2 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:opacity-40"
          >
            {phase === "done" ? "Ask again" : "Send to Council"}
          </button>
          {phase !== "idle" && (
            <span className="text-sm text-muted">
              {phaseLabel[phase]}
              {phase !== "done" && (
                <span className="tabular ml-2 text-subtle">{elapsed}s</span>
              )}
            </span>
          )}
        </div>
      </div>

      {error && (
        <div role="alert" className="rounded-xl border border-status-critical-fg/40 bg-status-critical-bg p-3">
          <p className="text-sm text-status-critical-fg">{error}</p>
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
        <div role="status" className="rounded-xl border border-status-ok-fg/40 bg-status-ok-bg p-3">
          <p className="text-sm text-status-ok-fg">
            Spec created: {spinResult}
          </p>
        </div>
      )}
    </div>
  );
}
