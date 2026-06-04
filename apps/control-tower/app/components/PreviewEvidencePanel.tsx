"use client";

import { useCallback, useEffect, useState } from "react";
import type {
  PreviewEvidenceItem,
  PreviewEvidenceResponse,
  PreviewEvidenceStatus,
} from "@/lib/preview-evidence";
import AsyncSurface from "@/app/components/ui/AsyncSurface";
import { Panel, SectionTitle } from "@/app/components/ui/Panel";
import StatusBadge from "@/app/components/ui/StatusBadge";
import type { StatusKind } from "@/app/components/ui/status";

const STATUS_KIND: Record<PreviewEvidenceStatus, StatusKind> = {
  complete: "ok",
  planned: "info",
  captured: "warn",
  invalid: "critical",
};

function formatGeneratedAt(value: string | null): string {
  if (!value) return "No timestamp";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function evidenceDetails(preview: PreviewEvidenceItem): string {
  const parts = [
    preview.hasPlan ? "plan" : null,
    preview.hasReport ? "report" : null,
    preview.screenshots > 0 ? `${preview.screenshots} screenshot(s)` : null,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" · ") : "no artifacts";
}

function PreviewRow({ preview }: { preview: PreviewEvidenceItem }) {
  return (
    <tr className="border-b border-border/60 last:border-0 transition-colors hover:bg-surface-2/40">
      <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold text-foreground">
        #{preview.pr}
      </td>
      <td className="px-4 py-3">
        <StatusBadge
          status={STATUS_KIND[preview.status]}
          label={preview.statusLabel}
          pulse={preview.status === "invalid"}
        />
      </td>
      <td className="px-4 py-3 text-xs text-muted">
        <div className="font-medium text-foreground">
          {evidenceDetails(preview)}
        </div>
        <div>{formatGeneratedAt(preview.generatedAt)}</div>
      </td>
      <td className="min-w-52 px-4 py-3 text-xs text-muted">
        {preview.url ? (
          <a
            href={preview.url}
            className="font-medium text-accent underline-offset-4 hover:underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            {preview.url}
          </a>
        ) : (
          <span>No preview URL yet</span>
        )}
        {(preview.provider || preview.app || preview.branch) && (
          <div className="mt-1 truncate">
            {[preview.provider, preview.app, preview.branch]
              .filter(Boolean)
              .join(" / ")}
          </div>
        )}
      </td>
      <td className="px-4 py-3">
        <StatusBadge
          status={preview.safetyOk ? "ok" : "warn"}
          label={preview.safetyOk ? "safe" : "incomplete"}
          pulse={false}
        />
      </td>
      <td className="max-w-72 px-4 py-3 text-xs text-muted">
        {preview.findings.length > 0
          ? preview.findings.slice(0, 2).join(" · ")
          : "No findings"}
      </td>
    </tr>
  );
}

export default function PreviewEvidencePanel() {
  const [data, setData] = useState<PreviewEvidenceResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchEvidence = useCallback(async () => {
    try {
      const res = await fetch("/api/preview-evidence");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData((await res.json()) as PreviewEvidenceResponse);
      setError(null);
    } catch {
      setError("Preview evidence unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEvidence();
  }, [fetchEvidence]);

  const previews = data?.previews ?? [];
  const invalidCount = previews.filter(
    (preview) => preview.status === "invalid"
  ).length;

  return (
    <section aria-label="Preview evidence">
      <SectionTitle
        meta={
          <>
            {invalidCount > 0 && (
              <StatusBadge
                status="critical"
                label={`${invalidCount} needs attention`}
              />
            )}
            <button
              type="button"
              onClick={() => {
                setLoading(true);
                setError(null);
                fetchEvidence();
              }}
              className="rounded-md border border-border bg-surface-1 px-2 py-0.5 text-xs font-medium text-muted transition-colors hover:border-border-strong hover:text-foreground"
            >
              Refresh
            </button>
          </>
        }
      >
        Preview evidence
      </SectionTitle>
      <AsyncSurface
        loading={loading}
        empty={previews.length === 0}
        error={error}
        onRetry={() => {
          setLoading(true);
          setError(null);
          fetchEvidence();
        }}
        emptyState={
          <p className="text-sm text-muted">
            No preview evidence bundles yet.
          </p>
        }
        skeleton={
          <Panel padded={false}>
            <div className="flex flex-col gap-2 p-4">
              {[0, 1, 2].map((i) => (
                <div
                  key={i}
                  className="h-10 animate-pulse rounded-lg bg-surface-2/60"
                />
              ))}
            </div>
          </Panel>
        }
      >
        <Panel padded={false} className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[920px] text-sm">
              <thead>
                <tr className="border-b border-border bg-surface-2/50 text-2xs uppercase tracking-wide text-muted">
                  <th className="px-4 py-2 text-left font-medium">PR</th>
                  <th className="px-4 py-2 text-left font-medium">State</th>
                  <th className="px-4 py-2 text-left font-medium">Evidence</th>
                  <th className="px-4 py-2 text-left font-medium">Preview</th>
                  <th className="px-4 py-2 text-left font-medium">Safety</th>
                  <th className="px-4 py-2 text-left font-medium">Findings</th>
                </tr>
              </thead>
              <tbody>
                {previews.map((preview) => (
                  <PreviewRow key={preview.pr} preview={preview} />
                ))}
              </tbody>
            </table>
          </div>
        </Panel>
      </AsyncSurface>
    </section>
  );
}
