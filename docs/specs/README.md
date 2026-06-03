# Specifications

This directory is the active product spec index. Keep current, reusable specs at
the top level. Move shipped, superseded, or operator-specific design records to
[`archive/`](archive/) so new adopters see the public product shape first.

## Active Specs

| Spec | Purpose |
|---|---|
| [`walter-council-v2.md`](walter-council-v2.md) | Council runtime, observability, trust tiers, consensus mode, and Control Tower. |
| [`secrets-runtime-architecture.md`](secrets-runtime-architecture.md) | Runtime secret loading with Infisical and local OS credential stores. |
| [`walter-os-protection-levels.md`](walter-os-protection-levels.md) | Release-age policy and protection levels for dependency changes. |
| [`walter-os-oss-security-hardening.md`](walter-os-oss-security-hardening.md) | OSS security hardening gates and supply-chain controls. |
| [`walter-bridge-litellm-expansion.md`](walter-bridge-litellm-expansion.md) | LiteLLM/provider expansion for the Walter bridge. |
| [`openclaw.md`](openclaw.md) | OpenClaw gateway trust model and runtime contract. |
| [`oss-trust-v0.5.0-small-batch.md`](oss-trust-v0.5.0-small-batch.md) | OSS Trust roadmap small-batch: C-3 pre-commit framework, D-1 GitHub Security Advisories partner, E-3 `@types/*` allowlist, E-4 `walter-os justify revoke` CLI. |
| [`post-merge-feedback-loop.md`](post-merge-feedback-loop.md) | Read-only AD-13 post-merge health classification before fix-PR/rollback automation. |
| [`autonomy-modes.md`](autonomy-modes.md) | AD-6 Lite/Guided/Full autonomy-mode contract for `walter-repo-config.yaml`. |

## Worked Examples

These are generic enough to stay public and useful as implementation references:

| Example | Purpose |
|---|---|
| [`phase-w-1-docker-compose.md`](phase-w-1-docker-compose.md) | Compose-first packaging for the self-hosted stack. |
| [`phase-w-6-install-wizard.md`](phase-w-6-install-wizard.md) | Installer and first-run wizard flow. |
| [`walter-personal-skeleton.md`](walter-personal-skeleton.md) | Personal overlay skeleton for keeping private configuration out of repo. |

## Archive Policy

Archive specs are retained as design history. They are not the recommended
starting point for new users and may describe optional overlays, older rollout
decisions, or private-reference architecture that has since been generalized.
