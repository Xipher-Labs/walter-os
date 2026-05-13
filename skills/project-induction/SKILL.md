---
name: project-induction
description: Run a guided induction interview with the operator to establish a new project's context, constraints, and success criteria. Generates a bootstrap spec, a project-level AGENTS.md, and a Plane epic with initial tasks. Use this skill when starting a new project or when the operator invokes 'walter-os new project <type> <name>'.
---

# Skill: project-induction

**Trigger**: Invoked when `walter-os new project <type> <name>` is called,
or directly via `skills/project-induction/scripts/induction.sh`.

**Purpose**: Runs a guided induction interview with the operator to establish
a new project's context, constraints, and success criteria. Generates a
bootstrap spec, a project-level `AGENTS.md`, and a Plane epic with initial tasks.

---

## Inputs

| Field | Source | Required |
|---|---|---|
| `project_name` | CLI arg or interview | yes |
| `project_type` | CLI arg (`webapp\|service\|solana\|hackathon\|personal`) | yes |
| `description` | Interview question 1 | yes |
| `stack` | Interview question 2 (with type-specific defaults) | yes |
| `non_negotiable_rules` | Interview question 3 (compliance, perf, etc.) | no |
| `critical_integrations` | Interview question 4 (DB, APIs, 3rd party) | no |
| `success_kpis` | Interview question 5 | no |
| `phi_data` | Interview question — "Does this project handle medical/health data?" | no |
| `financial_data` | Interview question — "Does this project handle payments?" | no |

**Non-interactive mode**: all inputs may be supplied via a YAML file
(`--answers-file <path>`), enabling scripted and test invocations.

---

## Outputs

1. **Project charter** (`docs/specs/<project-name>-bootstrap.md`): problem
   statement, decisions, acceptance criteria for the bootstrap phase, non-goals.
   Written to `--output-dir` if specified, otherwise to `docs/specs/`.

2. **Project AGENTS.md** (written to `--output-dir/AGENTS.md` or `./AGENTS.md`
   in the project root): local agent contract with rules derived from the
   interview. If `phi_data: true`, includes the `medical-data-compliance` skill
   and the PHI hard rules. If `financial_data: true`, includes a TODO block
   for a pending financial-data-compliance skill (deferred backlog) with manual PCI-DSS guidance.

3. **Plane epic** (created via `plane_issue_create`): main bootstrap epic with
   5 tasks: Setup CI pipeline, Initial test infrastructure, First feature skeleton,
   Setup local dev environment, Write README + getting started guide.
   Skipped if `--skip-plane` flag is set (for offline/test use).

---

## Interview flow (interactive mode)

The 7-9 structured questions (5 core + 2 compliance + optional type-specific):

```
Q1: What does this project do? (free-form, 1-3 sentences)
Q2: What stack will you use? [default based on type]
Q3: Any non-negotiable rules? (compliance, performance, legal)
Q4: Critical integrations? (external services, APIs, databases)
Q5: How will you know this project succeeded? (KPIs / goals)
Q6: Does this project handle medical or health data? (yes/no)
Q7: Does this project handle financial transactions? (yes/no)
```

Defaults per type:
- `webapp`:    Next.js 15 + Supabase + Vercel + Tailwind
- `service`:   Node.js/Rust + Postgres + Docker
- `solana`:    Anchor + TypeScript SDK + solana-test-validator
- `hackathon`: Next.js 15 + Supabase (quick-start defaults)
- `personal`:  Obsidian + local scripts

---

## Dependencies

- `scripts/agents/lib/plane.sh` — for `plane_issue_create`
- `scripts/agents/lib/llm.sh` — for generating charter/AGENTS.md content
- `PLANE_API_TOKEN`, `PLANE_API_URL`, `PLANE_WORKSPACE`, `PLANE_PROJECT` env vars
  (not required when `--skip-plane` is set)

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Bad arguments (invalid type, missing name) |
| 3 | Dependency missing (plane.sh not found, jq not available) |
| 4 | LLM invocation failed |

---

## Non-goals

- Full project scaffolding (file generation, repo init) — that's a separate skill.
- Auto-pushing to remote or creating GitHub repos — operator action.
- Running the CI setup — the generated Plane tasks cover that.

---

## Related

- `docs/specs/walter-council-v2.md` — Improvement 6 (T-23, T-24)
- `bin/walter-os` — canonical entry point: `bin/walter-os new project <type> <name>`.
  `bin/walter` is an alias; when in doubt, use `bin/walter-os`.
