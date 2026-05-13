# AGENTS.md — Hackathons Context

<!-- -----------------------------------------------------------------------
  CONTEXT TRIGGER: Set WALTER_CONTEXT=hackathons in your shell or in the
  project's .env.local before starting a hackathon session. Hackathon
  projects can live under any directory; the env-var trigger avoids
  conflicts with path-based contexts (work/, projects-personal/).

  This context is designed for time-boxed competitive events (typically
  24–72h). It trades long-term maintenance quality for delivery speed.
  Revert to work/ or projects-personal/ after the event ends.
  ----------------------------------------------------------------------- -->

Loaded when `WALTER_CONTEXT=hackathons` is set in the environment.

## Mode

High autonomy. Time-pressure-driven. The agent acts with minimal
confirmation overhead.

- Agent may open PRs, create branches, make toolchain choices, and push
  to the main branch without per-action confirmation.
- Operator reviews at demo checkpoints (hours 6, 18, 36), not every commit.
- Speed and demo-ability beat code quality. Shortcuts are acceptable on
  feature branches; the main branch is the submission artifact.

Hard limits still apply — see the Hard limits section below.

## 48h sprint discipline

Time is the only non-renewable resource at a hackathon. Use this schedule:

| Hours | Phase | Focus |
|---|---|---|
| 0–6 | Ideation lock | Commit to one core demo loop. No feature creep after hour 6. |
| 6–18 | Core implementation | One vertical slice judges can see working end-to-end. |
| 18–36 | Polish + secondary features | Only if core loop is fully green. |
| 36–44 | Demo prep | Recording, slides, pitch narrative. |
| 44–48 | Buffer | Bug fixes only. No new features. |

The ideation lock at hour 6 is non-negotiable. If you have not committed to
a single core loop by hour 6, drop the weakest ideas and lock the strongest.

## Demo-first delivery

Every feature must be visible in the 2-minute demo before it counts as done.

A feature that works but cannot be shown to judges in the demo window is
**out of scope**. Cut it before it consumes more time.

Demo checklist (before any feature is considered complete):
- [ ] Can be shown live in the demo without setup steps visible to judges.
- [ ] The happy path works 3 times in a row without a fatal error.
- [ ] Failure modes degrade gracefully (no blank screens, no stack traces).

## Branch flow

Trunk-based. Single `main` branch. Short-lived feature branches merged
within the same work session. No staging environment unless the judging
criteria specifically require it.

Submission tagging:
- Tag the final commit: `hackathon/<event-slug>/submission`
- Example: `hackathon/ethglobal-prague-2026/submission`

## Judging rubric awareness

Common scoring dimensions across hackathons. Identify the weights for your
specific event and prioritize accordingly:

| Dimension | What judges look for | Optimization tip |
|---|---|---|
| Technical depth | Novel use of API/technology | Depth over breadth; one impressive integration beats five shallow ones |
| UX/Design | Working UI beats a slide mockup | Figma mockup is a backup, not a deliverable |
| Business viability | One-sentence monetization path | Judges do not need a full business plan |
| Impact / theme fit | Explicit connection to the event theme | State it in the first 30 seconds of the demo |

Ask the organizers for the official judging rubric weights before hour 6
ideation lock. Optimize for what they measure.

## Research patterns

Run these in the first 4 hours to inform your ideation:

1. **Theme analysis**: parse the hackathon brief, extract judging criteria
   weights, identify the 2–3 criteria with the highest weight.

2. **API inventory**: list every sponsor API and SDK available. Rate each by:
   integration complexity (low / med / high) × uniqueness of use-case.
   Pick the intersection of low complexity and high uniqueness.

3. **Competitor scan**: search DevPost or Taikai for prior-year winners in
   the same track. Identify what they did and how to differentiate.

4. **Stack selection**: choose the stack you can move fastest in, not the
   most technically impressive one. Speed beats novelty in the first 6 hours.

## Post-hackathon cleanup

After the event, before returning to normal development discipline:

1. Tag the submission commit: `hackathon/<event-slug>/submission`
2. Archive or delete all WIP branches from the event.
3. If the project continues, migrate it to `projects-personal/` context:
   - Reset `WALTER_CONTEXT` (remove or change the env var).
   - Run `walter-os doctor` to re-apply normal discipline rules.
   - Create a spec at `docs/specs/<slug>.md` for any continued features.
4. If the project is not continuing, archive the repo and close issues.

## Hard limits

Even under time pressure, these rules are absolute:

- Never commit secrets (API keys, tokens, passwords, `.env` files).
- Never push directly to a public repo's default branch without at least a
  1-minute self-review of the diff.
- Never spend real money on API calls without checking the free tier first.
  Most sponsor APIs have generous hackathon-specific free tiers.
- Never send PHI or private user data to any external service.
- Never use another team's code or model without attribution.

## Skill auto-trigger

See `contexts/hackathons/SKILLS.md` for the full skill mapping table.
Key skills in this context:

- `hackathon-spinup` — session start (auto)
- `brainstorming` — ideation phase, hours 0–6 (auto)
- `writing-plans` — architecture decision (auto)
- `brand-creation` — branding sprint (opt-in)
- `landing-page-fast` — landing page needed (opt-in)
- `verification-before-completion` — before demo submission (auto)
- `web-security-baseline` — user-facing projects (opt-in)

## Customization

This context is designed to be used as-is for most hackathons. To override:

1. Run `setup/personal-overlay-init.sh` to scaffold the overlay.
2. Edit `~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md`.
3. Use `contexts/hackathons/PROMPT.md` for LLM-guided recommendations.

What to customize:
- Preferred hackathon stack (your fastest-moving tools)
- Default sponsor API integrations you use often
- Team size and coordination rules
- Event-specific autonomy adjustments (some events have stricter rules)
