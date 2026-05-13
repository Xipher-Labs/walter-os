# Walter Council v2

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Plane**: (ticket to be filed)

## Problem

El Walter Council (v1) es funcional pero ciego, sordo a sus propias fallas, y desconectado entre sus partes móviles. Los seis agentes ejecutan tareas en Plane, escriben en el wiki, y postean al Telegram, pero no hay forma de ver en un solo lugar qué están haciendo, cuánto gastan, ni qué aprendió uno que el otro debería saber.

Cuando un agente muere a mitad de una tarea, la issue queda `claimed` para siempre. No hay heartbeat, no hay watchdog, no hay re-encole. El operator se entera cuando no llega el digest matutino. El gasto en tokens se puede ver en el dashboard de LiteLLM, pero no hay forma de saber qué agente gastó qué en qué contexto. La memoria de cada agente vive en silos — el reviewer no sabe lo que aprendió el coder la semana pasada.

El resultado práctico: el operator sigue teniendo que babysit el Council de una manera distinta a la de v1 pero igual de costosa en atención. La promesa de autonomía real requiere observabilidad real, recuperación ante fallas, y un canal conversacional donde el operator pueda hablar CON el Council, no solo recibir notificaciones de él.

## Proposed solution

Walter Council v2 es un conjunto de nueve mejoras de infraestructura al Council existente, más una nueva interfaz visual y conversacional llamada **Control Tower**. Las nueve mejoras se agrupan en cuatro capas: observabilidad y costos (mejoras 1-2), memoria e inteligencia colectiva (mejoras 3-4), resiliencia operacional (mejoras 5-6), y controles de autonomía (mejoras 7-9). Control Tower es la superficie de operación que reune todo esto en un solo lugar.

Las mejoras son incrementales y no breaking: cada una se puede implementar y desplegar independientemente. El orden de la implementación sigue el critical path que maximiza el valor observable más rápido.

---

## Improvement 1: Council Observability (Prometheus + Grafana)

### Problem statement

No hay telemetría de primer nivel sobre el trabajo del Council. El operator puede abrir el dashboard de LiteLLM o grepar el audit log, pero no hay un panel unificado que muestre en tiempo real cuántas tasks se ejecutaron hoy, cuánto se gastó por agente, cuántos bloqueos del approval-gate se activaron, ni cuál agente está en qué estado.

### Proposed solution

Exponer métricas Prometheus desde el agent runner (`scripts/agents/`) y crear un dashboard Grafana que consolide estas métricas con los paneles existentes de LiteLLM.

**Métricas nuevas** (namespace `walter_council_`):

| Métrica | Labels | Descripción |
|---|---|---|
| `walter_council_tasks_total` | `agent`, `result` (success/failed/needs_operator) | Counter. Tasks terminadas por agente y resultado. |
| `walter_council_tokens_total` | `agent`, `model` | Counter. Tokens consumidos (sum input + output). |
| `walter_council_approvals_total` | `agent`, `category`, `outcome` (blocked/allowed_operator/allowed_standing) | Counter. Eventos del approval-gate. |
| `walter_council_task_duration_seconds` | `agent` | Histogram. Duración de cada task desde claim hasta done/failed. |
| `walter_council_agent_state` | `agent`, `state` (idle/working/blocked) | Gauge. Estado actual de cada agente. |
| `walter_council_heartbeat_age_seconds` | `agent` | Gauge. Segundos desde el último heartbeat (para detección de zombies, ver Improvement 5). |

El agent runner escribe estas métricas a un archivo de texto en formato Prometheus (`/var/lib/walter-council/metrics.prom`) y un proceso `textfile_collector` de Node Exporter las expone. No se agrega un servidor HTTP nuevo al runner.

### Acceptance Criteria

- [AC-1] `curl walter-vm:9100/metrics | grep walter_council_tasks_total` retorna la métrica con labels correctos después de ejecutar cualquier task.
- [AC-2] Dashboard Grafana "Walter Council" existe en el Grafana de walter-vm con al menos 6 paneles: tasks/day, tokens/agent, task success rate, approval-gate heatmap, agent state, task duration P95.
- [AC-3] Métricas persisten a través de reinicios del agent runner (el archivo `.prom` sobrevive al proceso).
- [AC-4] `walter-os agents status` muestra las métricas del día actual en formato texto (sin requerir acceso a Grafana).

---

## Improvement 2: Cost Attribution per Agent

### Problem statement

LiteLLM registra spend, pero los tags actuales no incluyen `agent_id` ni `task_id`. El operator no puede saber si el costo del mes lo generó el coder o el researcher, ni qué task específica quemó $8 en un solo run.

