# Work Context — Overlay Configuration Prompt

Paste this prompt into any LLM (Claude, GPT-4, Gemini) to get tailored
recommendations for your `~/.config/walter-os/overlay/contexts/work/AGENTS.md`.

---

I am configuring the work context for Walter-OS, an AI agent framework.
The work context AGENTS.md controls how an AI coding agent behaves when I am
working on professional / employer projects. I need you to recommend what to
write in my overlay file based on my answers to the following questions.

1. What is your company name and what does it do (product/service, customer type)?

2. What is your engineering role and team size?

3. What is your primary tech stack?
   - Language(s) and runtime(s):
   - Frontend framework (if any):
   - Database(s):
   - Cloud provider and key services:
   - CI/CD system:
   - Observability stack (logging, metrics, tracing):

4. What is your issue tracker? (Linear / Jira / Plane / GitHub Issues / other)
   What is your ticket format? (e.g., ENG-123, PROJ-456)

5. What is your PR policy?
   - Does your team use auto-merge, or does a human always click merge?
   - Are PRs opened by the agent allowed, or must the engineer open them?
   - How many approvals are required?

6. What are your security requirements?
   - Do you work with sensitive data (PII, HIPAA, PCI)?
   - Are there compliance frameworks you must follow (SOC 2, ISO 27001, etc.)?
   - Are there specific security tools or scanners you run (Snyk, Trivy, etc.)?

7. What domain-specific Walter-OS skills should auto-trigger in your work context?
   (Leave blank if unsure — the LLM will suggest based on your answers above.)

8. Are there any hard limits your company requires that go beyond Walter-OS defaults?
   (e.g., no external LLM APIs for code review, mandatory VPN for all deployments)

---

## Constraints for your recommendations

- The overlay file must be in English.
- Do not include company secrets, passwords, or API keys in the overlay file.
- Keep the overlay focused on agent behavior rules, not project documentation.
- The overlay path is: `~/.config/walter-os/overlay/contexts/work/AGENTS.md`
- The overlay takes precedence over the repo's generic template when present.
- Recommendations should be written as direct instructions to the agent,
  not as questions or suggestions.

Format your output as a complete `AGENTS.md` file ready to paste into the
overlay path.
