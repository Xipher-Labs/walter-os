---
name: data-migration-safety
description: Review database migrations and schema changes for safety — reversibility, lock duration, online-vs-offline behavior, batch-size on backfills, tenant isolation, RLS policies (Supabase), idempotence, audit-log impact. Use this skill on any PR that touches `migrations/*`, `supabase/migrations/*`, `*.sql`, schema files (Drizzle/Prisma/SQLAlchemy), or that adds/modifies columns, indexes, constraints, RLS policies. Critical for [Project A] (procurement audit trail) and [Project B] (PHI integrity). A bad migration on staging = postmortem; on production = incident.
---

# Data Migration Safety

Schema changes are among the highest-risk operations a team does. They're
slow to roll back, can lock tables for minutes, and migrations applied to
prod without testing have ended companies. This skill reviews migrations
before they ship and refuses ones that fail the safety checklist.

## Auto-trigger criteria

Files: `migrations/*.sql`, `supabase/migrations/*.sql`,
`*.surrealql`, `prisma/schema.prisma`, `drizzle/**/*.ts`,
`alembic/versions/*.py`, `db/migrate/*.rb`, anything matching
`*migration*` in path.

Also: any `CREATE TABLE`, `ALTER TABLE`, `DROP`, `CREATE INDEX`,
`CREATE POLICY` in a SQL file.

## The safety checklist (every migration)

### 1. Reversibility

Every migration has an `up` AND a `down`. Without `down`:

- BLOCKER for staging.
- Even harder rule for production (Argentine financial audits expect
  reversibility evidence).

`down` should leave the database in the state it was BEFORE `up` ran.
Test it:
```bash
# Apply
db migrate up
# Snapshot
pg_dump > after-up.sql
# Reverse
db migrate down
# Re-apply
db migrate up
# Compare
pg_dump > after-up-2.sql
diff after-up.sql after-up-2.sql  # should be empty
```

Exceptions where `down` legitimately can't restore: data deletions,
column drops with information loss. In those cases, the `down` MUST
recreate the column type/constraint, with a comment documenting the
data loss.

### 2. Lock duration

PostgreSQL takes various locks. Most ALTERs take **ACCESS EXCLUSIVE**
which blocks reads AND writes. Long ones = downtime.

Worst offenders (need extra care):
- `ALTER TABLE ... ADD COLUMN <type> NOT NULL DEFAULT <value>` — pre-PG11
  rewrites the entire table. PG11+ is fast for static defaults but
  still slow for volatile defaults.
- `ALTER TABLE ... ALTER COLUMN <c> TYPE <t>` — usually rewrites.
- `ADD CONSTRAINT NOT NULL` — full table scan to validate.
- `CREATE INDEX` (without `CONCURRENTLY`) — blocks writes on the table.
- `VACUUM FULL` — exclusive lock + rewrite.
- `REINDEX` (without `CONCURRENTLY`, PG12+) — exclusive lock.

Safe patterns:

```sql
-- BAD: blocks the world for the duration
ALTER TABLE bids ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';

-- GOOD: split into 3 migrations
-- M1: add nullable column
ALTER TABLE bids ADD COLUMN status TEXT;
-- (deploy code that writes both old + new)
-- M2: backfill in batches (separate script, not migration)
-- M3: set NOT NULL after backfill complete
ALTER TABLE bids ALTER COLUMN status SET NOT NULL;
```

```sql
-- BAD: blocks writes
CREATE INDEX idx_bids_user_id ON bids(user_id);

-- GOOD: doesn't block writes (PG12+)
CREATE INDEX CONCURRENTLY idx_bids_user_id ON bids(user_id);
-- Note: CREATE INDEX CONCURRENTLY can't run inside a transaction.
-- Migration runner must support running this outside one.
```

For Supabase specifically: their migration runner wraps each file in a
transaction by default. `CONCURRENTLY` requires a separate file or the
`-- supabase no-tx` directive (verify in current docs).

### 3. Online vs offline migrations

For tables with > 1M rows in production:

- Estimate time on staging with similar size before applying to prod.
- Document: "Expected duration on prod: ~X seconds. Lock taken: ACCESS
  EXCLUSIVE. Application impact: Y."
- If duration > 5s: schedule maintenance window OR redesign as online
  migration (split into reversible non-blocking steps).

### 4. Backfill batching

Backfilling existing rows (e.g., populating a new column) should NEVER
be in the migration itself for tables > 100k rows.

Pattern:
```sql
-- Migration: just add the column nullable
ALTER TABLE users ADD COLUMN normalized_email TEXT;

-- Separate script (not migration), run once or as background job:
DO $$
DECLARE batch_size INT := 5000;
DECLARE last_id BIGINT := 0;
DECLARE rows_updated INT;
BEGIN
  LOOP
    UPDATE users
    SET normalized_email = lower(trim(email))
    WHERE id > last_id
      AND id <= last_id + batch_size
      AND normalized_email IS NULL;
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    last_id := last_id + batch_size;
    EXIT WHEN rows_updated = 0;
    PERFORM pg_sleep(0.1);  -- breathing room
  END LOOP;
END $$;
```

### 5. Idempotence

A migration should be re-runnable safely. Use `IF NOT EXISTS` /
`IF EXISTS`:

```sql
CREATE TABLE IF NOT EXISTS audit_log ( ... );
ALTER TABLE bids ADD COLUMN IF NOT EXISTS status TEXT;
DROP INDEX IF EXISTS idx_old;
```

Rationale: if a migration partially completes (network blip, timeout),
re-running shouldn't error.

### 6. Foreign keys and constraints

