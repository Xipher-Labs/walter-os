---
name: vercel-agent-skills-bridge
description: How Walter-OS imports Vercel's official agent-skills (vercel-labs/agent-skills) where they make sense. NOT a wholesale fork — selective integration, since Walter-OS already has overlapping skills. Use this skill when the user mentions "vercel agent-skills", "react best practices skill", "deploy-to-vercel skill", or you need to evaluate adding a Vercel skill to Walter-OS.
---

# Vercel agent-skills bridge

[vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills)
is Vercel's official collection (~26k stars, no license currently —
keep an eye on this). They publish skills as both `.zip` (Anthropic
plugin format) and source directories.

Walter-OS doesn't blindly import everything. Some overlap, some don't fit.

## Current vetted pin

- Submodule: `external/vercel-agent-skills`
- Previous pin: `ce3e64e468f8fa09a2d075d102771838061fdac0`
- Current vetted pin: `4ec6f84b61cd3c931046c3e6e398f3ae7de372f7`
- Delta reviewed for #223: 26 upstream commits, including the new
  `vercel-optimize` and `writing-guidelines` upstream directories.
- Hook baseline impact: no files under a `hooks/` path changed in this
  upstream delta, so `walter-os baseline-external-hooks` is not required for
  this refresh.

## Vercel skills inventory + Walter-OS decision

| Vercel skill | Walter-OS decision | Why |
|---|---|---|
| `composition-patterns` | **Reference, don't install** | General React composition advice. Useful as reading material; not skill-grade actionable for Walter-OS workflow. |
| `deploy-to-vercel` | **Install + complement to skills/vercel-cli/** | Vercel's own deploy guide. Pairs with our CLI skill. |
| `react-best-practices` | **Install** | Useful for [Project A] (Next.js) + future projects. Vercel's curated React pitfalls. |
| `react-native-skills` | **Install for [Project B] context** | RN expertise; [Project B] frontend. Load only under context=projects-personal. |
| `react-view-transitions` | **Skip** | Niche; install per-project as needed, not globally. |
| `vercel-cli-with-tokens` | **Already covered** by skills/vercel-cli/ | Walter-OS version is more operator-specific. |
| `vercel-optimize` | **Evaluate manually; don't install globally yet** | High operational surface: Vercel CLI v53+, linked project context, usage/metrics/contract reads, Observability Plus assumptions, and many local `.mjs` helper scripts. Useful for Vercel cost/performance audits, but should be opt-in per project after a dedicated safety review. |
| `web-design-guidelines` | **Reference, don't install** | Overlaps with skills/brand-creation + skills/frontend-quality. |
| `writing-guidelines` | **Reference, don't install globally yet** | Vercel-specific writing handbook checker that fetches a live remote guideline URL before each review. Useful for Vercel-style docs/prose audits, but overlaps with Walter-OS content/readme skills and should stay opt-in until the source/licensing and network-fetch behavior are reviewed. |

## Latest upstream delta (#223)

The `ce3e64e` → `4ec6f84` refresh adds:

- `vercel-optimize`: a large cost/performance optimization workflow with
  metric collection, code scanners, report rendering, and extensive test
  fixtures under `packages/vercel-optimize-tests`.
- `writing-guidelines`: a compact prose-review upstream entry that loads Vercel's
  writing handbook from a raw GitHub URL.
- Updates to `react-best-practices`, `react-view-transitions`, and
  `vercel-cli-with-tokens`.
- Repository-level upstream metadata (`skills.sh.json`) and README/AGENTS
  updates.

This refresh intentionally does **not** add new symlinks under `skills/`.
Adding a symlink makes the skill part of Walter-OS's discoverable skill
surface and should be done in a follow-up PR with trigger-format checks,
license/network review, and project-specific loading guidance.

## Installation pattern

For "Install" decisions:

```bash
# One-time: clone Vercel skills as a git submodule for tracked updates
cd /path/to/walter-os
git submodule add https://github.com/vercel-labs/agent-skills.git \
  external/vercel-agent-skills

# Symlink the chosen skills into walter-os/skills/
ln -s ../../external/vercel-agent-skills/skills/deploy-to-vercel \
  skills/deploy-to-vercel
ln -s ../../external/vercel-agent-skills/skills/react-best-practices \
  skills/react-best-practices
ln -s ../../external/vercel-agent-skills/skills/react-native-skills \
  skills/react-native-skills

# install.sh picks them up like any other skill (symlinks → ~/.claude/skills/)
./install.sh --upgrade
```

## License caveat

vercel-labs/agent-skills has no SPDX license declared (as of 2026-05).
Two interpretations:
- Permissive (Vercel intends free use)
- Restricted (no license = all-rights-reserved by default in many jurisdictions)

For Walter-OS: **fork as submodule** (preserves attribution + git
history), **don't redistribute**. This is consistent with personal/
operator-only use. If the project later picks an explicit license,
re-evaluate.

## Update cadence

- Renovate doesn't track git submodules by default. Configure manually:
  ```json
  {
    "git-submodules": {
      "enabled": true,
      "schedule": ["before 6am on monday"]
    }
  }
  ```
- Quarterly: review Vercel skills changelog, decide if any new skills
  should join Walter-OS catalog.

## What this skill does NOT do

- Auto-import all Vercel skills (selective is better)
- Override Walter-OS's existing skills (vercel-cli, frontend-quality,
  brand-creation stay primary; Vercel skills complement)
- Use Vercel skills for non-Vercel deploys (Walter-VM, Hetzner-direct,
  Railway have their own skill paths)

## References

- [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills)
- [Vercel blog](https://vercel.com/blog) (Vercel announcements re: skills)
