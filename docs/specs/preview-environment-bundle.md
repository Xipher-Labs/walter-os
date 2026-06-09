# Preview Environment Bundle

## Problem

AD-10 requires preview environments to give the operator a review surface:
ephemeral per-PR deploy, seed data, screenshots, and a report bundle. Walter-OS
already has PR scoring and post-merge health checks, but it has no standard
artifact format for preview evidence.

## Goals

- Add `walter-os preview bundle` as the first AD-10 primitive.
- Add `walter-os preview plan --dry-run` as the provider-neutral deployment
  contract before live provider adapters exist.
- Add `walter-os preview capture` to produce screenshot artifacts from an
  existing preview URL.
- Add `walter-os preview local` as the first provider-shaped adapter for
  loopback previews that are already running on the operator machine.
- Add `walter-os preview static` as the first self-contained ephemeral adapter:
  serve an already-built static directory on loopback, capture evidence, and
  tear the server down without cloud credentials.
- Add `walter-os preview verify` so preview evidence can be checked before it
  is used for PR Score, Control Tower, or human review.
- Package an existing preview URL, seed manifest, and screenshots into a
  local report bundle with deterministic layout and artifact hashes.
- Surface local preview plans, screenshots, and report bundles in Control Tower
  so the operator can see review readiness without reading `.walter/` by hand.
- Fail closed unless `walter-repo-config.yaml` explicitly enables
  `preview_deploy: true`.
- Reject secret-like artifacts so production secrets are not copied into preview
  evidence.
- Emit JSON for future Control Tower, PR Score, and release automation.

## Non-Goals

- Do not deploy cloud preview environments in this slice.
- Do not mint credentials, call cloud providers, or touch production secrets.
- Do not merge PRs or relax the hard-limit floor.

## Contract

`walter-os preview bundle` writes:

```text
.walter/previews/preview-pr-<number>/
  README.md
  preview-report.json
  seed/<seed basename>
  screenshots/<screenshot basenames>
```

The command accepts only `http://` or `https://` preview URLs, requires a seed
manifest and at least one screenshot, and rejects secret-like artifact names
such as `.env`, `.pem`, `.key`, `secret*`, or `token*`.

`walter-os preview capture` writes:

```text
.walter/previews/preview-pr-<number>/
  screenshots/<name>.png
```

The capture command uses an already-available local Playwright CLI through
`npx --no-install playwright screenshot`, accepts only `http://` or `https://`
URLs, requires a safe screenshot name, rejects overwrites, and emits artifact
JSON when `--json` is passed. It captures an existing preview URL only; it does
not deploy, auto-install packages, or mint credentials.

Control Tower exposes read-only preview evidence through
`GET /api/preview-evidence`. The route reads `WALTER_PREVIEW_ROOT` when
configured and otherwise defaults to the repository `.walter/previews`
directory. The dashboard shows each `preview-pr-<number>` directory as
`Bundle ready`, `Dry-run plan`, `Screenshot only`, or `Needs attention`,
preserving the same safety invariants as PR Score.

`walter-os preview plan --dry-run` writes:

```text
.walter/previews/preview-pr-<number>/
  seed/
    <seed basename>
  preview-plan.json
```

The plan command requires `--dry-run`, a supported provider (`local`, `vercel`,
`cloudflare-pages`, `netlify`, `railway`, or `forgejo-actions`), an app slug, a
safe branch/ref, and a seed manifest. It copies the seed into the preview bundle
before writing the plan. It does not deploy; it records the future provider
steps (`deploy_ephemeral_preview`, `apply_seed_fixture`, `capture_screenshots`,
`write_preview_bundle`) with `credentials: not minted` and
`deploy: not performed`.

If `walter-repo-config.yaml` is absent or does not declare top-level
`preview_deploy: true`, the plan command exits with a usage error before
writing a plan. This preserves the AD-10 invariant that preview deploys are
opt-in per repo.

`walter-os preview local` writes the same bundle layout as
`walter-os preview bundle`, but records `kind: "preview-report"` and
`provider: "local"` for a loopback preview that is already running. The command
accepts only `localhost`, `127.0.0.1`, or `[::1]` HTTP(S) URLs, requires
`preview_deploy: true`, and records `use_existing_local_preview` instead of
`deploy_ephemeral_preview`. It does not deploy a cloud preview, mint
credentials, or connect to a remote provider.

`walter-os preview static` writes the same report bundle layout, but records
`provider: "local-static"` for an ephemeral loopback server started by the
command. The command requires an already-built static directory, `python3`, an
already-available local Playwright CLI through `npx --no-install`, a seed
manifest, and `preview_deploy: true`. It rejects symlinked static directories,
symlinks inside the static tree, and secret-like file names before starting the
server. Its report records `deploy: "local ephemeral"` to distinguish the local
loopback server from dry-run plans and cloud provider deployments. The server is
bound to `127.0.0.1`, used only for screenshot capture, and shut down before the
command exits.

`walter-os preview verify --pr <number>` validates the evidence under
`.walter/previews/preview-pr-<number>` or the directory passed with `--out`.
If a `preview-report.json` exists, it verifies the report schema, PR number,
HTTP(S) URL, seed and screenshot hashes, and safety invariants. Report safety
allows `deploy: "not performed"` for externally packaged evidence and
`deploy: "local ephemeral"` for `preview static`; credentials must remain
`not minted`. If only a `preview-plan.json` exists, it verifies the dry-run plan
schema, seed hash, and the `deploy: "not performed"` /
`credentials: "not minted"` invariants. The command exits `0` for ready reports
and valid dry-run plans, exits `1` for missing or invalid evidence, and emits
machine-readable JSON with `--json`.

## Acceptance Criteria

- AC1: The command copies the seed manifest and screenshots into the preview
  bundle and writes `preview-report.json`.
- AC2: `--json` emits `pr`, `url`, `bundle_dir`, `seed_manifest`,
  `screenshots`, and `safety`.
- AC3: The default output path is `.walter/previews/preview-pr-<number>` under
  the current repository/directory.
- AC4: Secret-like artifacts and non-HTTP(S) URLs fail closed.
- AC5: `walter-os help` documents the preview bundle and capture commands.
- AC6: `walter-os preview plan --dry-run` writes `preview-plan.json` only when
  `preview_deploy: true` is configured.
- AC7: The plan command refuses to run without `--dry-run`, with unsupported
  providers, or with secret-like seed artifacts.
- AC8: `walter-os preview capture` writes a screenshot artifact for an existing
  HTTP(S) preview URL and refuses unsafe names, missing `npx`, and overwrites.
- AC9: Control Tower reads preview evidence without deploying or minting
  credentials and renders complete, planned, partial, and invalid states.
- AC10: `walter-os preview local` packages a loopback preview as
  `provider: "local"` only when `preview_deploy: true` is configured, and
  rejects non-loopback URLs before writing a report.
- AC11: `walter-os preview verify` validates ready report bundles and dry-run
  plans, rejects missing or tampered evidence, and emits JSON findings.
- AC12: `walter-os preview static` serves an already-built static directory on
  loopback, captures a screenshot, writes `provider: "local-static"` evidence
  with `deploy: "local ephemeral"`, and rejects symlinks or secret-like files in
  the static tree before starting the server.

## Related

- Issue: #235
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-10
- Prior primitive: `docs/specs/pr-score.md` AD-11
