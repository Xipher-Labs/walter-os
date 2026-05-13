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

## Vercel skills inventory + Walter-OS decision

| Vercel skill | Walter-OS decision | Why |
|---|---|---|
| `composition-patterns` | **Reference, don't install** | General React composition advice. Useful as reading material; not skill-grade actionable for Walter-OS workflow. |
| `deploy-to-vercel` | **Install + complement to skills/vercel-cli/** | Vercel's own deploy guide. Pairs with our CLI skill. |
| `react-best-practices` | **Install** | Useful for [Project A] (Next.js) + future projects. Vercel's curated React pitfalls. |
| `react-native-skills` | **Install for [Project B] context** | RN expertise; [Project B] frontend. Load only under context=projects-personal. |
| `react-view-transitions` | **Skip** | Niche; install per-project as needed, not globally. |
| `vercel-cli-with-tokens` | **Already covered** by skills/vercel-cli/ | Walter-OS version is more operator-specific. |
| `web-design-guidelines` | **Reference, don't install** | Overlaps with skills/brand-creation + skills/frontend-quality. |

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

- https://github.com/vercel-labs/agent-skills
- https://vercel.com/blog (Vercel announcements re: skills)
