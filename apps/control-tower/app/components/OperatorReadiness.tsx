import {
  OPERATIONAL_READINESS_CHECKS,
  OPERATOR_READINESS_MODES,
  type ReadinessDoc,
} from "@/lib/operator-readiness";
import { SectionTitle, Panel } from "@/app/components/ui/Panel";
import StatusBadge from "@/app/components/ui/StatusBadge";
import type { StatusKind } from "@/app/components/ui/status";

function normalizeRepoUrl(raw: string | undefined | null): string | null {
  if (raw === undefined || raw === null) return null;
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  return trimmed.replace(/\/+$/, "");
}

const REPO_URL = normalizeRepoUrl(process.env.NEXT_PUBLIC_WALTER_REPO_URL);

function docHref(path: string): string | null {
  return REPO_URL ? `${REPO_URL}/blob/main/${path}` : null;
}

function DocLinks({ docs }: { docs: ReadinessDoc[] }) {
  return (
    <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs">
      {docs.map((doc) => {
        const href = docHref(doc.path);
        return href ? (
          <a
            key={doc.path}
            href={href}
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent underline decoration-accent/40 underline-offset-2 transition-colors hover:decoration-accent"
          >
            {doc.label}
          </a>
        ) : (
          <code
            key={doc.path}
            className="max-w-full overflow-hidden text-ellipsis whitespace-nowrap rounded bg-surface-2 px-1.5 py-0.5 text-2xs text-muted"
          >
            {doc.path}
          </code>
        );
      })}
    </div>
  );
}

function ReadinessRow({
  label,
  status,
  statusLabel,
  summary,
  command,
  docs,
}: {
  label: string;
  status: StatusKind;
  statusLabel: string;
  summary: string;
  command: string;
  docs: ReadinessDoc[];
}) {
  return (
    <div className="grid gap-3 border-b border-border/60 py-3 last:border-0 sm:grid-cols-[minmax(8rem,0.8fr)_minmax(0,1.6fr)_minmax(11rem,1fr)]">
      <div className="flex min-w-0 items-start justify-between gap-2 sm:block">
        <p className="text-sm font-medium text-foreground">{label}</p>
        <StatusBadge
          status={status}
          label={statusLabel}
          pulse={false}
          className="sm:mt-1"
        />
      </div>

      <div className="min-w-0">
        <p className="text-sm text-muted">{summary}</p>
        <div className="mt-2">
          <DocLinks docs={docs} />
        </div>
      </div>

      <code className="min-w-0 self-start overflow-x-auto rounded-lg border border-border bg-background px-2.5 py-2 text-xs text-foreground">
        {command}
      </code>
    </div>
  );
}

export default function OperatorReadiness() {
  return (
    <section aria-label="Operator readiness">
      <SectionTitle
        meta={<StatusBadge status="info" label="read-only" pulse={false} />}
      >
        Operator readiness
      </SectionTitle>

      <Panel padded={false} className="overflow-hidden">
        <div className="grid gap-0 xl:grid-cols-2">
          <div className="border-b border-border/80 p-4 xl:border-b-0 xl:border-r">
            <h3 className="text-xs font-semibold text-subtle">
              Operating path
            </h3>
            <div className="mt-1">
              {OPERATOR_READINESS_MODES.map((mode) => (
                <ReadinessRow
                  key={mode.id}
                  label={mode.label}
                  status={mode.status}
                  statusLabel={mode.statusLabel}
                  summary={mode.summary}
                  command={mode.primaryCommand}
                  docs={mode.docs}
                />
              ))}
            </div>
          </div>

          <div className="p-4">
            <h3 className="text-xs font-semibold text-subtle">
              Safe checks
            </h3>
            <div className="mt-1">
              {OPERATIONAL_READINESS_CHECKS.map((check) => (
                <ReadinessRow
                  key={check.id}
                  label={check.label}
                  status={check.status}
                  statusLabel={check.statusLabel}
                  summary={check.summary}
                  command={check.command}
                  docs={check.docs}
                />
              ))}
            </div>
          </div>
        </div>
      </Panel>
    </section>
  );
}
