# 0009. Agent Trust Tiers

**Date**: 2026-05-11
**Status**: Proposed

## Context

El `approval-gate.sh` (spec §7, `docs/specs/multi-agent-autonomy.md`) es hoy binario: o se bloquea una operación y se escala al operator, o se permite. No hay distinción de riesgo por agente.

Los 6 agentes del Council tienen perfiles de riesgo muy distintos:

| Agente | Qué hace | Blast radius |
|---|---|---|
| **triage** | Clasifica eventos, crea issues en Plane | Mínimo — solo escribe issues, no toca código ni infra |
| **researcher** | Lee web, ingesta wiki, crea páginas de wiki | Bajo — el wiki es privado y reversible |
| **coder** | Escribe código en feature/*, abre PRs | Medio — PRs son visibles, diff es reversible, no puede mergear |
| **reviewer** | Lee diffs, postea review comments | Bajo — read-only sobre código; write sobre PR comments |
| **janitor** | Lint, dep bumps, stale-PR sweep, DR drill | Medio-alto — puede tocar archivos de configuración, puede abrir PRs con cambios que parecen mecánicos pero tienen impacto |
| **liaison** | Lee actividad del Council, escribe digest | Bajo — no toca código, no toca infra, solo lee y escribe texto |

Con un approval-gate binario, el operator recibe el mismo nivel de ruido (aprobaciones manuales) para el reviewer leyendo un diff que para el janitor haciendo un `rm` de archivos temporales. Esto erosiona la atención del operator en los bloqueos que realmente importan.

El objetivo de los trust tiers es **reducir el ruido en aprobaciones de bajo riesgo sin debilitar las protecciones en operaciones de alto riesgo**. El trust tier NO reemplaza el approval-gate — lo complementa con un filtro de "¿este agente, para esta categoría de operación, merece una standing approval implícita?".

## Decision

Definimos tres tiers — `low`, `medium`, `high` — y los asignamos a los 6 agentes. La tabla de trust define qué categorías del approval-gate (§7.1 del spec de autonomía) se auto-aprueban por tier:

### Tier assignments

| Agente | Trust Tier | Justificación |
|---|---|---|
| triage | `medium` | Crea issues (write a Plane) pero nunca toca código ni infra. No destructivo por naturaleza. |
| researcher | `medium` | Escribe wiki (texto privado, reversible con git). Nunca toca código fuente. |
| coder | `medium` | Escribe código en feature/* y abre PRs. No puede mergear. El blast radius está contenido al branch. |
| reviewer | `high` | Read-only sobre código. Write solo sobre PR comments y review approvals. El daño máximo que puede hacer es aprobar un PR malo — y el merge sigue siendo operador-only. |
| janitor | `low` | Toca archivos de configuración, puede hacer rm de archivos "temporales" (que pueden no serlo), hace dep bumps que rompen builds. El nombre "janitor" suena inocuo pero el blast radius real es medio-alto. |
| liaison | `low` | El liaison tiene la mayor superficie de exfiltración de todos los agentes: escribe summaries hacia canales externos (Telegram, email drafts, status reports). Un compromise del liaison es estratégicamente peor que un compromise del coder — el coder solo puede pushear código a un feature branch, mientras que el liaison puede filtrar síntesis completa de la actividad del Council hacia canales no controlados. Por eso `low` trust requiere approval explícita del operator para cualquier output que salga del homelab. La baja autonomía operacional es el precio por el alto privilegio de información. |

### Override table by tier

Las categorías vienen del §7.1 del spec de autonomía. Los tiers definen un conjunto de **auto-allow overrides** — categorías que el tier puede ejecutar sin label `approved-by-operator`:

**Tier `high` — auto-allows** (además de todo lo que `medium` permite):
- `git-push-feature-branch` — push a `feature/*` (NO a main/staging/release)
- `gh-pr-create` — abrir PRs (no merge)
- `gh-pr-comment` — comentar en PRs
- `gh-pr-review-approve` — aprobar un PR (el merge sigue siendo operador-only)
- `read-any-file` — lectura de cualquier archivo (siempre permitido para todos, pero high lo tiene explícito)
- `run-tests-linters` — ejecutar tests, linters, formatters

**Tier `medium` — auto-allows** (además de todo lo que `low` permite):
- `git-push-feature-branch` — push a `feature/*`
- `gh-pr-create` — abrir PRs
- `gh-pr-comment` — comentar en PRs
- `run-tests-linters` — tests y linters
- `write-source-files-feature-branch` — editar código fuente en feature/* (no en main/staging)
- `write-wiki-pages` — crear/editar páginas del wiki privado
- `create-plane-issue` — crear issues en Plane

**Tier `low` — auto-allows** (base mínima):
- `read-any-file`
- `run-tests-linters`
- `gh-pr-comment`
- `create-plane-issue`

**Bloqueado para TODOS los tiers** (ni siquiera `high` puede auto-aprobar):
- `push-to-main-staging-release` — push a branches protegidas
- `gh-pr-merge` — merge de PRs
- `force-push-any-branch` — force push
- `modify-hooks` — editar hooks/, AGENTS.md, install.sh, mcp/servers.json
- `modify-agent-definitions` — editar agents/*.md o skills/*/SKILL.md
- `destructive-shell` — rm -rf, dd, mkfs, truncate
- `sql-destructive` — DROP, TRUNCATE, DELETE FROM
- `http-delete-managed-services` — DELETE en Hetzner, CF, Stripe, Forgejo, Vercel
- `money-spending` — cualquier provisioning o gasto
- `public-communication` — tweets, blog posts, emails enviados
- `auth-crypto-phi-files` — auth/*, crypto/*, [Project B]/*, *.key, *.pem
- `env-file-writes` — cualquier *.env*
- `production-db-migrations` — migraciones contra staging o prod

### Persistence

El trust tier de cada agente vive en `~/.config/walter-os/trust-tiers.yml`:

```yaml
agents:
  triage:
    tier: medium
    overrides: {}     # empty = use tier defaults

  researcher:
    tier: medium
    overrides: {}

  coder:
    tier: medium
    overrides: {}

  reviewer:
    tier: high
    overrides: {}

  janitor:
    tier: low
    overrides:
      write-wiki-pages: allow    # janitor puede limpiar el wiki

  liaison:
    tier: low
    overrides:
      write-wiki-pages: allow    # liaison puede escribir digests al wiki interno
```

El campo `overrides` permite ajustes por agente sin cambiar el tier. Un override `allow` sobre una categoría normalmente bloqueada-por-tier la permite; un override `block` sobre una categoría normalmente permitida-por-tier la bloquea. Los overrides NO pueden desbloquear la lista "Bloqueado para TODOS" — esa lista es hardcoded en `approval-gate.sh`.

### Hot-reload

`approval-gate.sh` es un proceso de corta duración (se invoca por PreToolUse hook, no es un daemon). Por lo tanto, lee `trust-tiers.yml` en cada invocación. Cambios al archivo tienen efecto inmediato sin reinicio.

## Consequences

**Lo que se hace más fácil**:
- El reviewer puede trabajar sin requerir aprobaciones para operaciones que ya son su función normal (push a feature/*, abrir PRs). El operator recibe menos interrupciones.
- El modelo de trust es auditable: un YAML legible que el operator puede revisar y modificar.
- Los overrides permiten ajustar trust a nivel de agente individual sin rediseñar el sistema de tiers.
- La lista "bloqueado para todos" mantiene las garantías de seguridad intactas independientemente de los tiers.

**Lo que se hace más difícil**:
- El janitor con tier `low` puede necesitar más aprobaciones manuales que antes. Si el operator agrega `write-source-files-feature-branch: allow` en el override del janitor, reduce el ruido pero aumenta el riesgo de que el janitor modifique archivos fuera de su rol esperado.
- La tabla override puede crecer a lo largo del tiempo y convertirse en un sistema complejo de excepciones. Mitigación: revisión trimestral del janitor agent (ya contemplado en el spec de autonomía §7.5).

**Riesgos aceptados**:
- Tier `high` del reviewer le permite push a feature/* sin aprobación. Si el reviewer tiene un bug que lo hace escribir código en lugar de solo revisar (un escenario improbable dado su system prompt, pero no imposible), puede pushear código a un branch del operator. El riesgo es bajo porque: (a) el reviewer no tiene acceso de merge, (b) el PR sigue siendo review-by-operator antes de merge, (c) el audit log registra todos los pushes.
- Los tiers son estáticos (no aprenden con el tiempo). No hay mecanismo de downgrade automático de trust si un agente hace algo malo. Downgrade es una acción manual del operator via edición del YAML. Esto es intencional — el trust debe ser una decisión consciente del operator, no un output de un algoritmo.

## Alternatives considered

**Trust basado en historial de comportamiento (dinámico)**:
- Idea: el trust tier sube automáticamente cuando el agente completa N tasks sin incidentes; baja cuando hay un bloqueo del approval-gate.
- Rechazado: introduce un loop de feedback que puede ser explotado (agente hace muchas tasks simples para subir trust, luego ejecuta la operación riesgosa). El trust debe ser una propiedad declarativa del rol del agente, no un producto de su comportamiento pasado. Los humanos asignamos roles, no los dejamos emerger.

**Trust por operación individual (no por tier)**:
- Idea: cada agente tiene una lista explícita de operaciones permitidas, sin noción de tier.
- Rechazado: demasiado granular para mantener. Con 6 agentes y 14 categorías, son hasta 84 combinaciones. El tier colapsa esto a 3 defaults + overrides por excepción. La complejidad extra no justifica la granularidad.

**Trust delegado al Plane issue**:
- Idea: el nivel de trust de una operación se determina por los labels del Plane issue (e.g., `trust:high` en el issue le da al agente más permisos para esa tarea).
- Rechazado: este mecanismo ya existe (el label `approved-by-operator`). El trust tier es un complemento orthogonal — define el rol del agente independientemente de la tarea específica. Mezclar ambos crea ambigüedad sobre qué tiene precedencia.

**Sin tiers, solo ampliar las standing approvals**:
- Idea: usar el mecanismo de standing approvals existente (§7.5 del spec de autonomía) en lugar de agregar una nueva abstracción.
- Rechazado: las standing approvals son globales (se aplican a todos los agentes). No hay forma de decir "standing approval de push a feature/* solo para el reviewer". Los tiers resuelven exactamente este problema de scoping por agente.
