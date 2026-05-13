---
name: postgres-cli
description: Query and inspect PostgreSQL databases via the `psql` CLI for [Project A]/[Project B]/[Company] data needs. Use this skill whenever the user asks to "query the DB", "check schema", "run migrations", "inspect rows", "explain query", or anything that touches a Postgres connection. Replaces low-trust community Postgres MCPs. Stack-aware for Supabase, self-hosted Postgres, and cloud variants.
---

# Postgres CLI (`psql`)

Direct database access via the official Postgres client. Replaces unmaintained
community MCPs (low-star, single-maintainer) which were our weakest links.
Mature, multi-decade-stable tooling, available everywhere.

## Setup

```bash
# Already in setup/Brewfile:
brew install postgresql@16   # provides psql + pg_dump + pg_restore

# Verify
psql --version
```

Connection strings live in **Infisical** (project-scoped) or
`~/.config/walter-os/secrets.env` (operator-local). NEVER hardcode in
scripts.

```bash
# From Infisical (preferred for runtime)
DATABASE_URL=$(infisical secrets get DATABASE_URL --raw --project [project-a]-staging)

# From walter-os env (operator interactive use)
source ~/.config/walter-os/secrets.env
psql "$DATABASE_URL"
```

## Common operations

### Connect

```bash
psql "$DATABASE_URL"            # interactive shell
psql "$DATABASE_URL" -c '\dt'   # one-shot command
psql "$DATABASE_URL" -f script.sql
```

### Inspect schema

```sql
\dt                              -- list tables
\dt+                             -- with sizes
\d users                         -- describe a table
\d+ users                        -- with comments + storage
\df                              -- list functions
\du                              -- list roles
\l                               -- list databases
\dn                              -- list schemas
\dx                              -- list extensions
```

### Query patterns

```bash
# Top 10 rows of a table (cleanly formatted)
psql "$DATABASE_URL" -P pager=off -c "SELECT * FROM bids ORDER BY created_at DESC LIMIT 10;"

# Row count of every table (great for pre-migration sanity)
psql "$DATABASE_URL" -At -c "
  SELECT schemaname || '.' || tablename AS table,
         (xpath('/row/c/text()', xml_count))[1]::text::int AS rows
  FROM (SELECT schemaname, tablename,
          query_to_xml('SELECT count(*) AS c FROM ' || schemaname || '.' || tablename, true, true, '') AS xml_count
        FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')) t;
"

# Slow queries (last hour, requires pg_stat_statements)
psql "$DATABASE_URL" -c "
  SELECT round(total_exec_time::numeric, 2) AS total_ms,
         calls, query
  FROM pg_stat_statements
  ORDER BY total_exec_time DESC
  LIMIT 10;"

# Live connections
psql "$DATABASE_URL" -c "
  SELECT pid, usename, application_name, client_addr,
         state, query_start, NOW() - query_start AS duration
  FROM pg_stat_activity
  WHERE state != 'idle'
  ORDER BY query_start;"

# Index usage
psql "$DATABASE_URL" -c "
  SELECT schemaname, tablename, indexname,
         idx_scan AS scans, idx_tup_read AS reads
  FROM pg_stat_user_indexes
  ORDER BY idx_scan DESC LIMIT 20;"
```

### EXPLAIN before any query you'd run on prod

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) SELECT ...;
```

If it's a write you'd run interactively, wrap it:

```sql
BEGIN;
EXPLAIN ANALYZE UPDATE bids SET status = 'awarded' WHERE id = 42;
-- inspect plan, decide
ROLLBACK;   -- or COMMIT if it looked right
```

## Backups

### Logical (text/SQL) — small DBs

```bash
# Full DB
pg_dump "$DATABASE_URL" --format=plain --no-owner --no-acl > [project-a]-backup-$(date +%F).sql

# Specific tables
pg_dump "$DATABASE_URL" --table=public.bids --table=public.tenders > partial.sql

# Custom format (faster, parallelizable, restore-by-table)
pg_dump "$DATABASE_URL" --format=custom --jobs=4 -f [project-a]-$(date +%F).dump
```

### Binary (faster, for prod)

Better via Postgres' own `pg_basebackup` over replication for prod-grade.
Outside scope of this skill.

### Restic integration (Walter-VM Phase K)

```bash
# Daily encrypted backup to Drive (operator cloud storage)
pg_dump "$DATABASE_URL" --format=custom \
  | restic -r rclone:gdrive:walter-vm-backup backup --stdin \
      --stdin-filename "[project-a]-$(date +%F).dump"
```

## Migrations

For project work, prefer the project's migration tool (Drizzle Kit,
Prisma migrate, alembic, sqitch, etc). Direct psql migrations are for:

- Hotfix patches between formal migrations
- Inspection/debugging
- One-off data corrections (with backup + transaction)

Pattern:

```bash
psql "$DATABASE_URL" <<'SQL'
BEGIN;

-- Run forward changes
ALTER TABLE bids ADD COLUMN sealed_at TIMESTAMPTZ;
UPDATE bids SET sealed_at = created_at WHERE sealed_at IS NULL;