### Proposed solution

Agregar tags `agent_id`, `task_id`, y `context` en cada llamada LLM via la metadata field de LiteLLM (ya soportada en `llm.sh` pero sin todos los tags). Conectar el endpoint `/spend/tags` de LiteLLM al nuevo comando `walter-os spend report`.

El campo `metadata` en cada llamada se expande de `{agent: $agent}` a `{agent_id: $agent, task_id: $task_id, context: $context, model_alias: $model_tag}`.

LiteLLM ya agrupa spend por tags via su tabla `LiteLLM_SpendLogs`. El reporte los query directamente vía la LiteLLM API (`GET /spend/tags?start_date=...&end_date=...&tags=agent_id`).

### Acceptance Criteria

- [AC-1] Cada llamada en `llm.sh` incluye `task_id` (proveniente de `$WALTER_AGENT_PLANE_ISSUE`) y `context` (proveniente de `$WALTER_AGENT_CONTEXT`) en el campo `metadata`.
- [AC-2] `walter-os spend report --by-agent --last 7d` imprime una tabla: agente | modelo | tokens_input | tokens_output | costo_usd, ordenado por costo desc.
- [AC-3] `walter-os spend report --by-task --last 7d` imprime las top 20 tasks más costosas con issue ID, agente, modelo, y costo.
- [AC-4] Si el gasto de cualquier agente en las últimas 24h supera su daily budget, aparece una advertencia en el output de `status` y se dispara una alerta `warn` (ver Improvement 8).

---

## Improvement 3: Memory Consolidation — Wiki Weekly Job

### Problem statement

El wiki crece sin poda. Páginas similares se crean sobre el mismo tema (dos páginas sobre LiteLLM config, tres sobre el bootstrap de la VM). Algunas definen el mismo concepto de forma contradictoria. Muchas páginas obsoletas (last-modified > 6 meses y sin links entrantes) ocupan espacio y agregan ruido al contexto que se inyecta en prompts.

### Proposed solution

Un job semanal (cron en walter-vm, domingos 02:00) que corre el agente janitor con una skill específica de consolidación. El job hace tres cosas en orden:

1. **Dedupe**: usa embeddings (`bge-small-en-v1.5` vía standby homelab node Ollama o Z440 vLLM) para detectar páginas con similitud coseno > 0.92. Propone merges, no los ejecuta — produce un reporte JSON con los candidatos y lo postea como Plane issue `wiki:consolidation` para que el operator lo apruebe.
2. **Contradicciones**: usa un LLM (cheap/haiku) para revisar pares de páginas sobre el mismo concepto y detectar definiciones conflictivas. Las marca con un comment `[CONTRADICTION]` en la página más antigua.
3. **Pruning**: marca páginas con `last-modified > 180 days AND no inbound links` como `[STALE]` en el frontmatter. No las borra — el operator confirma el borrado.

El output del job es siempre propuestas, nunca acciones irreversibles.

### Acceptance Criteria

- [AC-1] El job corre sin errores en walter-vm a las 02:00 los domingos. Log en `/var/log/walter-council/wiki-consolidation.log`.
- [AC-2] Después de correr en un wiki con ≥ 20 páginas, genera al menos un reporte de candidatos (aunque sea vacío si no hay similitud > 0.92).
- [AC-3] El reporte JSON de candidatos de dedupe incluye: `page_a`, `page_b`, `similarity_score`, `reason`. Se postea como Plane issue con label `wiki:consolidation`.
- [AC-4] Páginas marcadas `[STALE]` NO se borran automáticamente. Requieren acción explícita del operator (`walter-os wiki prune --confirm`).
- [AC-5] El job completa en ≤ 10 minutos en un wiki de hasta 200 páginas (medido en prueba manual).

---

## Improvement 4: Cross-Agent Learning Broker

### Problem statement

Cada agente guarda lessons en `~/sync/agent-memory/<agent>/`. El reviewer aprendió que cierto patrón de auth es inseguro; el coder sigue usándolo en la siguiente issue porque no tiene acceso a las lessons del reviewer. Cada agente aprende en un silo.

### Proposed solution

Un broker de lessons centralizado: un índice SQLite (`~/.config/walter-os/lessons.db`) con schema:

