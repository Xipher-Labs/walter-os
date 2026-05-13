-- Walter DevRel Analytics — Phase V schema
-- Migration 002: materialized views for fast analyst queries
--
-- These views are the read layer for the devrel-analyst skill.
-- Refreshed by pg_cron jobs defined at bottom of this file.
--
-- Refs: docs/specs/devrel-analytics-stack.md (Decision 4 — Schema)

-- ─────────────────────────────────────────────────────────────────────────────
-- mv_engagement_by_platform_week
-- Aggregate engagement per platform per ISO week.
-- Powers: optimal_hours(), top_threads() weekly rollup
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_engagement_by_platform_week AS
SELECT
  platform,
  date_trunc('week', occurred_at) AS week_start,
  event_type,
  COUNT(*)                         AS event_count,
  SUM(metric_value)                AS total_value,
  AVG(metric_value)                AS avg_value
FROM analytics_events
GROUP BY platform, date_trunc('week', occurred_at), event_type
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_epw_unique
  ON mv_engagement_by_platform_week (platform, week_start, event_type);

COMMENT ON MATERIALIZED VIEW mv_engagement_by_platform_week IS
  'Weekly engagement rollup per platform. Refreshed hourly by pg_cron.';

-- ─────────────────────────────────────────────────────────────────────────────
-- mv_top_content_pieces
-- Top content pieces by total engagement, last 90 days.
-- Powers: top_threads(), pattern_match()
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_top_content_pieces AS
SELECT
  ae.content_id,
  cp.title,
  cp.url,
  cp.published_at,
  cp.tags,
  cp.hook,
  cp.has_code,
  cp.has_image,
  cp.has_video,
  ae.platform,
  SUM(ae.metric_value)             AS total_engagement,
  COUNT(DISTINCT ae.event_type)    AS event_types_count,
  MAX(ae.occurred_at)              AS last_event_at
FROM analytics_events ae
LEFT JOIN content_pieces cp ON cp.id = ae.content_id
WHERE ae.occurred_at >= NOW() - INTERVAL '90 days'
  AND ae.event_type IN ('engagement', 'click', 'impression', 'view', 'like', 'retweet')
GROUP BY ae.content_id, cp.title, cp.url, cp.published_at, cp.tags,
         cp.hook, cp.has_code, cp.has_image, cp.has_video, ae.platform
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_tcp_unique
  ON mv_top_content_pieces (content_id, platform);

COMMENT ON MATERIALIZED VIEW mv_top_content_pieces IS
  'Top content pieces by engagement, last 90d. Refreshed hourly by pg_cron.';

-- ─────────────────────────────────────────────────────────────────────────────
-- mv_hourly_heatmap
-- Hour-of-day × day-of-week engagement heatmap per platform.
-- Powers: optimal_hours()
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_heatmap AS
SELECT
  platform,
  EXTRACT(ISODOW FROM occurred_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::INTEGER AS dow,  -- 1=Mon, 7=Sun
  EXTRACT(HOUR  FROM occurred_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::INTEGER AS hour_of_day,
  event_type,
  COUNT(*)              AS event_count,
  SUM(metric_value)     AS total_value,
  AVG(metric_value)     AS avg_value
FROM analytics_events
WHERE occurred_at >= NOW() - INTERVAL '30 days'
GROUP BY platform,
         EXTRACT(ISODOW FROM occurred_at AT TIME ZONE 'America/Argentina/Buenos_Aires'),
         EXTRACT(HOUR  FROM occurred_at AT TIME ZONE 'America/Argentina/Buenos_Aires'),
         event_type
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_hh_unique
  ON mv_hourly_heatmap (platform, dow, hour_of_day, event_type);

COMMENT ON MATERIALIZED VIEW mv_hourly_heatmap IS
  'Engagement heatmap by hour-of-day and day-of-week (ART timezone). '
  'Last 30 days. Refreshed every 6h by pg_cron.';

-- ─────────────────────────────────────────────────────────────────────────────
-- mv_roi_per_content
-- ROI = total engagement / total spend for each content piece with ad data.
-- Powers: roi_per_content_piece()
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_roi_per_content AS
SELECT
  cp.id       AS content_id,
  cp.title,
  cp.platform AS platform,  -- NOTE: content_pieces.platform is implicit in id prefix
  cp.published_at,
  COALESCE(eng.total_engagement, 0)  AS total_engagement,
  COALESCE(spend.total_spend_usd, 0) AS total_spend_usd,
  CASE
    WHEN COALESCE(spend.total_spend_usd, 0) = 0 THEN NULL
    ELSE COALESCE(eng.total_engagement, 0) / spend.total_spend_usd
  END AS engagement_per_dollar
FROM content_pieces cp
LEFT JOIN (
  SELECT content_id, SUM(metric_value) AS total_engagement
  FROM analytics_events
  WHERE event_type IN ('engagement', 'like', 'retweet', 'click')
  GROUP BY content_id
) eng ON eng.content_id = cp.id
LEFT JOIN (
  SELECT campaign_id, SUM(spend_usd) AS total_spend_usd
  FROM ad_spend_events
  GROUP BY campaign_id
) spend ON spend.campaign_id = cp.id  -- campaign_id aligned to content_id by ingestion convention
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_roi_unique
  ON mv_roi_per_content (content_id);

COMMENT ON MATERIALIZED VIEW mv_roi_per_content IS
  'ROI per content piece: engagement / ad spend. NULL engagement_per_dollar means no spend. '
  'Refreshed every 6h by pg_cron.';

-- ─────────────────────────────────────────────────────────────────────────────
-- pg_cron scheduled refreshes
-- ─────────────────────────────────────────────────────────────────────────────
-- Refresh hourly heatmap every 6 hours (plenty fresh for day-of-week analysis)
SELECT cron.schedule(
  'refresh-mv-hourly-heatmap',
  '0 */6 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hourly_heatmap$$
);

-- Refresh top content pieces hourly (fast-moving metric)
SELECT cron.schedule(
  'refresh-mv-top-content',
  '15 * * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_content_pieces$$
);

-- Refresh platform-week rollup every 6 hours
SELECT cron.schedule(
  'refresh-mv-engagement-weekly',
  '30 */6 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_engagement_by_platform_week$$
);

-- Refresh ROI view every 6 hours
SELECT cron.schedule(
  'refresh-mv-roi',
  '45 */6 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_roi_per_content$$
);

-- Initial population (no CONCURRENTLY on first run — views have no data yet)
REFRESH MATERIALIZED VIEW mv_engagement_by_platform_week;
REFRESH MATERIALIZED VIEW mv_top_content_pieces;
REFRESH MATERIALIZED VIEW mv_hourly_heatmap;
REFRESH MATERIALIZED VIEW mv_roi_per_content;