-- Verify
\d bids
SELECT count(*) FROM bids WHERE sealed_at IS NULL;  -- should be 0

-- COMMIT only if everything looks right
ROLLBACK;  -- replace with COMMIT after inspection
SQL
```

For real migrations: see `data-migration-safety` skill (covers locks,
backfilling, idempotence, RLS).

## Per-project conventions (operator-specific)

### [Project A] (Supabase, multi-tenant)

```bash
# Staging (read-write OK during dev)
PROJECT_A_STAGING_DB="postgresql://postgres.PROJECT-REF:PASSWORD@aws-0-us-east-2.pooler.supabase.com:6543/postgres"

# Production (READ ONLY by default — append ?options=-c%20default_transaction_read_only=on)
PROJECT_A_PROD_DB="${PROJECT_A_PROD_DB_BASE}?options=-c%20default_transaction_read_only=on"
```

Common [Project A] queries:

```sql
-- Tenders due in next 7 days
SELECT id, title, deadline, organization_id
FROM tenders
WHERE deadline BETWEEN NOW() AND NOW() + INTERVAL '7 days'
  AND status = 'open'
ORDER BY deadline;

-- Audit log integrity check (no gaps in sequence)
SELECT MIN(seq), MAX(seq), COUNT(*), MAX(seq) - MIN(seq) + 1 AS expected,
       (MAX(seq) - MIN(seq) + 1) - COUNT(*) AS missing_count
FROM audit_log;
```

### [Project B] (PHI — strict rules)

```sql
-- ALWAYS in read-only transaction, ALWAYS scoped to test data
SET default_transaction_read_only = on;
SET search_path = bv_synthetic;  -- never bv_production from CLI
```

**Never query `bv_production` from psql interactively.** All PHI access goes
through the audited application path (`bv_audit_log` row written for each
read). Direct DB access is for schema inspection and synthetic data only.
This rule is enforced by `medical-data-compliance` skill — a violation is
CRITICAL.

### [Company] (analytics on RPC metrics)

```sql
-- p99 latency per method last 24h
SELECT method,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_ms) AS p99,
       count(*) AS calls
FROM rpc_log
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY method
ORDER BY p99 DESC LIMIT 20;
```

## Hard rules

- **Never run UPDATE/DELETE without WHERE clause.** psql doesn't gate this.
  Use a transaction (BEGIN; ... ROLLBACK;) to test first.
- **Never connect to prod DB from local for write operations.**
  Production writes go through the application + migrations only.
- **Never paste DATABASE_URL into chat/Slack/etc.** Even partial. The
  password is in the URL.
- **Never run pg_dump on a hot prod DB during peak.** Use a read replica
  or off-hours window.
- **For [Project B] production**: psql is restricted by the
  `medical-data-compliance` skill. Don't connect.

## Useful flags

| Flag | What |
|---|---|
| `-At` | Tab-separated, no headers (script-friendly) |
| `-c "SQL"` | One-shot command |
| `-f script.sql` | Run from file |
| `-X` | Skip `~/.psqlrc` (clean env, useful for scripts) |
| `-q` | Quiet (less noise) |
| `-1` / `--single-transaction` | Wrap entire `-f` script in BEGIN/COMMIT |
| `-v ON_ERROR_STOP=1` | Bail on first error |
| `-e` | Echo executed commands |
| `-L log.txt` | Save full session to log |
| `\timing` | Show query duration interactively |
| `\watch 5` | Re-run last query every 5s (useful for monitoring) |

## Configuration tips

`~/.psqlrc`:

```sql
\set QUIET 1
\pset null '∅'
\pset linestyle unicode
\pset border 2
\timing
\set HISTSIZE 10000
\set HISTFILE ~/.psql_history- :DBNAME
\set ON_ERROR_ROLLBACK interactive
\set VERBOSITY default
\unset QUIET
```

Per-database history (different DB → different history file).
`ON_ERROR_ROLLBACK interactive` means in a transaction, an error doesn't
abort the whole transaction — you can keep going from the savepoint.

## Why CLI instead of MCP

- `psql` is decades-mature, ships with Postgres, available on every system.
- Best community MCPs we found: 7 GitHub stars, single maintainer.
  Trusting them with DB access is a security risk (a malicious update
  could exfiltrate the DATABASE_URL or worse).
- All operations are scriptable from Bash — agent uses Bash tool, runs
  psql, parses output. Same UX, more reliable.
- pg_dump/pg_restore in same toolchain, MCPs don't cover backups.

## Integration with other skills

- `data-migration-safety` — review schema changes before applying via
  psql + migration tool.
- `medical-data-compliance` — enforces no-prod-PHI-access for [Project B].
- `web-security-baseline` — checks for SQL injection patterns when
  reviewing app code that constructs queries.

## What this skill does NOT cover

- Production migrations (use Drizzle/Prisma/Alembic via migration tool).
- DB monitoring dashboards (Grafana / pg_stat).
- Backup orchestration (use restic + cron via Walter-VM).
- DB design / schema modeling (use ER tooling — DrawSQL, Eraser).
