# Langfuse operations

Langfuse is the optional Walter-OS profile for LLM traces and evals. Enable it when agent work needs a shared observability surface for prompt changes, model routing, token usage, tool calls, latency, and evaluation datasets. Leave it disabled for hosts that do not need durable AI telemetry.

## Enablement

```bash
cd setup/walter-host/services/langfuse
cp .env.template .env
$EDITOR .env
docker compose --profile langfuse up -d
```

Caddy should route `https://langfuse.${WALTER_DOMAIN}` to `langfuse-web:3000`. The profile intentionally avoids public host ports for Langfuse dependencies; Postgres, ClickHouse, Redis, and object storage are service-local.

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
