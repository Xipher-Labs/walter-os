# SPEC: OpenClaw — Personal AI Assistant

**Status:** Accepted (2026-05-12)
**Profile:** `assistant` (optional Docker Compose profile)
**Spec covers:** trust model, capability matrix, threat model, operator data flow.

---

## Problem

Operators need a persistent, multi-channel AI assistant that:
- Accepts natural-language tasks over Telegram (Phase 1) and Matrix-bridged
  messaging platforms (Phase 2).
- Routes requests through the operator's self-hosted LiteLLM gateway — no
  direct upstream API calls, no keys in the assistant container.
- Runs on Walter-VM alongside the rest of the stack; requires no additional
  cloud dependency.

---

## Decisions (locked)

| Question | Decision |
|---|---|
| LLM gateway | LiteLLM (self-hosted). OpenClaw uses a dedicated virtual key (`LITELLM_OPENCLAW_KEY`) scoped to allowed models only. |
| Phase 1 channel | Telegram bot only. Matrix/WhatsApp/iMessage bridges are Phase 2. |
| Auth | Gateway token (`OPENCLAW_GATEWAY_TOKEN`) required for off-loopback binding. Strict DM pairing (`OPENCLAW_DM_POLICY=pairing`). Unknown senders receive a pairing code. |
| Version pinning | `openclaw@2026.5.7` pinned in Compose. Update requires an explicit version bump + smoke test. |
| Secret storage | All credentials sourced from environment variables; none hardcoded. Secrets provisioned via Infisical → in-memory shell env → Docker `environment:`. |

---

## Trust Model

OpenClaw operates at **operator trust level** — it acts on behalf of the
authenticated operator only.

| Principal | Trust | Capabilities |
|---|---|---|
| Operator (paired Telegram account) | **Full** | All enabled tools: message, calendar, digest, LLM query |
| Unknown Telegram sender | **None** | Receives pairing-code prompt; blocked until operator approves |
| LiteLLM gateway | **Trusted internal service** | Receives model requests; never exposed to public internet |
| Walter-VM host | **Infrastructure trust** | Owns the container; can read env vars — secure the host |

**Session pairing** is enforced by `OPENCLAW_DM_POLICY=pairing`. This is not
optional — the operator's Telegram chat ID (`OPENCLAW_OPERATOR_CHAT_ID`) is the
only pre-paired identity.

**Gateway token** (`OPENCLAW_GATEWAY_TOKEN`) gates all `/api/*` calls when the
gateway is bound off-loopback (`--bind lan`). Without this token, any container
on `litellm_net` could issue API calls to the gateway. Generate with:
`openssl rand -hex 32`.

---

## Capability Matrix

| Capability | Phase 1 | Phase 2 |
|---|---|---|
| Telegram bot messaging | Yes | Yes |
| Natural-language LLM query | Yes (via LiteLLM) | Yes |
| Calendar event creation | Yes (if calendar integration configured) | Yes |
| Daily digest | Yes | Yes |
| Matrix homeserver channel | No | Yes (Synapse + bridges) |
| WhatsApp / iMessage / Signal | No | Yes (Beeper/Matrix bridges) |
| Web admin UI (`claw.<domain>`) | No (port 18789, loopback only) | Yes (tunnel-fronted) |
| Browser automation tools | No | Operator-configured add-on |

---

## Threat Model

| Threat | Mitigation |
|---|---|
| Telegram bot impersonation | `OPENCLAW_DM_POLICY=pairing` + `OPENCLAW_OPERATOR_CHAT_ID` allowlist |
| Unauthorized gateway access from containers | `OPENCLAW_GATEWAY_TOKEN:?` required; binding on `0.0.0.0` inside container with empty token blocked at start |
| LLM key exfiltration | `LITELLM_OPENCLAW_KEY` is a LiteLLM virtual key with model-scope limits; even if leaked, attacker can only use allowed models, not extract upstream provider keys |
| Malicious message payload | OpenClaw parses only structured Telegram updates; no shell eval of message content |
| First-boot unprotected state | Container enters `sleep infinity` until `openclaw onboard` runs; healthcheck fails, alerting operator |
| Container image supply chain | `node:24-slim` is a well-known Docker Hub official image; OpenClaw npm package is pinned to `2026.5.7` |
| Secrets on disk | No secrets written to disk. All env vars injected at runtime via Docker Compose `environment:` from operator shell env |

---

## Data Flow (Phase 1)

```
Operator → Telegram → OpenClaw container
                          │
                          ├── LITELLM_OPENCLAW_KEY → LiteLLM → upstream LLM providers
                          │
                          └── OPENCLAW_GATEWAY_TOKEN (validates inbound /api/* calls)
```

1. Operator sends Telegram message to `@${WALTER_OPENCLAW_BOT_HANDLE}`.
2. OpenClaw authenticates sender via DM pairing.
3. Request routed to LiteLLM at `http://litellm:4000` using `LITELLM_OPENCLAW_KEY`.
4. LiteLLM selects model from `OPENCLAW_DEFAULT_MODEL` (default: `sonnet` route).
5. Response returned to Telegram.

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `LITELLM_OPENCLAW_KEY` | Yes | LiteLLM virtual key scoped to OpenClaw |
| `OPENCLAW_TELEGRAM_BOT_TOKEN` | Yes | Telegram BotFather token |
| `OPENCLAW_OPERATOR_CHAT_ID` | Yes | Operator's Telegram numeric chat ID |
| `OPENCLAW_GATEWAY_TOKEN` | Yes (`:?` fail-loud) | Auth token for gateway off-loopback bind |
| `OPENCLAW_DEFAULT_MODEL` | No (default: `sonnet`) | LiteLLM route name |
| `OPENCLAW_DM_POLICY` | No (default: `pairing`) | DM policy; do not change to `auto-reply` |
| `WALTER_DOMAIN` | Yes | Used for CORS allowed origins on admin UI |

---

## Non-Goals

- OpenClaw is NOT a replacement for the operator's primary Claude Code / Codex
  sessions. It handles Telegram-based async tasks, not interactive development.
- Phase 2 Matrix bridges are a separate spec (`openclaw-phase2-matrix-bridges.md`).
- OpenClaw does not manage its own LLM API keys. All model access goes through
  LiteLLM.

---

## Related

- `setup/walter-host/services/openclaw/compose.yml` — service definition
- `docs/specs/openclaw-phase2-matrix-bridges.md` — Phase 2 bridge architecture
- `docs/specs/secrets-runtime-architecture.md` — secret provisioning flow
- `setup/SERVICES-INVENTORY.md` — runtime status
