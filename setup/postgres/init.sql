-- Walter-OS shared Postgres initialization
-- Creates per-service databases and users on first run.
-- Idempotent: DO $$ blocks guard each CREATE USER/DATABASE.
-- Passwords are NOT set here — bootstrap.sh runs ALTER USER after init
-- to sync passwords from env vars. This avoids mismatch on first boot.
--
-- Refs: setup/SERVICES-INVENTORY.md

-- Forgejo
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'forgejo') THEN
    CREATE USER forgejo;
  END IF;
END
$$;
SELECT 'CREATE DATABASE forgejo OWNER forgejo' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'forgejo')\gexec

-- Infisical
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'infisical') THEN
    CREATE USER infisical;
  END IF;
END
$$;
SELECT 'CREATE DATABASE infisical OWNER infisical' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'infisical')\gexec

-- LiteLLM
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'litellm') THEN
    CREATE USER litellm;
  END IF;
END
$$;
SELECT 'CREATE DATABASE litellm OWNER litellm' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec

-- n8n
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'n8n') THEN
    CREATE USER n8n;
  END IF;
END
$$;
SELECT 'CREATE DATABASE n8n OWNER n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

-- Postiz (devrel profile)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'postiz') THEN
    CREATE USER postiz;
  END IF;
END
$$;
SELECT 'CREATE DATABASE postiz OWNER postiz' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'postiz')\gexec

-- Metabase (marketing core — promoted from devrel profile)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'metabase') THEN
    CREATE USER metabase;
  END IF;
END
$$;
SELECT 'CREATE DATABASE metabase OWNER metabase' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metabase')\gexec

-- PostHog (marketing core)
-- Password synced by bootstrap.sh via ALTER USER posthog PASSWORD '...'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'posthog') THEN
    CREATE USER posthog;
  END IF;
END
$$;
SELECT 'CREATE DATABASE posthog OWNER posthog' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'posthog')\gexec