```sql
CREATE TABLE lessons (
  id          TEXT PRIMARY KEY,
  source_agent TEXT NOT NULL,
  tags        TEXT,           -- JSON array de strings
  headline    TEXT NOT NULL,  -- frase corta (≤ 120 chars)
  body        TEXT,           -- detail completo
  embedding   BLOB,           -- vector float32[], 384-dim (bge-small)
  context     TEXT,           -- context:work / context:projects-personal / etc.
  created_at  TEXT NOT NULL,
  confidence  REAL DEFAULT 1.0
);
```

**Escritura**: cuando un agente termina una task y encuentra algo que vale la pena recordar, llama `lesson_write <headline> <body> <tags>` (nueva función en `scripts/agents/lib/lessons.sh`). El script computa el embedding local y lo escribe al DB.

**Lectura (injection)**: antes de que cualquier agente invoque el LLM para una task, `lesson_query <task_description> <agent_name>` busca las top-5 lessons por similitud coseno (filtrado por context si corresponde). Las lessons relevantes se inyectan en el system prompt del agente bajo un header `## Lessons from the Council`.

**Embedding — arquitectura dual peer**:
- **Cuando el agente corre en standby homelab node** (operator en BA, peer local activo): embedding service local (`nomic-embed-text` via Ollama), ~10ms, sin cache necesaria.
- **Cuando el agente corre en Walter-VM** (operator remoto o failover): embedding service CPU-based en Walter-VM (`bge-small-en-v1.5` o `nomic-embed-text`) + Redis cache para requests frecuentes. Latencia esperada ≤ 500ms — aceptada por el operator.

El standby homelab node no es un backup pasivo — es un **peer activo** que corre el Council cuando el operator está en BA. La sincronización standby homelab node ↔ Walter-VM de lessons DB, wiki, y Plane state usa **eventual consistency con Last-Write-Wins**: Syncthing para archivos, Postgres logical replication para state. Ver `docs/specs/archive/standby-node-replication.md` para la arquitectura de replicación — no se duplica aquí.

No depende de la API de Anthropic.

**Límite**: máximo 5 lessons por invocación, máximo 800 tokens. Lessons con confidence < 0.5 no se inyectan (mecanismo de feedback: el operator puede bajar confidence de lessons que resulten incorrectas via `walter-os lessons rate <id> <score>`).

### Acceptance Criteria

- [AC-1] `lessons.db` existe en `~/.config/walter-os/` después de la primera ejecución de cualquier agente con la nueva lib.
- [AC-2] Después de que el reviewer escribe una lesson sobre un patrón de auth, el coder la recibe (como parte de su system prompt) en la siguiente task con tags relevantes. Verificable via `--dry-run` que imprime el system prompt resultante.
- [AC-3] `walter-os lessons list --agent reviewer --last 30d` lista las lessons del reviewer con headline, tags, y fecha.
- [AC-4] `walter-os lessons rate <id> 0.0` baja la confidence a 0; la lesson deja de inyectarse. Verificable via el mismo `--dry-run`.
- [AC-5] El query de lessons agrega ≤ 500ms al tiempo de inicio de cualquier task. En standby homelab node (embedding local, operator en BA): target ≤ 50ms. En Walter-VM (CPU-based + Redis cache): target ≤ 500ms. La diferencia es aceptada — latencia adicional en el path remoto no es problema operacional.

---

## Improvement 5: Failure Recovery — Heartbeat + Zombie Watchdog

### Problem statement

Cuando un agente muere mid-task (OOM, red caída, timeout del LLM, crash del proceso), la issue Plane queda en estado `claimed` indefinidamente. No hay mecanismo que detecte esto. El operator se entera manualmente, días después, cuando ve que la issue nunca avanzó.

### Proposed solution

Tres piezas coordinadas:

**A — Heartbeat**: el agent runner (`scripts/agents/run.sh`) escribe un heartbeat cada 60 segundos al archivo `/var/lib/walter-council/heartbeats/<agent>/<issue_id>.heartbeat` con timestamp ISO-8601 y checkpoint de progreso (qué archivos tocó, qué tests corrió). El heartbeat es un append-only JSONL.

**B — Zombie watchdog**: un cron en walter-vm cada 5 minutos corre `scripts/agents/watchdog.sh`. Este script:
1. Lista todas las issues en estado `claimed` en Plane.
2. Para cada una, busca el heartbeat file correspondiente.
3. Si el heartbeat file no existe O si `now - last_heartbeat_ts > 30min`, la issue se declara zombie.
4. El watchdog postea un comment en la issue ("Agent declared zombie after 30min without heartbeat. Re-enqueueing.") y hace la transición de estado a `ready`, limpiando el assignee.

