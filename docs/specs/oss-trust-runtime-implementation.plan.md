# OSS Trust runtime implementation plan

Parent: issue #122.

This plan turns the remaining OSS Trust runtime specs into mergeable, reviewable
PR slices. The order is dependency-driven: session state is already in the open
#218/#219 stack, capability tokens consume that session state, sandbox consumes
capabilities, invisible mounts refine the sandbox, audit integrity consumes the
session signing keys, telemetry consumes the audit chain, and SLSA is independent
release hardening.

## Merge Preconditions

1. Merge #218 (`codex/time-bounded-sessions`).
2. Merge #219 (`codex/session-timeout-hook`).
3. Rebase the capability-token stack onto `main` after #218/#219 land.

Until then, capability-token implementation PRs should be stacked on
`codex/session-timeout-hook` so the diff only contains the next layer.

## Design Risks To Resolve Before Claiming Completion

- The process-isolation spec currently assumes hooks can wrap the eventual
  `Bash`/`Edit`/`Write` execution. Claude hook contracts normally allow/block;
  they do not rewrite the tool runner. The sandbox implementation must identify
  the actual skill/tool execution entry point before claiming isolation.
- `approval-gate.sh` does not yet emit a stable machine-readable
  `{category,tier,target}` result. Capability enforcement and invisible mounts
  must either add that shared classifier or risk duplicating brittle regexes.
- The A-4 implementation uses lazy session creation in `session-state.sh`, not
  a standalone `session-start.sh`. Capability keys and audit signing must attach
  to that real lifecycle.
- Invisible mounts should use the hard-fail `:dir` / `:file` typed path model
  from the AC, not the older warn-and-adapt wording.
- Static Promtail YAML cannot be conditionally disabled by
  `WALTER_AUDIT_LOKI_DISABLE=1` alone. Telemetry needs a generated config,
  compose override/profile, or separate included tail file.
- The audit dashboard should avoid `unwrap ts` directly on ISO timestamp
  strings; use count/rate style LogQL or parse a numeric timestamp field.
- SLSA/reproducibility is independent of runtime isolation and can run in a
  separate PR stack, but it must first add a deterministic workflow-controlled
  tarball asset. GitHub auto source archives are not sufficient evidence.

## PR Sequence

### Capability Tokens

1. **Capability session keys**.
   - Files: `scripts/walter/lib/session-state.sh`, `tests/walter/session-state.bats`,
     `docs/specs/capability-tokens.md`.
   - Deliverable: each session has a private signing key path, public key path,
     and caps directory with safe permissions.
   - Verification: Bats covers key creation, public-key persistence, cap dir
     permissions, and deletion of the private key on session end.
2. **PASETO helper and CLI**.
   - Files: `scripts/walter/lib/capability-token.sh`,
     `scripts/walter/subcommands/cap.sh`, `bin/walter-os`,
     `tests/walter/capability-token.bats`, `tests/walter/cap-cli.bats`.
   - Deliverable: `walter-os cap mint|list|verify|revoke` for signed,
     session-bound tokens. If the currently documented `paseto-cli` package is
     unavailable, update the spec to the actual pinned implementation and keep
     the wire format as PASETO v4 public.
   - Verification: round-trip sign/verify, expiry, bare-duration rejection, and
     subagent mint refusal.
3. **Capability enforcement hook**.
   - Files: `hooks/capability-check.sh`, `install.sh`,
     `tests/hooks/capability-check.bats`,
     `tests/install/hook-chain-content.bats`.
   - Deliverable: high-tier `Bash`/`Edit`/`Write` require a matching valid cap;
     low-tier operations pass through.
   - Verification: no-cap block, matching-cap allow, expired-cap block,
     low-tier passthrough, and two-factor bypass.
4. **Default skill capabilities and audit checks**.
   - Files: `contexts/_examples/skill-capabilities.example.yml`,
     `scripts/walter/lib/skill-cap-loader.sh`,
     `skills/daily-supply-chain-audit/scripts/audit.sh`,
     `tests/audit/*cap*`, `docs/operational/capability-tokens.md`.
   - Deliverable: operator-overridable auto-caps and daily audit state checks.

### Process Isolation Sandbox

5. **Sandbox shim and provider detection**.
   - Files: `scripts/walter/lib/sandbox.sh`,
     `tests/walter/sandbox-shim.bats`.
   - Deliverable: `walter_sandbox_provider`, `walter_sandbox_check`, and
     `walter_sandbox_run` for macOS `sandbox-exec`, Linux/WSL `nsjail`, and
     optional Linux `firejail`.
