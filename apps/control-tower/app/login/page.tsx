type SearchParams = Record<string, string | string[] | undefined>;

type LoginPageProps = {
  searchParams?: SearchParams | Promise<SearchParams>;
};

function single(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

/**
 * Control Tower login — admin-token gate. Re-skinned to the token system (D-2);
 * the page renders in the dark theme like the rest of the cockpit.
 */
export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await Promise.resolve(searchParams ?? {});
  const next = single(params.next) ?? "/";
  const hasError = single(params.error) === "1";

  return (
    <main className="flex min-h-screen items-center justify-center bg-background px-6">
      <section className="w-full max-w-sm">
        <div className="mb-6 flex items-center gap-2">
          <span
            aria-hidden="true"
            className="h-2.5 w-2.5 rounded-full bg-accent status-pulse"
          />
          <h1 className="text-2xl font-semibold text-foreground">
            Control Tower
          </h1>
        </div>
        <p className="text-sm text-muted">
          Enter the admin token to continue.
        </p>
        <form action="/api/login" method="post" className="mt-6 space-y-4">
          <input type="hidden" name="next" value={next} />
          <label className="block">
            <span className="text-sm font-medium text-foreground">
              Admin token
            </span>
            <input
              name="token"
              type="password"
              autoComplete="current-password"
              required
              className="mt-2 w-full rounded-lg border border-border bg-surface-1 px-3 py-2 text-foreground transition-colors hover:border-border-strong"
            />
          </label>
          {hasError ? (
            <p role="alert" className="text-sm text-status-critical-fg">
              Invalid token.
            </p>
          ) : null}
          <button
            type="submit"
            className="w-full rounded-lg bg-accent px-4 py-2 font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            Sign in
          </button>
        </form>
      </section>
    </main>
  );
}