**C — Checkpoint serialization**: el heartbeat JSONL actúa como checkpoint. Cuando el watchdog re-encola una issue, el próximo agente que la tome lee el heartbeat más reciente para saber desde dónde continuar (qué archivos ya se modificaron, qué tests ya pasaron). El checkpoint usa una clave simple `completed_steps: [...]` donde cada step es el nombre de la subtask del plan.

### Acceptance Criteria

- [AC-1] Mientras un agente corre una task, el archivo de heartbeat se actualiza cada 60s. Verificable con `watch -n 5 cat /var/lib/walter-council/heartbeats/<agent>/<issue_id>.heartbeat`.
- [AC-2] Matar el proceso del agente a mitad de una task resulta en: dentro de 35 minutos, el watchdog detecta el zombie, postea el comment en Plane, y retorna la issue a `ready`.
- [AC-3] El log del watchdog (`/var/log/walter-council/watchdog.log`) registra cada detección de zombie con timestamp, agente, y issue ID.
- [AC-4] Cuando un segundo agente toma la re-encolada issue, puede leer el checkpoint y sabe qué steps ya estaban completos (mensaje en el comment de claim: "Resuming from checkpoint: steps [X, Y] already done."). El heartbeat persiste qué steps completó (`completed_steps`). `files_touched` y `tests_run` quedan como stub fields (siempre `[]` y `0`) hasta que Phase U agregue tool-call instrumentation hooks. **PARTIAL** — `completed_steps` implementado, file/test tracking deferred.
- [AC-5] `walter-os agents status` incluye una sección "Zombies detected (last 7d): N".

---

## Improvement 6: Project Induction Skill

### Problem statement

Cuando se crea un proyecto nuevo, el operator tiene que poblar manualmente el contexto: escribir el `AGENTS.md` del repo, el primer spec, el primer epic en Plane, y configurar las reglas no-negociables. Este proceso es inconsistente — a veces falta el `AGENTS.md`, a veces el spec es incompleto, a veces el primer epic nunca se crea. El resultado es que los agentes que trabajan en el proyecto nuevo no tienen el contexto necesario para trabajar bien desde el día uno.

### Proposed solution

Una nueva skill `project-induction` que se invoca via `walter new project <type> <name>`. La skill guía al operator a través de una entrevista de ~7-9 minutos con 7-9 preguntas estructuradas:

1. ¿Qué hace este proyecto? (2-3 oraciones, lenguaje de usuario)
2. ¿Cuál es el stack técnico principal?
3. ¿Qué reglas son no-negociables? (seguridad, compliance, performance)
4. ¿Cuáles son los 3 KPIs que definen el éxito en 6 meses?
5. ¿Qué integraciones externas son críticas? (APIs, MCPs, servicios)
6. ¿Quiénes son los usuarios? (perfil, volumen esperado)
7. ¿Qué es lo que más podría salir mal?
8. ¿Hay PHI, datos financieros, o datos legalmente sensibles?
9. ¿Cuál es el path al mercado? (deploy, distribución)
10. ¿Qué agentes del Council van a trabajar aquí? ¿Alguno restringido?
11. ¿Branching strategy? ¿Feature flags? ¿Environments?
12. ¿Hay un deadline hard o milestone crítico pronto?

Output de la inducción:
- `docs/specs/<slug>-project-charter.md` (problem + stack + KPIs + constraints)
- `AGENTS.md` del repo con las reglas específicas del proyecto
- Primer Plane epic con 5-8 tasks de bootstrap (setup del repo, CI, primera feature, primer spec)
- Entry en `wiki/projects/<name>.md` con el resumen del charter

### Acceptance Criteria

- [AC-1] `walter new project webapp my-app` inicia la entrevista interactiva en la terminal. Si se pasa `--non-interactive`, lee las respuestas de un archivo YAML.
- [AC-2] Al finalizar la entrevista, existe `docs/specs/my-app-project-charter.md` con todos los campos del charter poblados desde las respuestas.
- [AC-3] Al finalizar, existe `AGENTS.md` en el root del repo nuevo con al menos: stack, reglas no-negociables, agentes habilitados/restringidos, y KPIs.
- [AC-4] Se crea un Plane epic "Bootstrap: my-app" con al menos 5 tasks. Verificable via `walter-os agents status` o la Plane UI.
- [AC-5] Si el operator responde "sí" a PHI, el `AGENTS.md` generado incluye automáticamente las reglas de `medical-data-compliance`. Si el operator responde "sí" a datos financieros, el `AGENTS.md` incluye un bloque TODO marcando que `financial-data-compliance` skill está pending. Hasta su creación, el operator debe confirmar manualmente operaciones financieras. La skill `financial-data-compliance` en sí está deferred — ver `docs/specs/financial-data-compliance.md` (TBD).