6. **Default hook and skill profiles**.
   - Files: `setup/sandbox-profiles/*`,
     `tests/walter/sandbox-hook-profile.bats`,
     `tests/walter/sandbox-skill-profile.bats`.
   - Deliverable: read-only hook profile, repo-scoped skill profile, sensitive
     path deny rules, and signal/network constraints per OS.
7. **Hook and skill integration**.
   - Files: `hooks/*.sh`, skill execution entry points, `install.sh`,
     `skills/daily-supply-chain-audit/scripts/audit.sh`.
   - Deliverable: runtime fail-closed sandbox use, install-time warning
     sentinel, provider/profile checksum baselines, and explicit bypass logging.
8. **Capability-aware dynamic profiles**.
   - Files: `scripts/walter/lib/sandbox.sh`,
     `tests/walter/sandbox-cap-integration.bats`.
   - Deliverable: valid cap `scope.paths` tightens the sandbox profile for the
     wrapped command.

### Read-Only / Hidden Secret Mounts

9. **Invisible mount mechanism**.
   - Files: `scripts/walter/lib/sandbox.sh`,
     `setup/sandbox-profiles/invisible-paths.default.txt`,
     `tests/walter/sandbox-invisible-*.bats`.
   - Deliverable: high-tier sandbox runs hide default and overlay-configured
     secret-bearing paths with type-correct placeholders.
10. **High-tier integration, bypass, and audit**.
    - Files: `hooks/approval-gate.sh`, sandbox wrapper call sites,
      daily audit script, `docs/operational/sandbox-invisible-mounts.md`.
    - Deliverable: high-tier operations activate invisible mounts; two-factor
      secret-read bypass is logged and audited.

### Audit Chain And Receipts

11. **Audit chain writer**.
    - Files: `scripts/walter/lib/audit-chain.sh`,
      `tests/walter/audit-chain-append.bats`.
    - Deliverable: atomic JSONL append with sorted-key normalization,
      per-day chain files, and `prev_hash`.
12. **Signing and verification**.
    - Files: `scripts/walter/lib/audit-chain.sh`,
      `scripts/walter/subcommands/audit.sh` or existing audit dispatcher,
      `bin/walter-os`, `tests/walter/audit-chain-verify.bats`.
    - Deliverable: row signatures using session keys, public-key archive, and
      `walter-os audit verify-chain`.
13. **Hook integration and daily roots**.
    - Files: `hooks/approval-gate.sh`, `hooks/bash-denylist.sh`,
      `hooks/network-gate.sh`, `hooks/capability-check.sh`,
      `tests/hooks/audit-chain-hook-integration.bats`.
    - Deliverable: exactly one audit row per PreToolUse decision, `close-day`,
      cross-day roots, and optional Rekor upload.

### Audit Telemetry

14. **Promtail and dashboard provisioning**.
    - Files: `setup/walter-host/services/observability/promtail/*`,
      `setup/walter-host/services/observability/grafana/provisioning/dashboards/walter-audit.json`,
      `tests/services/*audit*`.
    - Deliverable: local Loki ingestion of audit-chain JSONL with dashboard
      panels and default retention.
15. **Loki verification and opt-out**.
    - Files: audit CLI, `docs/operational/audit-telemetry.md`,
      `tests/walter/audit-chain-verify-from-loki.bats`.
    - Deliverable: `verify-chain --from-loki`, `WALTER_AUDIT_LOKI_DISABLE=1`,
      and status visibility.

### SLSA L3 And Reproducible Builds

16. **SLSA provenance**.
    - Files: `.github/workflows/release.yml`,
      `tests/release/attestation-verify.bats`,
      `docs/security/verification.md`.
    - Deliverable: pinned `actions/attest-build-provenance`, release assets
      with in-toto attestations, and release-time attestation verification.
17. **Deterministic artifacts**.
    - Files: `.github/workflows/release.yml`,
      `scripts/release/reproduce.sh`,
      `tests/release/reproducibility.bats`,
      `docs/security/reproducible-builds.md`.
    - Deliverable: deterministic source tarball, SBOM ordering, checksum
      ordering, pinned toolchain smoke checks, and fresh-run reproducibility
      verification.

## Review Loop For Every PR

Each PR follows the repo review contract:

1. Local Bats/ShellCheck/diff checks for the touched surface.
2. PR title validated with `hooks/pr-title-validator.sh`.
3. PR opened against the dependency-correct base branch.
4. Copilot review requested through the REST `requested_reviewers` endpoint.
5. Codex cross-review run against the PR base.
6. Findings fixed one commit per finding, with PR comments replied/resolved.
7. Repeat until checks are green and there are no active unresolved review
   threads.
