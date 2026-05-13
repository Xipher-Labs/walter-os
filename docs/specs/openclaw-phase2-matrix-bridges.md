# SPEC: OpenClaw Phase 2 — Matrix Bridge Integration

**Status:** Proposed (implementation gated on Phase 1 operational for 30 days)
**Depends on:** `openclaw.md` (Phase 1 accepted), Synapse homeserver (`comms` profile)

---

## Problem

Phase 1 OpenClaw is Telegram-only. Operators communicate across multiple
platforms (WhatsApp, iMessage, Signal, Instagram, LinkedIn DMs). Manually
switching between apps is high-friction. Phase 2 surfaces all platforms as
OpenClaw "channels" through a Matrix bridge layer hosted on Walter-VM.

---

## Architecture

```
Operator platforms:          Matrix bridges:         OpenClaw:
  Telegram ──────────────── (native bot) ─────────┐
  WhatsApp ──────────────── Beeper-mini ──────────┤
  iMessage ──────────────── Beeper-mini ──────────┤─ Synapse homeserver ─── OpenClaw
  Signal ────────────────── mautrix-signal ────────┤  (Matrix events)       (Phase 2
  Instagram DMs ─────────── mautrix-instagram ─────┤                         bridge mode)
  LinkedIn ───────────────── mautrix-linkedin ──────┘
```

All bridges connect to the local Synapse homeserver (`matrix.<domain>`).
OpenClaw reads Matrix events from Synapse, matching the operator's Matrix
user ID. Replies are routed back through the same bridge → origin platform.

---

## Decisions (proposed — not locked)

| Question | Proposed Decision |
|---|---|
| Bridge software | Beeper-mini for WhatsApp/iMessage; mautrix-* for Signal/Instagram |
| Matrix user ID | `@operator:<domain>` — single identity across all bridges |
| Encryption | Matrix E2E encryption enabled where the bridge supports it |
| Bridge hosting | Same Walter-VM, `comms` Docker Compose profile |
| Phase 2 web UI | `claw.<domain>` (currently loopback-only in Phase 1) becomes tunnel-fronted |
| Platform priority | WhatsApp → iMessage → Signal → Instagram → LinkedIn |

---

## Acceptance Criteria (Phase 2)

- [ ] Synapse homeserver running in `comms` profile; reachable at `matrix.<domain>`.
- [ ] At least one Beeper-mini bridge registered to Synapse.
- [ ] OpenClaw processes Matrix events from at least one bridge platform.
- [ ] Replies from OpenClaw appear in the originating platform within 5 seconds
      of processing (network-normal conditions).
- [ ] `claw.<domain>` admin UI accessible via Cloudflare tunnel (CF Access protected).
- [ ] No hardcoded operator usernames in any bridge config or compose file.

---

## Security Considerations

- Bridge bots connect to external messaging platforms using the operator's
  account credentials (WhatsApp session, iMessage Apple ID, etc.). These are
  **high-value secrets** — store in Infisical, never in compose files.
- Bridge containers should be isolated on a dedicated Docker network
  (`openclaw_net`) with egress to `matrix.DOMAIN` only (no direct LiteLLM access).
- Matrix E2E encryption keys must be backed up. A Synapse key backup is
  mandatory before production use of encrypted bridges.
- Platform-specific risks: iMessage requires a macOS device or Beeper Cloud
  relay. This dependency must be documented per-operator.

---

## Migration Path from Phase 1

Phase 1 → Phase 2 is additive — no Phase 1 config changes required:

1. Deploy Synapse (`comms` profile).
2. Deploy one bridge (recommend: Beeper-mini for WhatsApp or iMessage).
3. Register bridge with Synapse.
4. Set `OPENCLAW_MATRIX_HOMESERVER` env var on the OpenClaw container.
5. OpenClaw picks up Matrix events in addition to Telegram (parallel channels).
6. Expose admin UI via Cloudflare tunnel.

---

## Non-Goals

- Outbound message initiation from OpenClaw on WhatsApp/iMessage (send-only
  is fine for replies; cold-start messages require manual operator initiation
  on the platform to open a session window).
- Bridging group chats. Phase 2 targets operator DMs only.
- Real-time collaborative tooling (that's n8n + workflow automation territory).

---

## Related

- `docs/specs/openclaw.md` — Phase 1 spec (accepted)
- `setup/walter-host/services/openclaw/compose.yml` — Phase 1 service
- `setup/SERVICES-INVENTORY.md` — sidecar migration status
