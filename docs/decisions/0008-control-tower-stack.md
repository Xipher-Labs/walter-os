# 0008. Control Tower Stack

**Date**: 2026-05-11
**Status**: Proposed

## Context

Control Tower es una interfaz visual y conversacional para el Walter Council. Requisitos de contexto:

- **Un solo usuario** (el operator). No hay multi-tenant, no hay auth compleja.
- **Corre en walter-vm** (Hetzner CX53, docker-compose, Tailscale-only). No hay acceso público directo.
- **Reads-heavy**: la mayor parte de la UI es lectura de métricas, logs, y estado. La escritura ocurre en Council Chat y en las acciones de modo/unlock.
- **Realtime requerido** para el Agent Status Board (state changes en ≤ 2s). El resto puede ser polling de 30-60s.
- **Coexiste con el HA replication** (standby homelab node standby). La app no necesita replicarse — si walter-vm cae, el operator no necesita la UI, necesita que el Council se recupere.
- **Integra con LiteLLM** (para Council Chat), **Grafana** (para métricas embebidas), **Plane** (para issues), y el **sistema de archivos local** (para logs y métricas en formato texto).
- **Consistencia con el resto del homelab**: [Project A] usa Next.js 15 + Drizzle + Supabase. Si hay stack familiar, hay menos context-switching cognitivo para el operator cuando mantiene ambos.

Las opciones evaluadas son:

1. **Next.js 15 App Router + WebSockets/SSE** (mismo stack que [Project A])
2. **Tauri** (Rust + web frontend, desktop app nativa)
3. **Streamlit** (Python, rápido de hacer, feo)
4. **HTMX + Go** (minimalista)
5. **Web component sobre Grafana** (cero código nuevo, reutilización máxima)

## Decision

Usamos **Next.js 15 App Router** con:
- **Server-Sent Events** (SSE) para realtime del Agent Status Board (más simple que WebSockets en App Router, no requiere custom server)
- **Tailwind CSS** para styling
- **No ORM, no database propia**: la Tower solo lee del filesystem del walter-vm (métricas `.prom`, logs `.jsonl`, `mode.json`) y llama APIs existentes (LiteLLM, Plane, Grafana). No hay estado propio que persistir excepto el historial de conversaciones (un JSONL append-only en el filesystem).
- **Grafana embebido via iframe** para los dashboards de métricas (no se duplica UI de métricas — Grafana ya tiene la inversión)
- **Container Docker** en walter-vm, accesible via Cloudflare Tunnel + Tailscale ACL

## Consequences

**Lo que se hace más fácil**:
- El operator ya conoce Next.js (de [Project A]). Mantener Control Tower no es aprender otro stack.
- App Router + Server Components + SSE es un patrón bien documentado. No hay reinvención.
- Despliegue idéntico al patrón existente (docker-compose en walter-vm). Cero infraestructura nueva.
- TypeScript end-to-end. Los tipos de las respuestas de LiteLLM y Plane se reusan entre proyectos.
- Si en algún momento Control Tower necesita más features (auth multi-usuario, database propia), el stack lo soporta sin migration.

**Lo que se hace más difícil**:
- El build de Next.js (~2-3 minutos) es más lento que HTMX+Go o Streamlit para cambios en desarrollo.
- Node.js en walter-vm agrega ~200MB de RAM al baseline del servidor. Con CX53 (8GB RAM), irrelevante en la práctica.
- SSE no es bidireccional — para Council Chat se usa polling corto (500ms) en el cliente para simular streaming, o se usa la API de streaming de Next.js 14+ (`ReadableStream` en route handlers). Esto es manejable pero levemente más complejo que WebSockets.

**Riesgos aceptados**:
- Si Next.js rompe la API de route handlers entre minor versions, hay que parchear. Riesgo bajo dado que el proyecto usa versión fija y updates deliberados.
- El historial de conversaciones en JSONL local no sobrevive a una reinstalación completa del container sin backup. Aceptado — es historial de deliberaciones, no datos críticos. Restic lo cubre.