---

## Improvement 7: Trust Calibration per Agent

### Problem statement

Hoy el approval-gate es binario: bloqueado o no. No hay distinción entre un reviewer (que es read-only y de bajo riesgo) y un janitor (que toca archivos de configuración y puede causar daño real si se equivoca). Esto lleva a dos problemas: el operator recibe aprobaciones innecesarias para operaciones de bajo riesgo del reviewer, y el janitor tiene el mismo nivel de autonomía que el reviewer en categorías donde debería tener menos.

### Proposed solution

Introducir `trust_tier` por agente (low/medium/high) y una tabla de override que define qué categorías del approval-gate se auto-aprueban por tier. Ver ADR `0009-agent-trust-tiers.md` para la decisión completa.

La tabla de trust se persiste en `~/.config/walter-os/trust-tiers.yml` y es leída por `approval-gate.sh` antes de decidir block/allow.

### Acceptance Criteria

- [AC-1] Cada agente tiene un `trust_tier` asignado en `trust-tiers.yml`. Los valores iniciales coinciden con la tabla definida en ADR-0009.
- [AC-2] El reviewer (high trust) puede ejecutar `git push origin feature/*` sin approval del operator. Verificable via `approval-gate.sh check "git push origin feature/test" --tool Bash` con `WALTER_AGENT_NAME=reviewer`.
- [AC-3] El janitor (low trust) sigue requiriendo approval para `rm -rf` en paths fuera de `/tmp`. Verificable con el mismo check.
- [AC-4] `walter-os agents trust <agent>` muestra el tier y la lista de categorías auto-aprobadas para ese agente.
- [AC-5] Cambiar el `trust_tier` de un agente en `trust-tiers.yml` se refleja inmediatamente en las decisiones del gate (sin reinicio requerido).

---

## Improvement 8: Hierarchical Failure Mode Signaling

### Problem statement

Hoy todas las alertas del Council van al mismo Telegram bot con el mismo formato. Un aviso de "dep bump disponible" tiene la misma presencia visual que "runaway LLM spend detectado" o "CVE crítico en MCP". El operator tiene que leer todo para no perderse lo crítico.

### Proposed solution

Cuatro tiers de señalización, con rutas de notificación distintas:

| Tier | Descripción | Canal | Efecto sobre el Council |
|---|---|---|---|
| `info` | Operación rutinaria, sin acción requerida. | Solo log local en `/var/log/walter-council/events.log` | Ninguno |
| `warn` | Algo anómalo pero tolerable. Operator debería saberlo. | Telegram (sin interrupción) | Ninguno |
| `critical` | Falla real o gasto excepcional. Requiere atención pronto. | Telegram con formato especial + bandera en Control Tower | Ninguno |
| `panic` | Evento de seguridad o runaway. Requiere intervención humana inmediata. | Telegram + email + bandera roja en Control Tower + **pause automático del Council** + **lock del approval-gate hasta `/unlock` del operator** | Council pausado, gate bloqueado |

**Eventos y sus tiers**:

| Evento | Tier |
|---|---|
| Task completada exitosamente | `info` |
| Dep bump disponible | `info` |
| Tarea re-encolada por watchdog | `warn` |
| Daily budget de un agente superado en 80% | `warn` |
| Approval-gate bloqueó una operación | `warn` |
| Task fallida después de 2 retries | `critical` |
| Daily budget de un agente superado (100%) | `critical` |
| CVE CVSS ≥ 7 detectado por supply-chain audit | `panic` |
| MCP con tool-name shadowing detectado | `panic` |
| Runaway spend: gasto mensual > 200% del baseline | `panic` |
| Agente intentó modificar hooks o AGENTS.md | `panic` |

La función `alert_emit <tier> <message> <context_json>` en `scripts/agents/lib/alerts.sh` es el punto de entrada único para todos los eventos. Los agents y scripts existentes la llaman en lugar de postear directamente a Telegram.

### Acceptance Criteria

