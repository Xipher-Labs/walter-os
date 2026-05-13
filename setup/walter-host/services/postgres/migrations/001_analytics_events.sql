-- Walter DevRel Analytics — Phase V schema
-- Migration 001: core tables
--
-- Run by Postgres docker-entrypoint-initdb.d on first container start.
-- Idempotent: uses IF NOT EXISTS throughout.
--
-- Refs: docs/specs/devrel-analytics-stack.md (Decision 4 — Schema)

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ─────────────────────────────────────────────────────────────────────────────
-- content_pieces: catalog of DevRel content published across platforms
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS content_pieces (
  id            TEXT PRIMARY KEY,            -- '<platform>:<external_id>'
  title         TEXT,
  url           TEXT,
  published_at  TIMESTAMPTZ,
  tags          TEXT[],
  hook          TEXT,                         -- first sentence, for hook-pattern analysis
  word_count    INTEGER,
  has_image     BOOLEAN DEFAULT false,
  has_code      BOOLEAN DEFAULT false,
  has_video     BOOLEAN DEFAULT false,
  created_by    TEXT,                         -- 'devrel-writer-agent', 'operator-manual'
  draft_path    TEXT,                         -- link to draft in wiki/devrel/drafts/
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- platform generated column: split_part(id, ':', 1) — e.g. 'twitter:123' → 'twitter'
-- Required by mv_roi_per_content which references cp.platform.
ALTER TABLE content_pieces ADD COLUMN IF NOT EXISTS platform TEXT GENERATED ALWAYS AS (split_part(id, ':', 1)) STORED;

COMMENT ON TABLE content_pieces IS
  'Catalog of DevRel content published across platforms. One row per piece of content.';

-- ─────────────────────────────────────────────────────────────────────────────
-- analytics_events: append-only engagement metrics, partitioned by month
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics_events (
  id            BIGSERIAL,
  occurred_at   TIMESTAMPTZ NOT NULL,
  ingested_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  platform      TEXT NOT NULL,               -- 'twitter', 'youtube', 'plausible', 'github', 'bluesky'
  content_id    TEXT NOT NULL,               -- tweet ID, video ID, slug, repo name
  event_type    TEXT NOT NULL,               -- 'impression', 'engagement', 'click', 'conversion', 'view', 'star'
  metric_value  NUMERIC NOT NULL,
  metadata      JSONB,
  PRIMARY KEY (id, occurred_at),
  UNIQUE (platform, content_id, event_type, occurred_at)
) PARTITION BY RANGE (occurred_at);

COMMENT ON TABLE analytics_events IS
  'Append-only engagement metrics ingested from all platforms. '
  'Partitioned monthly via pg_partman. Do not UPDATE or DELETE rows.';

-- Seed the partition maintenance with pg_partman
-- Creates monthly partitions (2 ahead by default) and manages historical ones.
SELECT partman.create_parent(
  p_parent_table := 'public.analytics_events',
  p_control      := 'occurred_at',
  p_interval     := 'monthly',
  p_premake      := 3
);

-- ─────────────────────────────────────────────────────────────────────────────
-- ad_spend_events: ad platform spend ingested via Singer taps
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ad_spend_events (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL,
  platform      TEXT NOT NULL,               -- 'google', 'meta', 'x', 'youtube'
  campaign_id   TEXT NOT NULL,
  ad_group_id   TEXT,
  ad_id         TEXT NOT NULL,
  spend_usd     NUMERIC NOT NULL,
  impressions   INTEGER,
  clicks        INTEGER,
  conversions   INTEGER,
  metadata      JSONB,
  ingested_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (platform, ad_id, occurred_at)
);

COMMENT ON TABLE ad_spend_events IS
  'Ad spend ingested via Singer taps (tap-google-ads, tap-facebook). '
  'One row per ad per day. Joined with analytics_events for ROI analysis.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
-- analytics_events: most queries filter by platform + occurred_at range
CREATE INDEX IF NOT EXISTS analytics_events_platform_occurred
  ON analytics_events (platform, occurred_at DESC);

CREATE INDEX IF NOT EXISTS analytics_events_content_id
  ON analytics_events (content_id, occurred_at DESC);

-- ad_spend: queries join by campaign + date range
CREATE INDEX IF NOT EXISTS ad_spend_campaign_occurred
  ON ad_spend_events (campaign_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS ad_spend_platform_occurred
  ON ad_spend_events (platform, occurred_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- Automatic updated_at for content_pieces
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS content_pieces_updated_at ON content_pieces;
CREATE TRIGGER content_pieces_updated_at
  BEFORE UPDATE ON content_pieces
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
