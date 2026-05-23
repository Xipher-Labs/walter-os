# AGENTS.md Cascade — Vendor-Neutral Specification

**Status**: Draft v0.1
**Owners**: Xipher Labs S.R.L. (originating implementation)
**Created**: 2026-05-22
**Implementation reference**: <https://github.com/Xipher-Labs/walter-os>

> This is a **standalone, vendor-neutral specification** of the AGENTS.md
> cascade mechanism. It is intentionally readable without prior knowledge of
> Walter-OS. The Walter-OS framework is one implementation; the cascade
> itself is a generic pattern that any AI-coding-tool author can adopt or
> any project can use independently.
>
> Conformance criteria (Section 6) define what makes an implementation
> compliant. A reference test suite is provided as
> `tests/oss/agents-md-cascade-conformance.bats` in the Walter-OS repository.

---

## Abstract

The AGENTS.md cascade defines a three-layer, file-based mechanism for
configuring AI coding agents (Claude Code, Cursor, Codex CLI,
Antigravity v1.20.3+, and similar tools that already read a
project-root `AGENTS.md` file). The mechanism
addresses a real coordination problem: an operator working across several
projects, each with its own conventions, plus a personal style that should
apply everywhere, currently has no standard way to express "this rule
applies globally, this one applies only in client work, this one applies
only in this specific repo." The cascade is the missing layer.

Conflict resolution is **most-specific-wins**: a repository-level rule
overrides a context-level rule overrides a global rule. A separate
**personal overlay** mechanism lets the operator carry private
customizations out-of-tree so the repository's AGENTS.md stays clean.

This spec does NOT mandate which file format `AGENTS.md` itself uses
beyond it being a single Markdown file with addressable sections. The
cascade is an orthogonal layering mechanism on top of any existing
`AGENTS.md` convention.

---

## 1. Terminology

- **AGENTS.md** — A Markdown file that an AI coding tool reads to learn
  how to behave in a given directory. The file is the configuration
  artifact this spec layers on.

- **Layer** — A position in the resolution chain. This spec defines
  three layers: *global*, *context*, *repository*.

- **Cascade** — The act of reading every applicable AGENTS.md from the
  most-general layer to the most-specific layer, in order. The agent
  treats the concatenated content as a single contract.

- **Context** — A named directory pattern (e.g., `~/work/*`, `~/Projects-Personal/*`)
  that selects an intermediate AGENTS.md to apply.

- **Overlay** — An out-of-tree directory where an operator stores
  personal customizations that the cascade reads at the appropriate
  layer without committing them to any repository.

- **Conflict resolution** — The rule that determines which value wins
  when two layers specify the same item. This spec mandates
  **most-specific-wins**.

- **Compliant implementation** — An AI coding tool, framework, or library
  that implements the cascade according to Sections 2–5 of this spec.

The keywords MUST, MUST NOT, SHOULD, SHOULD NOT, MAY are to be
interpreted as described in [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119)
when, and only when, they appear in all capitals.

---

## 2. Layer definitions

The cascade has exactly three layers, resolved in order from
most-general to most-specific:

### 2.1 Layer 1 — Global

The global layer is the framework-level contract. It contains rules that
apply to every project the operator works on, regardless of context.

- A compliant implementation MUST define a canonical absolute path for
  the global AGENTS.md (e.g., `~/walter-os/AGENTS.md` in the reference
  implementation, or an analogous fixed location).
- The global AGENTS.md MUST exist for the cascade to function. If
  absent, the implementation MUST surface a clear error to the operator.
- The global AGENTS.md SHOULD be vendor- and operator-neutral so it can
  be safely committed to a public repository. Operator-personal
  customization lives in the overlay (Section 4), not here.

### 2.2 Layer 2 — Context

The context layer is the operator's "shape of work" customization. Common
contexts include `work` (employer/client code), `projects-personal` (the
operator's own software projects), and `personal` (non-code: notes,
finance, journaling).

- A compliant implementation MUST support **at least one** context, and
  SHOULD support multiple contexts.
- Context selection MUST be derivable from one of:
  - The current working directory matching a pre-configured pattern
    (e.g., `cwd` is under `~/work/*` selects the `work` context).
  - An explicit environment variable (e.g., `WALTER_CONTEXT=hackathons`)
    that overrides directory-based selection.
- A compliant implementation MUST document its context-resolution rules
  and the precedence between cwd-matching and explicit override.

### 2.3 Layer 3 — Repository

The repository layer is the project-specific contract. It lives in
`AGENTS.md` at the repository root.

- A compliant implementation MUST locate the repository AGENTS.md by
  walking up from the current working directory until it finds an
  AGENTS.md at the repository root (or a marker like `.git/`).
- The repository AGENTS.md SHOULD be committed to the repository so all
  contributors share the same rules. Operator-personal additions belong
  in the overlay, not here.

---

## 3. Conflict resolution

Most-specific-wins. Formally:

For any rule R that can be expressed at multiple layers:
1. If layer 3 (repository) specifies R, the repository's value is used.
2. Else if layer 2 (context) specifies R, the context's value is used.
3. Else if layer 1 (global) specifies R, the global's value is used.
4. Else R is undefined; the implementation MUST behave as if R were not
   set at any layer.

**Concatenation rule:** unless the operator declares an explicit
override, the implementation MUST concatenate non-conflicting rules
across layers. A rule is "conflicting" only when two layers specify
incompatible values for the same item (e.g., both define a
`WALTER_BRANCH_FLOW` value). Two layers each adding entries to a list
are not conflicting; the implementation MUST union the lists.

**Distinguishing override from addition:** the implementation SHOULD
provide an explicit syntax for overriding a parent layer's value (e.g.,
`> Override: ...` callout in Markdown, or a structured frontmatter
block). Without such syntax, the default is concatenation.

