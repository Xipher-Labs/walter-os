# AGENTS.md Cascade as a Vendor-Neutral Standard

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Linear/Plane**: I-05

## Problem

The AGENTS.md cascade mechanism — global → context → repository, with an
optional personal overlay, resolving conflicts as most-specific-wins — is the
most differentiating technical idea in Walter-OS. It is also the most
transferable: the mechanism works regardless of which AI coding tool reads it,
and it solves a genuine coordination problem (consistent agent behavior across
tools and projects).

Currently, the mechanism is documented in three places:
1. The global `AGENTS.md` itself (its own "Context layers" section, lines 35-52)
2. The README "Architecture overview" section
3. `docs/operational/operator-contexts.md`

None of these documents describe the mechanism in vendor-neutral RFC terms.
They all assume the reader is already a Walter-OS adopter. If Anthropic or
OpenAI wanted to standardize a multi-layer agent configuration format,
Walter-OS's cascade design is a credible proposal — but it is buried in a
single operator's framework.

Extracting the cascade specification as a standalone document serves two
purposes:
1. It makes the mechanism accessible to operators who want to implement the
   cascade pattern without adopting the full Walter-OS framework.
2. It creates an artifact that, if the operator chooses to pursue ecosystem
   standardization, is ready to be submitted or shared without modification.

**Realistic note on standards engagement:** Getting Anthropic or OpenAI to
formally adopt a third-party file format convention requires relationship
capital and timing that no document can guarantee. This spec does not claim
that "publishing the cascade spec will make it a standard." It claims that
having a well-written standalone spec is a necessary precondition if the
operator ever wants to pursue that path. External engagement with AI tool
vendors is the operator's work, not this spec's.

## Proposed solution

Write `docs/specs/agents-md-cascade-spec.md` as a standalone, vendor-neutral
specification document. It should be readable without knowing what Walter-OS
is. It defines the cascade format, the resolution rules, the overlay mechanism,
and the conformance criteria for a compliant implementation. The document uses
RFC-style language ("MUST", "SHOULD", "MAY" per RFC 2119) where precision
matters.

Separately, write a minimal conformance test suite that any project claiming
to implement the cascade can run against itself.

## Acceptance Criteria

- [AC-1] `docs/specs/agents-md-cascade-spec.md` exists with the following
  sections:
  - Abstract (3-5 sentences, no Walter-OS branding)
  - Terminology (key terms defined: cascade, layer, context, overlay,
    most-specific-wins, AGENTS.md)
  - Layer definitions (global, context, repository, overlay) with resolution
    rules
  - File discovery rules (how a compliant tool finds and loads each layer)
  - Conflict resolution rules (most-specific-wins; what counts as a conflict)
  - Conformance requirements (MUST/SHOULD/MAY with RFC 2119 language)
  - Open questions (items that would need resolution before formal submission)
- [AC-2] The spec document does not use "Walter-OS" or "Xipher Labs" in the
  normative sections. It MAY reference them in a non-normative "background"
  or "reference implementation" section.
- [AC-3] A conformance test outline `docs/specs/agents-md-cascade-conformance-tests.md`
  exists listing test cases in plain English (not code) that a compliant
  implementation must pass. Minimum 10 test cases covering: layer loading,
  override behavior, overlay precedence, conflict resolution.
- [AC-4] The `README.md` "Architecture overview" section links to the
  standalone cascade spec for readers who want the formal definition.
- [AC-5] `docs/operational/operator-contexts.md` is updated to reference
  the standalone spec as the canonical definition of the cascade mechanism.

## Non-goals

- Submitting the spec to Anthropic, OpenAI, or any standards body. That is
  operator-territory and out of scope for this repo's work.
- Implementing the cascade mechanism in any language other than shell scripts
  (the current Walter-OS implementation is shell-based, and this spec is
  satisfied by the current implementation).
- Getting the spec adopted by any tool. The deliverable is the document.

## Open questions

- Q1: Should the cascade spec include a normative section on the overlay
  mechanism, or describe the overlay as a RECOMMENDED extension? Recommendation:
  RECOMMENDED extension — the core cascade (global/context/repo) is the
  normative part; the overlay is an extension that some implementations will
  not need.
- Q2: Should the spec address how AI tools discover the cascade at all, or
  only how the cascade layers relate to each other? Recommendation: describe
  both, but separate the "how layers relate" (normative) from "how tools
  discover them" (informative, since it is tool-specific).

## References

- `AGENTS.md` lines 35-52 — current cascade documentation (inline)
- `docs/operational/operator-contexts.md` — current cascade operational guide
- RFC 2119 — "Key words for use in RFCs to indicate requirement levels"
- `docs/specs/walter-os-oss-readiness-roadmap.md` — parent roadmap, WS-5
