# Control Tower Team Readiness Plan

## Task 1 — Add Readiness Data Contract

- File: `apps/control-tower/lib/operator-readiness.ts`
- Define the three operating modes: solo, second-device, teammate.
- Define the three safe checks: service health, post-merge, model/tool
  readiness.
- Keep commands read-only and limited to commands available on `main`.
- Verification: unit test asserts IDs, commands, and doc paths.

## Task 2 — Render Dashboard Panel

- File: `apps/control-tower/app/components/OperatorReadiness.tsx`
- Render a dense panel with separate "Operating path" and "Safe checks"
  sections.
- Link docs via `NEXT_PUBLIC_WALTER_REPO_URL` when configured; otherwise show
  repo-relative doc paths without hardcoded GitHub ownership.
- Use existing `Panel`, `SectionTitle`, and `StatusBadge` primitives.
- Verification: lint/typecheck and static unit test for dashboard wiring.

## Task 3 — Wire Overview Page

- File: `apps/control-tower/app/page.tsx`
- Add `OperatorReadiness` as a full-width dashboard band between the agent board
  and health/spend surfaces.
- Verification: unit test checks the overview imports/renders the panel.

## Task 4 — Document Scope

- Files:
  - `docs/specs/control-tower-team-readiness.md`
  - `docs/specs/README.md`
  - `CHANGELOG.md`
- Document the read-only first slice and explicitly exclude release doctor until
  #307 merges.
- Verification: markdownlint and cross-reference lint pass.

## Task 5 — Final Verification

- Run:
  - `pnpm --dir apps/control-tower test:unit -- operator-readiness.test.ts`
  - `pnpm --dir apps/control-tower typecheck`
  - `pnpm --dir apps/control-tower lint`
  - `npx --yes markdownlint-cli --config .markdownlint.json docs/specs/control-tower-team-readiness.md docs/specs/control-tower-team-readiness.plan.md docs/specs/README.md CHANGELOG.md`
  - `./tests/lint-cross-references.sh`
  - `git diff --check`