- [AC-1] `alert_emit info "task completed" '{}'` solo escribe al log local. No llega a Telegram.
- [AC-2] `alert_emit warn "budget 80% consumed" '{}'` envía mensaje Telegram con prefijo `[WARN]` y no pausa el Council.
- [AC-3] `alert_emit panic "CVE detected" '{}'` envía Telegram + email al operator, pausa el Council (crea el pause flag), y hace que `approval-gate.sh` bloquee TODAS las operaciones hasta que el operator corra `walter-os agents unlock --reason "..."`.
- [AC-4] El log de eventos (`/var/log/walter-council/events.log`) es un JSONL append-only con timestamp, tier, message, y context.
- [AC-5] `walter-os agents unlock --reason "CVE triaged, not exploitable in our setup"` levanta el panic lock y registra el reason en el log de eventos.

---

## Improvement 9: Council Consensus Mode

### Problem statement

Cuando el operator no está disponible (vacaciones, viaje, fin de semana), las tasks que requieren approval humano se acumulan en estado `needs-operator`. El Council puede evaluar si muchas de estas tasks son suficientemente rutinarias como para auto-aprobarse — pero no tiene un mecanismo formal para hacerlo. El operator regresa a una cola larga de aprobaciones pendientes que pudo haber sido reducida automáticamente sin riesgo.

### Proposed solution

Un modo global `consensus` activable via `walter-os mode consensus on` o `walter-os mode consensus off`. Se persiste en `~/.config/walter-os/mode.json`:

```json
{
  "consensus": true,
  "since": "2026-05-11T14:00:00Z",
  "voting_threshold": 3
}
```

**Cuando consensus mode está ON**:

Tasks que normalmente requerirían approval humano para tiers `info` o `warn` (lint fixes, dep bumps non-major, doc updates, wiki edits, refactor small, formatting, comment changes, tests-only PRs) pasan a un **Council Vote** automático.

**Voting flow**:
1. Task entra a estado `awaiting-consensus` en Plane.
2. Los 3 agentes más relevantes para la task (selección por tags del Plane issue) son invocados con prompt: "should this task be auto-approved? respond yes/no with 1-sentence reason".
3. Si ≥ 2/3 dicen yes → la task se ejecuta. Si ≤ 1/3 dicen yes → escala a `awaiting-human` con los comments del Council adjuntos.
4. Audit trail explícito: cada consensus-approved action lleva un comment en Plane: `approved by council consensus 3/3 (researcher, reviewer, coder) at <timestamp>. dissent: none.`

**Tasks NUNCA elegibles para consensus** (siempre van a humano sin importar el modo):
- Cualquier operación de tier `critical` del approval-gate (auth, money, PHI, schema changes, prod deploys, security).
- Cualquier categoría de la lista "Bloqueado para TODOS" del ADR-0009.
- Dep bumps major (solo minor y patch son elegibles).
- Cambios a `hooks/`, `AGENTS.md`, `install.sh`, `mcp/servers.json`.

**Cuando consensus mode está OFF (default)**:
- Comportamiento actual: todo lo que requiera approval humano espera al humano.

**Experiencia del operator al volver**:
- `walter-os mode consensus off`
- `walter-os agents summary --since <last-checkin>` → muestra: cuántas tasks aprobó el Council por consenso (links), cuántas esperan approval humano, cuántas fallaron en consensus con links a la discusión.

### Acceptance Criteria

- [AC-1] `walter-os mode consensus on` crea/actualiza `~/.config/walter-os/mode.json` con `consensus: true` y timestamp. `walter-os mode consensus status` lo muestra. `walter-os mode consensus off` revierte.
- [AC-2] En consensus mode, una task de lint fix (tier `info`) en Plane no va a `needs-operator` sino a `awaiting-consensus`. Verificable via dry-run: el runner imprime "entering consensus voting" en lugar de "escalating to operator".
- [AC-3] Con ≥ 2/3 votos yes del Council, la task pasa de `awaiting-consensus` a `ready` (y luego a ejecución). El comment de Plane adjunto incluye los votos individuales con razón.
- [AC-4] Una task de schema migration (prod DB) en consensus mode va directamente a `awaiting-human`, nunca a `awaiting-consensus`. Verificable via `approval-gate.sh check "psql migration" --tool Bash` — retorna block con reason "consensus-ineligible: prod-db-migration".
- [AC-5] `walter-os agents summary --since 2026-05-10` imprime: total tasks auto-aprobadas por consenso, total en awaiting-human, total que fallaron consensus, con links a Plane issues.
- [AC-6] El toggle de consensus mode es visible en Control Tower (Mode Indicator) con indicación del número de tasks auto-aprobadas desde que se activó.

---

## Part B: Control Tower

### Problem statement

El Walter Council opera en la oscuridad desde la perspectiva del operator. Las alertas llegan a Telegram, el estado del sistema está repartido entre Plane, Grafana, el audit log, y el dashboard de LiteLLM. Para saber qué está pasando ahora mismo, el operator tiene que abrir cuatro ventanas distintas. No hay un lugar donde "ver el Council" y "hablar con el Council" sean la misma superficie.

