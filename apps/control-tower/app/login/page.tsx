type SearchParams = Record<string, string | string[] | undefined>;

type LoginPageProps = {
  searchParams?: SearchParams | Promise<SearchParams>;
};

function single(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await Promise.resolve(searchParams ?? {});
  const next = single(params.next) ?? "/";
  const hasError = single(params.error) === "1";

  return (
    <main className="min-h-screen bg-zinc-950 text-zinc-100 flex items-center justify-center px-6">
      <section className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold tracking-normal">
          Control Tower
        </h1>
        <p className="mt-2 text-sm text-zinc-400">
          Enter the admin token to continue.
        </p>
        <form action="/api/login" method="post" className="mt-6 space-y-4">
          <input type="hidden" name="next" value={next} />
          <label className="block">
            <span className="text-sm font-medium text-zinc-300">Admin token</span>
            <input
              name="token"
              type="password"
              autoComplete="current-password"
              required
              className="mt-2 w-full rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-zinc-100 outline-none focus:border-zinc-400"
            />
          </label>
          {hasError ? (
            <p className="text-sm text-red-300">Invalid token.</p>
          ) : null}
          <button
            type="submit"
            className="w-full rounded-md bg-zinc-100 px-4 py-2 font-medium text-zinc-950 hover:bg-white"
          >
            Sign in
          </button>
        </form>
      </section>
    </main>
  );
}
