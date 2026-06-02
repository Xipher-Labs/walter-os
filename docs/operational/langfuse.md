# Langfuse operations

Langfuse is the optional Walter-OS profile for LLM traces and evals. Enable it when agent work needs a shared observability surface for prompt changes, model routing, token usage, tool calls, latency, and evaluation datasets. Leave it disabled for hosts that do not need durable AI telemetry.

## Enablement

```bash
cd setup/walter-host/services/langfuse
cp .env.template .env
$EDITOR .env
docker compose --profile langfuse up -d
```

Caddy should route `https://langfuse.${WALTER_DOMAIN}` to
`localhost:${LANGFUSE_HOST_PORT:-3011}`. The profile exposes only the Langfuse
UI on loopback; Postgres, ClickHouse, Redis, and object storage stay
service-local.

## Emitting traces

Starting the profile only creates the Langfuse app. To send Walter-Bridge /
LiteLLM traffic into it, create a Langfuse project and load its keys into the
LiteLLM environment:

```text
LANGFUSE_PUBLIC_KEY=<project public key>
LANGFUSE_SECRET_KEY=<project secret key>
LANGFUSE_HOST=https://langfuse.${WALTER_DOMAIN}
```

Then enable LiteLLM callbacks in the LiteLLM config:

```yaml
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
```

For containers on the same Docker network, `LANGFUSE_HOST` may point at the
internal service URL instead of the public Caddy route. Treat trace payloads as
retained telemetry: prompts, completions, tool inputs, and metadata may include
customer or operator data.

Before enabling callbacks broadly, decide what must be masked or excluded.
Redact secrets, auth headers, customer identifiers, and long tool payloads
before they reach LiteLLM metadata. Disable Langfuse callbacks entirely for
routes handling PHI, legal-privileged material, or any workflow the operator
marks local-only.

## Operational fit

Use Langfuse for startup and team workflows where trace review and eval history matter:

- debugging failed agent runs from the exact trace rather than local logs;
- comparing prompt, model, or tool changes against eval datasets;
- reviewing cost, latency, and error trends before shipping AI workflow changes;
- giving product and engineering a common view of LLM behavior.

Keep it optional because the storage footprint can grow faster than typical app logs. Langfuse v3 stores relational metadata in Postgres, high-volume trace events in ClickHouse, queue/cache data in Redis, and payloads or exports in S3-compatible object storage. That means more backup work, more retention decisions, and more secrets to rotate.

## Backup checklist

Back up these named volumes as a set:

```text
langfuse_postgres_data
langfuse_clickhouse_data
langfuse_clickhouse_logs
langfuse_redis_data
langfuse_minio_data
```

Before enabling broad tracing, define retention for traces, eval datasets, media uploads, and batch exports. Restores should be tested with Postgres, ClickHouse, and object storage together; partial restores can leave trace lists, eval records, or attachments inconsistent.
