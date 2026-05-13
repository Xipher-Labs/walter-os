# `minimumReleaseAge` — package-manager coverage gap

> 2026-05-12. Re-check on the quarterly upgrade cadence.

Walter-OS treats freshly-published package versions as suspicious
(typosquats, compromised pushes, fast-moving breaks). Mitigation: a
release-age floor of 7 days. Coverage varies by package manager.

## Native support

**Bun** — `minimumReleaseAge` (seconds) in `bunfig.toml`:

```toml
[install]
minimumReleaseAge = 604800
minimumReleaseAgeExcludes = ["@walter-os/internal-*"]
```

Docs: <https://bun.sh/docs/install/security>

**pnpm** (Walter-OS canonical) — `minimum-release-age` (minutes) in
`.npmrc`:

```ini
minimum-release-age=10080
minimum-release-age-exclude=@walter-os/*
```

Docs: <https://pnpm.io/settings#minimumreleaseage>

## No native support (the gap)

**npm** — Walter-OS does not use it directly. When forced, wrap via
socket.dev (`socket npm install` has an age filter), the community
`safe-npm`, or the audit-script fallback (below). npm/cli#3649 has been
open since 2021 — do not block on upstream.

**cargo** — no native flag. crates.io exposes `versions[].created_at`
via `https://crates.io/api/v1/crates/<name>`. cargo-deny can ban
specific versions but has no rolling window
(EmbarkStudios/cargo-deny#677). Mitigation: audit-script fallback +
lockfile freeze + quarterly bump.

**uvx / uv / pip** — no native flag. PyPI exposes `upload_time` at
`https://pypi.org/pypi/<pkg>/<ver>/json`. `--constraint` pins but does
not enforce a rolling age window. Mitigation: audit-script + `uv.lock`
freeze.

## Walter-OS posture

| Manager | Native | Walter-OS uses it? | Mitigation |
|---|---|---|---|
| Bun    | ✅ | indirectly       | native |
| pnpm   | ✅ | yes (canonical)  | native, configured in `.npmrc` |
| npm    | ❌ | no — wrap if forced | socket.dev or audit-script |
| cargo  | ❌ | future (Rust)    | audit-script via crates.io API |
| uvx/uv | ❌ | yes              | audit-script via PyPI API |

The audit-script fallback is one algorithm with three registry
adapters. It runs inside `daily-supply-chain-audit` and blocks the
session when too-fresh dependencies land in the diff. The script itself
lands in PR #56 `feat/protection-levels`
(`scripts/walter/check-release-age.py`).

## Action items

- [ ] Pin pnpm `minimum-release-age` in repo `.npmrc` (currently relies
      on operator's global config).
- [ ] Land `check-release-age.py` with PR #56 — covers npm + cargo +
      uvx gaps with three registry adapters.
- [ ] Re-check this doc next quarter.
