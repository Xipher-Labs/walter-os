# Preview Environment Bundle

## Problem

AD-10 requires preview environments to give the operator a review surface:
ephemeral per-PR deploy, seed data, screenshots, and a report bundle. Walter-OS
already has PR scoring and post-merge health checks, but it has no standard
artifact format for preview evidence.

## Goals

- Add `walter-os preview bundle` as the first AD-10 primitive.
- Package an existing preview URL, seed manifest, and screenshots into a
  local report bundle with deterministic layout and artifact hashes.
- Reject secret-like artifacts so production secrets are not copied into preview
  evidence.
- Emit JSON for future Control Tower, PR Score, and release automation.

## Non-Goals

- Do not deploy preview environments in this slice.
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

## Acceptance Criteria

- AC1: The command copies the seed manifest and screenshots into the preview
  bundle and writes `preview-report.json`.
- AC2: `--json` emits `pr`, `url`, `bundle_dir`, `seed_manifest`,
  `screenshots`, and `safety`.
- AC3: The default output path is `.walter/previews/preview-pr-<number>` under
  the current repository/directory.
- AC4: Secret-like artifacts and non-HTTP(S) URLs fail closed.
- AC5: `walter-os help` documents the preview bundle command.

## Related

- Issue: #235
- Roadmap: `docs/specs/autonomous-delivery-roadmap.md` AD-10
- Prior primitive: `docs/specs/pr-score.md` AD-11