Control Tower es la interfaz operacional del Council: un dashboard web que vive en Walter-VM (Tailscale-only, 1 usuario), que muestra el estado en tiempo real de todos los agentes, las métricas embebidas, los costos, el estado del HA, y las alertas activas — y que además tiene un modo conversacional donde el operator puede pedirle al Council que piense sobre un tema juntos.

### Proposed solution

Una aplicación web Next.js 15 (App Router) desplegada en walter-vm como container Docker. Ver ADR `0008-control-tower-stack.md` para la justificación del stack.

**Módulos visuales**:
- **Agent Status Board**: estado en tiempo real de los 6 agentes (idle/working/blocked + task actual + tiempo en estado). Actualización via WebSocket.
- **Decision Timeline**: log de las decisiones del Council (qué se ejecutó, qué se bloqueó, qué se aprobó) con links a Plane issues y commits.
- **Metrics Dashboard**: paneles Grafana embebidos via iframe (Improvement 1). No se duplica la UI de métricas.
- **Cost Dashboard**: vista del reporte de spend del Improvement 2, con sparklines por agente.
- **HA Status**: estado de walter-vm vs standby homelab node (basado en el spec `standby-node-hetzner-replication.md`). Verde/rojo por servicio.
- **Alert Feed**: alertas activas con su tier (info/warn/critical/panic) y botón de acknowledge.
- **Mode Indicator**: estado del consensus mode (ON/OFF) con toggle y count de tasks auto-aprobadas desde la última activación.

**Módulo conversacional**:
- **Council Chat**: el operator escribe un tema o pregunta. El Council responde en un **flow híbrido de 3 fases**:
  1. **Round 1 — parallel groupthink**: los 6 agentes reciben el prompt del operator y responden de forma independiente, sin ver las respuestas de los demás. Outputs son cortos (≤ 300 tokens cada uno). El objetivo es capturar perspectivas sin contaminación cruzada.
  2. **Round 2 — sequential deliberation**: cada agente recibe las 6 respuestas de Round 1 y produce una respuesta más larga que (a) refina su posición, (b) cita o refuta a otros agentes por nombre, (c) propone trade-offs explícitos. El orden de Round 2 va por trust tier descendente (high → medium → low) para evitar que agentes de baja confianza dominen el discurso temprano.
  3. **Synthesis**: el agente `liaison` lee las 12 respuestas (6 de R1 + 6 de R2) y produce un summary con: posiciones convergentes, disagreements abiertos, recommended path forward, y próximos pasos accionables. El summary incluye un botón "Spin this as spec + plan" que invoca al architect agent.
  No es un chat general-purpose — es específicamente para deliberación estructurada del Council.
- **Ideation Session**: modo de brainstorm asistido. El operator propone una idea, el Council delibera usando el mismo flow de 3 fases, y al final hay un summary + botón "Spin this as spec + plan" que invoca al architect agent para crear el spec formal.
- **Conversation History**: searchable por fecha, topic, y agente.

### Acceptance Criteria

- [AC-1] Control Tower es accesible en `https://tower.${WALTER_DOMAIN}` (Tailscale-only). Sin acceso al tailnet → 403.
- [AC-2] El Agent Status Board se actualiza en ≤ 2 segundos cuando un agente cambia de estado (idle → working). Verificable iniciando un `run-once` y observando el board.
- [AC-3] El Decision Timeline muestra los últimos 50 eventos del audit log con links a Plane funcionando.
- [AC-4] Los paneles Grafana del Improvement 1 son visibles en la sección Metrics sin login adicional (auth via Grafana anonymous embed o API key hardcodeada en el backend).
- [AC-5] El Cost Dashboard muestra el spend de los últimos 7 días por agente en ≤ 3 segundos de carga.
- [AC-6] El HA Status refleja correctamente si walter-vm o standby homelab node están healthy (verde) o degraded (rojo), consultando la misma health check que usa CF Load Balancer.
- [AC-7] En Council Chat, el operator escribe un mensaje y el flow de 3 fases completa en ≤ 90 segundos: Round 1 (6 respuestas ≤ 300 tokens) visible en ≤ 30s; Round 2 (6 respuestas deliberativas en orden de trust tier) visible en ≤ 75s; Synthesis del liaison visible en ≤ 90s. La UI muestra cada fase con un indicador de progreso visible.
- [AC-8] En Ideation Session, al hacer click en "Spin as spec + plan", se crea un Plane issue en `lane:code` con el summary de la sesión como descripción, y el architect agent lo toma en el próximo polling cycle.
- [AC-9] Control Tower arranca en < 5 segundos de cold start (contenedor ya corriendo). No hay dependencia de cold start del contenedor en el happy path.
- [AC-10] Todas las llamadas al Council Chat pasan por LiteLLM (no directo a Anthropic API). Verificable en los logs de LiteLLM.

