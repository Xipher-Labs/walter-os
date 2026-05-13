# 0008. Control Tower Stack

**Date**: 2026-05-11
**Status**: Proposed

## Context

Control Tower is a visual and conversational interface for the Walter Council. Context requirements:

- **Single user**: the operator. No multi-tenancy and no complex auth model.
- **Runs on walter-vm**: Hetzner CX53, docker-compose, Tailscale-only. No direct public access.
- **Read-heavy**: most of the UI reads metrics, logs, and state. Writes happen in Council Chat and in mode/unlock actions.
- **Realtime required** for the Agent Status Board, with state changes visible within 2 seconds. Everything else can poll every 30-60 seconds.
- **Coexists with HA replication** through the standby homelab node. The app itself does not need replication: if walter-vm is down, the operator needs Council recovery more than the UI.
- **Integrates with LiteLLM** for Council Chat, **Grafana** for embedded metrics, **Plane** for issues, and the **local filesystem** for logs and text metrics.
- **Consistency with the rest of the homelab**: example product projects use Next.js 15 + Drizzle + Supabase. A familiar stack reduces cognitive context switching when maintaining both.

The evaluated options were:

1. **Next.js 15 App Router + WebSockets/SSE**: same stack family as the example product projects.
2. **Tauri**: Rust + web frontend, native desktop app.
3. **Streamlit**: Python, fast to build, weak fit for an operations UI.
4. **HTMX + Go**: minimalist server-rendered approach.
5. **Web component over Grafana**: no new metric UI code, maximum reuse.

## Decision

Use **Next.js 15 App Router** with:

- **Server-Sent Events** for realtime Agent Status Board updates. SSE is simpler than WebSockets in App Router and does not require a custom server.
- **Tailwind CSS** for styling.
- **No ORM and no dedicated database**: Control Tower reads from the walter-vm filesystem (`.prom` metrics, `.jsonl` logs, `mode.json`) and calls existing APIs (LiteLLM, Plane, Grafana). It has no durable state of its own except append-only conversation history stored as JSONL on the filesystem.
- **Grafana embedded through iframes** for metric dashboards. The metric UI is not duplicated; Grafana already has the investment.
- **Docker container** on walter-vm, exposed through Cloudflare Tunnel plus Tailscale ACL.

## Consequences

**What becomes easier**:

- The operator already knows Next.js. Maintaining Control Tower does not require learning another stack.
- App Router + Server Components + SSE is a well-documented pattern.
- Deployment matches the existing pattern: docker-compose on walter-vm, with no new infrastructure.
- TypeScript end-to-end. LiteLLM and Plane response types can be reused across projects.
- If Control Tower later needs multi-user auth or its own database, the stack can support that without a migration.

**What becomes harder**:

- Next.js builds take about 2-3 minutes, slower than HTMX+Go or Streamlit for development changes.
- Node.js on walter-vm adds roughly 200 MB of RAM to the server baseline. On CX53 with 8 GB RAM, this is acceptable.
- SSE is not bidirectional. Council Chat uses short client polling, or Next.js route-handler streaming through `ReadableStream`. This is manageable, but slightly more complex than WebSockets.

**Accepted risks**:

- If Next.js changes route-handler APIs between minor versions, the project may need a patch. Risk is low because the project uses pinned versions and deliberate updates.
- Local JSONL conversation history does not survive a full container reinstall without backup. Accepted: it is deliberation history, not critical data. Restic covers it.

**Note on the dual-peer architecture: standby homelab node and Walter-VM**

The standby homelab node is an active Council peer, not only a standby target. When the operator is near the local node, the Council runs there with local embeddings at roughly 10 ms. When the operator is remote, the Council runs on Walter-VM with CPU-based embeddings and Redis cache, accepted at up to 500 ms. Control Tower always runs on Walter-VM regardless of where the Council is running; it is the single UI instance.

Data synchronization between peers uses **eventual consistency with Last-Write-Wins**:

- Syncthing for files: lessons DB, wiki, heartbeats, and logs.
- Postgres logical replication for state if `mode.json` or related state later moves into a database.

This architecture is documented in `docs/specs/archive/standby-node-replication.md`. Control Tower does not need to adapt; it reads Walter-VM's local filesystem, which Syncthing keeps synchronized from the standby homelab node with typical lag of seconds.

## Alternatives Considered

**Tauri (Rust + web frontend)**:

- Pro: native desktop app, zero browser latency, strong developer experience.
- Con: requires the operator to have the app installed on a specific workstation. If the operator uses the standby homelab node or another machine, it does not work. Control Tower needs to be accessible from any browser in the tailnet.
- Con: compiling Tauri for macOS ARM from walter-vm (Linux x86) requires cross-compilation or remote CI.
- **Rejected**: browser portability is more important than desktop experience.

**Streamlit (Python)**:

- Pro: can be in production in about two hours. The operator knows Python.
- Con: Streamlit re-renders global state on every interaction. It is a poor fit for realtime operations UIs, and WebSocket/SSE are not first-class.
- Con: adds Python as a runtime dependency to walter-vm, where the rest is Node.js or isolated containers.
- **Rejected**: the Streamlit UX is not strong enough for a daily operations console.

**HTMX + Go**:

- Pro: static binary, zero runtime dependencies, instant startup, and HTMX works well for SSE.
- Con: Go is not part of the operator's regular stack, which is Rust, TypeScript, and Python.
- Con: without TypeScript, shared types with example product projects are lost.
- Consideration: this would be the right stack if the operator were primarily a Go developer or if walter-vm had severe RAM constraints. Neither condition applies.
- **Rejected**: consistency is more valuable than minimalism here.

**Web component over Grafana**:

- Pro: no new metric UI code. Grafana dashboards already exist.
- Con: Grafana has no primitives for Council Chat, Ideation Session, or control actions such as mode toggles and unlocks. A second framework would still be required.
- Con: Grafana is not designed to be an embedded operations shell. Menus, annotations, and time controls add noise in this context.
- **Rejected**: it misses about 40% of requirements and degrades the UX for the requirements it does cover.

**Why not tRPC + Drizzle, as in the example product stack**:

- Control Tower has no database of its own. Data comes from local filesystems or existing APIs: LiteLLM, Plane, and Grafana. tRPC without a real data layer would add overhead without benefit.
- If Control Tower later needs durable state, such as database-backed chats or stateful alerts, Drizzle can be added then.