---

## 4. Personal overlay

The personal overlay lets an operator carry private customizations
across machines and projects without committing them to any repository.

- A compliant implementation MUST support an overlay at a documented
  out-of-tree location (e.g., `~/.config/walter-os/overlay/`).
- The overlay MUST be applied at the context layer (Layer 2). It MAY
  also extend Layer 1 or Layer 3, but Layer 2 is the canonical
  insertion point because that's where operator-personal customization
  belongs.
- The overlay's contents SHALL NOT be committed to the public repository.
- A compliant implementation MUST provide a documented mechanism to
  scaffold the overlay (e.g., `setup/personal-overlay-init.sh` or
  equivalent), starting from generic templates so a new operator can
  bootstrap without manual file copying.

---

## 5. Environment variables

A compliant implementation MUST recognize at least the following
environment variables. Implementations MAY add their own, but the
following two are part of the cascade specification:

### 5.1 `WALTER_BRANCH_FLOW`

Selects a branch-flow policy that applies repository-wide. Valid values:

- `single-tier` — feature/<slug> → main, no intermediate branches.
- `three-stage` — feature/<slug> → dev → staging → main.

The implementation MUST treat any other value as an error.

### 5.2 `WALTER_CONTEXT`

Overrides the directory-based context selection (see §2.2). The value
selects a named context that the implementation knows about (e.g.,
`hackathons`). If the implementation does not recognize the value, it
MUST surface a clear error rather than silently defaulting.

---

## 6. Conformance criteria

An implementation is **compliant** if and only if it satisfies all of
the following:

1. **Three layers**: it implements global / context / repository layers
   per Sections 2.1, 2.2, 2.3 — none may be omitted.
2. **Most-specific-wins**: it resolves conflicting rules per Section 3.
3. **Concatenation default**: non-conflicting rules across layers are
   unioned by default; only explicit override syntax forces replacement.
4. **Overlay support**: it implements the overlay per Section 4 at an
   out-of-tree, operator-private location.
5. **Required env vars**: it recognizes `WALTER_BRANCH_FLOW` and
   `WALTER_CONTEXT` per Section 5.
6. **Conformance suite**: it passes the reference
   `agents-md-cascade-conformance.bats` test suite (provided in the
   Walter-OS repository at `tests/oss/`) with no skipped tests.
7. **Documentation**: it documents how to use the cascade, the canonical
   paths it expects, and the scaffolding mechanism, in a place
   discoverable from the project's README.

An implementation MAY extend the cascade with additional layers (e.g.,
team-wide layer between context and repository) provided the extension
does not break the most-specific-wins rule and is documented as a
super-set.

---

## 7. Non-goals

- **File-format opinionation.** This spec does not mandate sections,
  headings, or markup conventions inside any AGENTS.md. Tools layered on
  top (e.g., Walter-OS's discipline contract) define their own
  conventions; the cascade is orthogonal.
- **Multi-operator semantics.** The cascade is a single-operator
  mechanism. Team coordination across the cascade (e.g., enforcing that
  every team member uses the same overlay) is out of scope.
- **Cross-host portability of the overlay.** Operators who want their
  overlay on multiple machines use a separate sync mechanism (private
  git repo, dotfile manager, etc.). The cascade itself is filesystem-
  local.
- **Standardizing the AGENTS.md filename.** This spec uses `AGENTS.md`
  because it's the convention adopted by Anthropic, OpenAI, and Cursor.
  If the ecosystem settles on a different name, the cascade applies
  unchanged.

---

## 8. Security considerations

- **Untrusted overlay content.** An overlay that is not on the operator's
  trusted device is untrusted. A compliant implementation MUST NOT
  auto-load an overlay from a network source without operator
  confirmation.
- **Symlink attacks.** If the overlay or AGENTS.md is symlinked,
  implementations SHOULD verify the link target is within the
  operator's expected paths before reading.
- **Prompt injection through AGENTS.md.** Because AGENTS.md content is
  consumed by an LLM, untrusted AGENTS.md (e.g., from a freshly cloned
  unfamiliar repository) can contain prompt-injection payloads.
  Implementations SHOULD bound the influence of repository-layer
  AGENTS.md content per the [model-card guidance on indirect prompt
  injection](https://www.anthropic.com/research/many-shot-jailbreaking).
  At minimum, sections that grant the agent expanded capabilities (new
  tool permissions, relaxed approval gates) MUST require operator
  acknowledgement.

---

## 9. Authorship & evolution

This spec was extracted from the [Walter-OS](https://github.com/Xipher-Labs/walter-os)
framework (Xipher Labs S.R.L., 2026). The cascade pattern was developed
in production use over the v0.1.0–v0.4.x release cycle of Walter-OS
before being lifted out as a standalone specification.

Comments, issues, and pull requests against this spec are accepted via
the Walter-OS issue tracker. The spec is licensed under Apache-2.0 (see
the repository's `LICENSE-APACHE`) — implementers may copy, adapt, and
redistribute it without restriction beyond attribution.

If broader ecosystem adoption emerges (Anthropic, OpenAI, Cursor, or a
neutral working group taking interest), this document is ready to move
to a neutral venue without modification.

## 10. References

- Walter-OS implementation: <https://github.com/Xipher-Labs/walter-os>
- Walter-OS's global AGENTS.md (reference): `AGENTS.md` at the repo root
- Anthropic AGENTS.md convention: <https://docs.claude.com/en/docs/claude-code/memory>
- OpenAI / Codex CLI convention: <https://github.com/openai/codex>
- Cursor rules documentation: <https://docs.cursor.com/context/rules>
- RFC 2119 (MUST/SHOULD/MAY semantics): <https://datatracker.ietf.org/doc/html/rfc2119>
