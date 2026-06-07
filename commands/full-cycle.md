---
description: Drive a governed idea-to-PR Walter-OS delivery cycle with feature-state, planning, TDD, review, and human gates.
argument-hint: <idea>
---

You are running `/full-cycle <idea>` as the Walter-OS Delivery Orchestrator
entry point.

Idea:

```text
$ARGUMENTS
```

This command coordinates the pipeline described in
`docs/specs/autonomous-delivery-roadmap.md` and
`docs/decisions/0025-delivery-orchestrator-agent.md`. It is an orchestrator
entry, not a safety bypass. The hard-limit floor is non-overridable: do not
merge, deploy to production, push to protected branches, spend money, modify
secrets, weaken hooks, or touch auth/crypto/PHI/destructive paths without the
explicit human gate required by policy.

## Operating Contract

1. If `$ARGUMENTS` is empty or ambiguous, stop and ask for a clearer idea.
2. Classify the task rigor as tiny, small, or major using `AGENTS.md`.
3. Inspect the repo policy if present. Default to Guided Autonomy when the
   policy is missing or unclear.
4. Create or identify a stable feature id and initialize runtime state:

   ```bash
   walter-os feature-state init <feature-id> \
     --title "<short title>" \
     --idea "$ARGUMENTS" \
     --spec docs/specs/<slug>.md
   ```

5. Keep `.walter/features/<feature-id>/state.yaml` as runtime state only. It
   cannot authorize auto-merge, relax approval gates, raise capability tiers, or
   override policy. Validate it before each handoff:

   ```bash
   walter-os feature-state validate
   ```

6. If the feature-state CLI from `docs/specs/feature-state-ledger.md` is not
   available in the current checkout, continue with an explicit note that the
   ledger step is degraded and create a follow-up issue.

## Human Gates

Stop for human approval at these points:

- **Intent gate**: before writing the spec. Summarize the idea, assumptions,
  non-goals, risk, and proposed feature id.
- **Architecture gate**: after brainstorming and before implementation.
  Present the spec, acceptance criteria, key tradeoffs, and verification plan.
- **Merge gate**: after the PR is open and all reviews/checks are clean. The
  operator clicks merge.
- **Production deploy gate**: always human-approved, even in full autonomy.

If a gate result is missing, ambiguous, or contradictory, fail closed and ask.

## Delivery Sequence

1. **Brief**: turn `$ARGUMENTS` into a concise problem statement, non-goals,
   risk notes, and candidate acceptance criteria.
2. **Brainstorm**: run `/brainstorm` to refine scope and surface tradeoffs.
3. **Plan**: run `/write-plan` to produce
   `docs/specs/<slug>.md` and `docs/specs/<slug>.plan.md`.
4. **Semantic checks**: verify spec completeness, AC testability,
   architecture-review coverage, and test relevance. Use the repo's semantic
   gate tooling when available; otherwise document the manual check in the
   feature ledger.
5. **Implement**: run `/execute-plan` task by task under RED-GREEN-REFACTOR.
6. **Verify**: run the plan's verification commands, the relevant lint/type
   checks, and `walter-os feature-state validate`.
7. **Review**: request reviewer subagent review, Copilot review, and the
   configured cross-model review round required by `commands/pr.md`.
8. **PR**: run `/pr <spec-slug>` only after verification evidence exists.
9. **Stop**: report the PR URL, checks, review status, ledger path, and any
   deferred issues. Do not merge or production deploy.

## Output

Keep the operator updated with:

- feature id and ledger path
- current phase
- gate status
- files changed
- verification evidence
- PR URL and outstanding review/check items
