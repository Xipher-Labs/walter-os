# 0011. Depersonalization Strategy — Dual-Layer Overlay

**Date**: 2026-05-11
**Status**: Proposed

## Context

Walter-OS has personal references embedded in the OSS core: a specific domain
(`${WALTER_DOMAIN}`), operator-specific context files ([Company], [Project A], [Project B]),
and Argentine regulatory content. These must be removed from the OSS core before
v0.2.0 without losing the content itself (which is valuable as examples and is
the operator's active configuration).

Three architectural approaches were considered:

**A — Dual-layer overlay**: the OSS repo ships generic templates; operator-specific
content lives in a personal overlay directory (`~/.config/walter-os/overlay/`)
outside the repo. The overlay takes precedence in the AGENTS.md cascade when
present. Personal content preserved as `contexts/_examples/` labeled examples
in-repo. New operators get working generics immediately.

**B — Single-repo + gitignore**: personal context files are gitignored (or in a
gitignored subdirectory). The operator commits their personal files locally but
they never push. A template is committed; the real file is gitignored.

**C — Env-substitution only**: no separate overlay, no gitignore. All personal
references replaced with `${VAR}` placeholders. Personal data is only ever in
env vars (`.env.local`, gitignored). AGENTS.md loads values from env vars at
read-time.

The decision has downstream effects on how W-5 (depersonalization), W-6
(install wizard step 3), and the operator's upgrade experience are designed.

## Decision

Use **Approach A — Dual-layer overlay**.

The personal overlay lives at `~/.config/walter-os/overlay/` (outside the repo).
The AGENTS.md cascade explicitly checks for overlay files before loading repo
templates:

```
Cascade order (most-specific-wins):
  1. ~/.config/walter-os/overlay/contexts/<context>/AGENTS.md  (operator personal)
  2. <repo>/contexts/<context>/AGENTS.md                        (OSS generic template)
  3. <repo>/AGENTS.md                                           (global)
```

The OSS repo ships:
- `contexts/work/AGENTS.md` — generic work context template
- `contexts/projects-personal/AGENTS.md` — generic projects-personal template
- `contexts/personal/AGENTS.md` — generic personal context template
- `contexts/_examples/` — labeled examples with generic persona configs

`setup/personal-overlay-init.sh` scaffolds the overlay directory and copies
the templates as starting points. The operator fills in their details.

Domain references (`${WALTER_DOMAIN}`) are replaced with `${WALTER_DOMAIN}` in all
compose files and env templates. `WALTER_DOMAIN` is one of the 5 required bootstrap
vars and is always set in `.env.local`.

## Consequences

**Easier:**
- New operators get a working Walter-OS with generic templates immediately, with
  no personal content to remove.
- Existing operators can migrate personal content to the overlay at their
  own pace; nothing breaks during the transition.
- The overlay is independent of git — no risk of accidentally committing personal
  content to the OSS repo.
- The examples in `contexts/_examples/` serve as documentation for how to fill
  in the overlay.
- `walter-os sync --upgrade` updates the OSS core without touching the overlay.
- Other operators can share their overlays (as private repos or gists) without
  touching the Walter-OS OSS repo.

**Harder:**
- The operator must maintain a separate overlay directory alongside the repo.
  `walter-os sync` must be taught to check that the overlay is still compatible
  after an upgrade (i.e., a new capability in the template is not in the overlay).
- The AGENTS.md cascade documentation must be updated to describe the overlay
  layer. Without clear docs, users will not know where to put their
  customizations.
- `doctor` must check that overlay files are not stale (reference skills or
  patterns that no longer exist in the OSS core).

**Risks accepted:**
- Overlay drift: over time, the operator's overlay may reference skills or
  patterns that the OSS core has evolved away from. Mitigation: `walter doctor`
  includes a check that overlay skill references resolve to existing `skills/`
  directories. This is a best-effort check, not a blocker.

## Alternatives considered

**B — Single-repo + gitignore:**
- Pro: No separate directory to manage. All content in one place.
- Con: Git status is noisy (`contexts/work/AGENTS.md: ignored`). Operators
  working on multiple machines must copy the gitignored files manually. Forks
  silently drop the personal content (it was never committed). If the operator
  accidentally removes a file from `.gitignore`, personal content is at risk
  of being committed. The "gitignore the real file, commit a template" pattern
  is fragile — any git tool (IDE, GitHub Desktop) that auto-stages new files
  can silently commit the wrong thing.
- Rejected: The overlay approach has cleaner separation and better upgrade
  semantics.

**C — Env-substitution only:**
- Pro: Purely env-var-driven, no separate directory, no cascade mechanism.
  Maximum simplicity.
- Con: AGENTS.md is a markdown file read by humans and LLMs. Embedding
  `${OPERATOR_COMPANY}` in a markdown file that is used as a system prompt
  creates visual noise and requires an `envsubst` step before loading — which
  means the LLM always sees a pre-processed file, not the one in the repo.
  Context files (work, projects-personal, personal) contain paragraphs of
  descriptive text, not just configuration values. Env vars work for domain
  names and boolean flags, not for descriptive prose.
- Rejected: AGENTS.md context files are prose, not config templates. The overlay
  approach is the right abstraction for prose content.