---

---

## Wiki Normalization (pre-requisite for Phase M)

### Problem statement

Las páginas del wiki crecen sin un esquema de frontmatter consistente. Algunas no tienen `type`, otras tienen `last-modified` como string libre, otras omiten campos requeridos para el cross-agent learning broker (Improvement 4). El broker de lessons usa el frontmatter para filtrar por context — frontmatter roto produce queries incorrectos.

### Proposed solution

Un script `scripts/wiki/normalize-frontmatter.sh` que corre como pre-requisito antes de la fase M. El script recorre `~/sync/wiki/**/*.md`, valida el frontmatter YAML contra `wiki/SCHEMA.md`, y aplica fixes automáticos donde es posible (campos default, type inference por path: `people/*` → `type: person`, `projects/*` → `type: project`). Páginas que no pueden auto-normalizarse se reportan para revisión humana — no se modifican silenciosamente.

El script también se instala como hook para escrituras futuras al wiki (ver Required AGENTS.md amendments más abajo): ninguna escritura al wiki puede ocurrir sin pasar validación de frontmatter.

---

## Required AGENTS.md amendments

El implementer debe agregar el siguiente bloque al `<operator-home>/Projects/walter-os/AGENTS.md` global, en la sección "Universal disciplines", como subsección nueva entre "Wiki integrity" y la siguiente sección existente:

```markdown
### Wiki integrity (mandatory)

- Every write to `~/sync/wiki/**` MUST validate frontmatter YAML against
  `wiki/SCHEMA.md` BEFORE the write. The `wiki-validator.sh` hook enforces this.
- Pages with broken frontmatter are rejected. No silent fixes — the agent
  must repair frontmatter explicitly and re-attempt.
- Cross-links use the `[[page-slug]]` format. Broken links fail the write.
- Type inference is allowed from path (e.g. `people/*` → type: person) but
  must be made explicit in frontmatter, not implicit.
```

Esta amendment es parte de la implementación — no es opcional. Task `T-M-1` en el plan la cubre.

---

## Non-goals

- Voz, wake-word, TTS, STT — eso es Jarvis en standby homelab node, Phase L. Control Tower es texto-only.
- Nuevos MCPs — v2 no agrega ningún MCP al stack.
- Nuevos agentes — los 6 actuales se mantienen. Control Tower puede expandirse para soportar más en v3 si se necesita.
- Auto-merge de PRs — sigue siendo operador-only. El botón no existe en Control Tower.
- Acceso multi-usuario — 1 operador, 1 instancia, sin auth multi-tenant.
- Mobile app — Telegram sigue siendo el canal mobile. Control Tower es desktop browser.
- Alertas a canales distintos de Telegram + email — no se agrega Slack, PagerDuty, ni otros.

## Open questions

- Para el embedding del broker de lessons (Improvement 4): ¿`bge-small-en-v1.5` o `nomic-embed-text`? El primero es más pequeño (33M params); el segundo está ya configurado en LiteLLM como `local-embed` en standby homelab node. Recomendar nomic-embed-text por ya estar deployado, pero requiere que standby homelab node esté up.
- ¿La Ideation Session guarda la transcripción completa en el wiki automáticamente, o solo el summary que el operator aprueba? Recomendar solo-summary por defecto para evitar wiki pollution.

## References

- `docs/specs/multi-agent-autonomy.md` — v1 del Walter Council (base de este spec)
- `docs/specs/homelab-topology.md` — arquitectura de 4 nodos (contexto de dónde corre cada cosa)
- `docs/specs/archive/standby-node-replication.md` — HA status que se muestra en Control Tower
- `docs/decisions/0008-control-tower-stack.md` — ADR de stack de Control Tower
- `docs/decisions/0009-agent-trust-tiers.md` — ADR de trust tiers
- `hooks/approval-gate.sh` — gate que se extiende en Improvements 7 y 8
- `scripts/agents/lib/llm.sh` — LLM invocation que se extiende en Improvement 2
- `scripts/agents/main.sh` — CLI que se extiende con nuevos subcomandos