Adding a foreign key to a non-empty table:
```sql
-- BAD: blocks + validates all existing rows
ALTER TABLE bids ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);

-- GOOD: add NOT VALID first (instant), validate later (concurrent)
ALTER TABLE bids ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID;
-- Later, separate transaction:
ALTER TABLE bids VALIDATE CONSTRAINT fk_user;
```

### 7. Supabase RLS specifically

For any new table or policy change in Supabase:

- **RLS enabled by default**: `ALTER TABLE x ENABLE ROW LEVEL SECURITY;`.
  A new table without RLS is a leak waiting to happen.
- **Default deny**: no policy = no access. Each policy explicitly grants.
- **Per-operation policies**: separate `SELECT`, `INSERT`, `UPDATE`,
  `DELETE` policies. Don't bundle.
- **Anon vs authenticated**: think about both roles. Anon should access
  almost nothing.
- **Test cross-tenant access**: prove with a test that user A cannot
  read/write user B's data.
- **Service role bypasses RLS**: any code path that uses the service
  role bypasses ALL policies. Audit those paths separately.

Migration test pattern:
```sql
-- After applying RLS policies, prove they work:
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "user-A-id"}';
SELECT * FROM bids;  -- should only return user-A's bids, never user-B's
```

### 8. Sensitive data implications

For [Project A] (procurement audit trail):
- Audit log entries are append-only — `UPDATE` and `DELETE` blocked at
  the policy level.
- Tender history immutable once awarded.
- Any migration that could lose audit information is BLOCKER without
  explicit operator + counsel sign-off (Argentine ley 13.064 audit
  requirements).

For [Project B] (PHI):
- See `medical-data-compliance` skill for PHI rules. Migrations touching
  PHI tables: CRITICAL severity for any rule violation.
- Encryption-at-rest columns can't be silently re-keyed without a
  documented key-rotation plan.
- Patient consent tables: deletion requires retention-policy check
  (some statutes require minimum retention).

### 9. Index changes

- Drop indexes during low-traffic window (or `CONCURRENTLY`).
- Adding indexes: always `CONCURRENTLY` for prod-sized tables.
- Document the query the index serves; without that, future devs delete
  it as "unused" and a slow query reappears in production.

### 10. Naming and schema hygiene

- Migration file names: `<timestamp>_<verb>_<noun>.sql` (Supabase
  convention).
- Tables: snake_case. Plural (`bids`, not `bid`).
- Columns: snake_case. Foreign keys: `<table_singular>_id` (`user_id`).
- Indexes: `idx_<table>_<columns>` (so future devs know what's indexed).
- Constraints: `<type>_<table>_<columns>` (`fk_bids_user_id`,
  `chk_users_age`).

## Output format

```
**[BLOCKING|WARN|NIT] [DM-N] <one-liner>**

Where: `migrations/20260503_add_status.sql:5-12`
Class: <reversibility | locking | online-migration | backfill |
       idempotence | RLS | sensitive-data>
Risk: <impact: downtime / data loss / RLS bypass / etc.>
Estimated impact: <duration estimate, blast radius, blocking?>
Fix: <specific change with code if it fits>
Test: <command to validate the fix locally>
```

Severity:
- **BLOCKING**: would cause data loss, prolonged outage, RLS bypass, or
  audit-log corruption. Must fix.
- **WARN**: best-practice gap (no `IF EXISTS`, missing `down`, no
  estimate documented).
- **NIT**: naming, ordering, comments.

## Pre-merge checklist (paste in PR)

- [ ] Migration has `up` AND `down` (or documented why `down` can't
      restore).
- [ ] Tested against staging dataset of representative size.
- [ ] No `ACCESS EXCLUSIVE` lock for > 5 seconds in worst case.
- [ ] Backfills are batched (separate script for >100k rows).
- [ ] `IF EXISTS` / `IF NOT EXISTS` for re-runnability.
- [ ] Foreign keys added with `NOT VALID` then `VALIDATE`.
- [ ] Indexes added `CONCURRENTLY`.
- [ ] If new table on Supabase: RLS enabled + per-operation policies.
- [ ] If touching PHI ([Project B]): `medical-data-compliance` reviewed.
- [ ] If touching audit log ([Project A]): operator + counsel signed off.
- [ ] Naming follows project conventions.
- [ ] Estimated duration on prod documented in PR.

## Tooling

- **`squawk`** — opinionated PG migration linter. Catches lock-heavy
  ALTERs.
- **`migra`** — diff schema between two databases. Useful for verifying
  `up` + `down` round-trip.
- **Supabase CLI** — `supabase db diff` and `supabase db reset` for
  local validation.
- **`pg_dump | wc -l`** before and after on staging.

## Hard rules

- **No production migration without staging dry-run.** Ever.
- **No migration applied during peak traffic.** Schedule.
- **No DROP TABLE without explicit operator confirmation in chat for
  THAT table.** This skill blocks `DROP TABLE` automatically; operator
  must override with reason.
- **No data backfill in the migration file** for tables > 100k rows.
  Separate script, run as job.
- **No silent column type changes** that could lose data (e.g., `bigint
  -> int`, `text -> varchar(N)`).

## What this skill does NOT cover

- Application code that uses the new schema (use `pr-review` +
  framework-specific lint).
- Long-term query performance (use a query analyzer, not this skill).
- ETL / data warehouse migrations (different patterns, often offline).
- NoSQL schema changes (different beast — though some principles apply).

## References

- "Zero downtime migrations in PostgreSQL" — Strong DM blog
- "Common DB schema change mistakes" — GoCardless engineering blog
- Squawk's rule documentation
- Supabase RLS deep-dive in their docs