**Nota sobre la arquitectura dual peer (standby homelab node ↔ Walter-VM)**:

El standby homelab node es un peer activo del Council, no solo un standby. Cuando el operator está en BA, el Council corre en standby homelab node con embeddings locales (~10ms). Cuando el operator está remoto, el Council corre en Walter-VM con embeddings CPU-based + Redis cache (≤ 500ms, aceptado). Control Tower siempre corre en Walter-VM independientemente de dónde corra el Council — es la única instancia de la UI.

La sincronización de datos entre peers usa **eventual consistency con Last-Write-Wins**:
- Syncthing para archivos (lessons DB, wiki, heartbeats, logs).
- Postgres logical replication para state (Plane, mode.json si se migra a DB en el futuro).

Esta arquitectura está documentada en `docs/specs/archive/standby-node-replication.md`. El Control Tower no necesita adaptarse — lee del filesystem local de Walter-VM, que Syncthing mantiene sincronizado desde standby homelab node con lag típico de segundos.

## Alternatives considered

**Tauri (Rust + web frontend)**:
- Pro: desktop app nativa, zero latency, no browser, mejor para developer experience.
- Contra: requiere que el operator tenga la app instalada en el Mac. Si accede desde standby homelab node o cualquier otra máquina, no funciona. El Control Tower necesita ser accesible desde cualquier browser en el tailnet, no solo desde la Mac del operator.
- Contra: compilar Tauri para macOS ARM desde walter-vm (Linux x86) requiere cross-compilation o CI remoto — complejidad innecesaria.
- **Rechazado**: la portabilidad browser > la experiencia desktop.

**Streamlit (Python)**:
- Pro: puede estar en producción en 2 horas. El operator conoce Python.
- Contra: Streamlit re-renderiza el estado global con cada interacción (stateful server). No escala bien para realtime (SSE/WebSocket no son ciudadanos de primera clase). La UI es inevitablemente "data science app", no "ops dashboard".
- Contra: introduce Python como dependencia runtime en walter-vm donde el resto es Node.js o containers isolados.
- **Rechazado**: la UX de Streamlit no está a la altura de una herramienta que el operator va a usar diariamente.

**HTMX + Go**:
- Pro: binario estático, zero dependencies en runtime, arranque instantáneo, HTMX es excelente para SSE.
- Contra: Go no está en el stack del operator (Rust, TypeScript, Python sí). Hay que aprender y mantener un nuevo lenguaje para una app interna.
- Contra: sin TypeScript, los tipos compartidos con [Project A] se van.
- Consideración: este sería el stack correcto si el operator fuera principalmente Go developer, o si walter-vm tuviera constraints de RAM muy ajustados. Ninguna condición aplica.
- **Rechazado**: el beneficio de consistency supera al beneficio de minimalismo en este caso.

**Web component sobre Grafana**:
- Pro: cero código nuevo para las métricas. Grafana ya tiene dashboards configurados.
- Contra: Grafana no tiene primitivas para Council Chat, Ideation Session, ni para acciones de control (mode toggle, unlock). Se necesitaría un segundo framework para esas features de todas formas.
- Contra: el UX de Grafana no está diseñado para ser embedding shell — los menus, las annotations, y los controles de tiempo del dashboard son ruido en el contexto de una ops console.
- **Rechazado**: no cubre el 40% de los requisitos (conversational interface, mode control) y la UX es degradada para lo que sí cubre.

**Por qué no tRPC + Drizzle (como [Project A])**:
- Control Tower no tiene su propia base de datos. Toda la data viene de filesystems locales o APIs existentes (LiteLLM, Plane, Grafana). tRPC sin una capa de datos propia es overhead sin beneficio.
- Si en el futuro la Tower necesita persistir estado (chats en DB, alertas con estado), se agrega Drizzle en ese momento.
