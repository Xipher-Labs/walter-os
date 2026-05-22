# MCP Money-Spending Guardrails — Draft RFC

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-07

## Problem

The MCP (Model Context Protocol) ecosystem is growing rapidly. AI coding
tools and agent frameworks now routinely wire LLMs to MCP servers that can
provision cloud infrastructure, process payments, and manage production
deployments. The current MCP specification does not define a standard way to
signal that a server can spend money, require pre-action cost disclosure, or
enforce per-action confirmation gates.

Walter-OS has solved this problem for its own MCP catalog: `mcp/servers.json`
uses a `"money": true` tag to mark money-spending servers, and the global
`AGENTS.md` defines six behavioral guardrails that any agent operating in
Walter-OS must follow before taking a money-spending action.

Those guardrails (documented in `AGENTS.md` lines 425-450) are:
1. Read before write — default to read-only operations.
2. Show the bill — print expected cost delta in human-readable form before
   any state-changing action.
3. One action per confirmation — each resource requires individual confirmation.
4. Stop on partial state — if a multi-step sequence fails midway, stop and
   report, do not auto-retry or auto-clean.
5. Never schedule destructive ops — destruction is always interactive.
6. Tokens scoped — use read-only tokens by default; mint write-scoped tokens
   only when actively provisioning.

This spec formalizes these guardrails as a vendor-neutral draft RFC suitable
for sharing with the MCP community. It does NOT submit the RFC anywhere —
that is operator-territory.

## Proposed solution

Write `docs/specs/mcp-money-spending-guardrails-rfc.md` as a standalone
vendor-neutral document. The document should be readable without knowing what
Walter-OS is, propose a minimal schema extension to the MCP server manifest,
and define the agent behavioral requirements for each guardrail.

**Realistic scope note:** This document is a starting point for community
discussion, not a complete protocol specification. The MCP ecosystem's current
standardization process (via the MCP spec at modelcontextprotocol.io) is
the appropriate venue for any formal adoption. Walter-OS can publish this as a
blog post, GitHub discussion, or Discord proposal to generate feedback.

## RFC outline (the content of the RFC document)

### Section 1: Abstract

MCP servers that can initiate irreversible financial actions (cloud provisioning,
payment processing, resource destruction) pose a distinct risk class that the
current MCP specification does not address. This document proposes a minimal
`money` capability annotation in MCP server manifests and six agent behavioral
requirements that any client SHOULD enforce when operating money-capable servers.

### Section 2: Motivation

[Describe the risk: an agent that can provision cloud VMs can spend thousands
of dollars before the operator notices. Current MCP servers have no standard
way to declare this risk or to require per-action confirmation.]

### Section 3: Proposed manifest annotation

Extend the MCP server manifest (JSON/YAML) with an optional `capabilities`
object:

```json
{
  "capabilities": {
    "money": {
      "risk": "high",
      "description": "Can provision cloud resources; actions incur cost.",
      "currency": "EUR",
      "cost_display_required": true
    }
  }
}
```

When `capabilities.money` is present, a compliant MCP client MUST enforce the
behavioral requirements in Section 4.

### Section 4: Agent behavioral requirements

For any server with `capabilities.money` set, the agent:

1. **MUST** default to read-only operations (list, describe, get).
   Write operations (create, modify, destroy) MUST require explicit per-action
   confirmation in the current conversation.

2. **MUST** display the expected cost impact before any state-changing action.
   The display MUST be human-readable ("Provisioning CPX41: €25.20/mo") and
   MUST appear before the action is taken, not after.

3. **MUST NOT** batch confirmations. Operator confirming Action A does not
   authorize Action B, even in the same sequence.

4. **MUST** stop on partial state. If a multi-step sequence fails after some
   resources are created, the agent MUST stop, report the current state to
   the operator, and NOT attempt auto-retry or auto-cleanup.

5. **MUST NOT** schedule destructive operations for future execution. Resource
   deletion MUST be confirmed interactively at the time of deletion.

6. **SHOULD** use read-only credentials by default. Write-scoped credentials
   SHOULD be requested only for the duration of the provisioning session and
   revoked afterward.

### Section 5: Conformance

An MCP client is conformant if it enforces all MUST requirements for
`money`-capable servers. A server is conformant if it declares `capabilities.money`
when it can initiate irreversible financial actions.

### Section 6: Open questions

- Should `money` be a boolean or a structured object (as proposed)?
- Should the `currency` field be required or optional?
- Is `cost_display_required` the right mechanism, or should it be a MUST
  requirement in the behavioral section?
- Should there be a `money.max_per_action` field that the agent uses to
  auto-block requests above a threshold?
- Who maintains the list of known money-capable MCP servers?

### Section 7: Reference implementation

Walter-OS implements this pattern in `mcp/servers.json` (`"money": true` tag)
and `AGENTS.md` (the six behavioral guardrails). The implementation is
available at https://github.com/xipher-labs/walter-os.

## Acceptance Criteria

- [AC-1] `docs/specs/mcp-money-spending-guardrails-rfc.md` exists as a
  standalone document following the outline in this spec. It uses RFC 2119
  language for the behavioral requirements.
- [AC-2] The RFC document does not require Walter-OS knowledge to understand.
  The Walter-OS reference implementation is mentioned in Section 7 only.
- [AC-3] The RFC document is reviewed for technical accuracy against the
  current Walter-OS implementation in `mcp/servers.json` and `AGENTS.md`.
  Any discrepancy between the RFC text and the implementation is resolved
  by updating the implementation to match the RFC (the RFC is the canonical
  intent).
- [AC-4] `mcp/servers.json` is updated (if needed) to use the proposed
  structured `capabilities.money` object format instead of the current boolean
  `"money": true`. This aligns the implementation with the RFC proposal.

## Non-goals

- Submitting the RFC to modelcontextprotocol.io or any standards body.
- Implementing a new MCP client enforcement mechanism beyond what AGENTS.md
  already documents.
- Covering non-financial destructive operations (e.g., deleting data without
  cost). That is a separate concern.

## Open questions

- Q1: Should the RFC propose a machine-readable cost estimate interface
  (where the MCP server returns an estimated cost before the action runs),
  or leave cost display entirely to the agent? Recommendation: leave cost
  display to the agent for now — requiring MCP servers to implement a cost
  API is a larger protocol change that should be a separate proposal.

## References

- `AGENTS.md` lines 425-450 — the current six guardrails
- `mcp/servers.json` — the current `"money": true` implementation
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-7
- https://modelcontextprotocol.io — the MCP specification
