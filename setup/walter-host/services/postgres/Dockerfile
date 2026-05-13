# Walter-VM — Postgres 17 with pg_partman + pg_cron
#
# Official postgres:17 image does NOT ship pg_partman or pg_cron.
# Both are required for the DevRel analytics stack (Phase V):
#   - pg_partman: monthly range-partitioned analytics_events table
#   - pg_cron: schedule materialized view refreshes inside Postgres
#
# Refs: docs/specs/devrel-analytics-stack.md (V-prereq-6)
# Refs: docs/operational/phase-v-tools-availability.md (Postgres extensions section)

FROM postgres:17

RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-17-partman \
      postgresql-17-cron \
    && rm -rf /var/lib/apt/lists/*

# Copy custom postgresql.conf additions
# pg_cron MUST be in shared_preload_libraries at server start (not runtime).
COPY postgresql.conf /etc/postgresql/postgresql.conf

# Copy init scripts — executed in alphabetical order on first DB init
COPY migrations/ /docker-entrypoint-initdb.d/

# Expose standard Postgres port (same as base image)
EXPOSE 5432
