#!/usr/bin/env python3
"""
Singer JSON stream → analytics_events / ad_spend_events row mapper.

Each Singer tap produces a stream of JSON messages:
  {"type": "SCHEMA",  "stream": "...", "schema": {...}, "key_properties": [...]}
  {"type": "RECORD",  "stream": "...", "record": {...}}
  {"type": "STATE",   "value": {...}}

This module maps RECORD messages to dicts compatible with the
walter_devrel_analytics Postgres schema (Decision 4 in the spec).

Usage:
  from singer_to_analytics import map_singer_record, process_stream

Refs: docs/specs/devrel-analytics-stack.md (Decision 4 — Schema)
      docs/operational/council-v2-prereqs.md (V-prereq-9)
"""

from __future__ import annotations

import json
import sys
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

def map_singer_record(
    message: dict[str, Any],
    *,
    source_tap: str,
) -> list[dict[str, Any]]:
    """
    Map a Singer RECORD message to one or more row dicts.

    Returns:
        List of dicts. Each dict is either:
        - an analytics_events row (for engagement/impression metrics)
        - an ad_spend_events row (for spend data from ads taps)

    The caller identifies which table to insert into via the '_table' key.
    """
    if message.get("type") != "RECORD":
        return []

    stream = message.get("stream", "")
    record = message.get("record", {})

    tap_handlers = {
        "google_ads": _map_google_ads,
        "tap_google_ads": _map_google_ads,
        "facebook": _map_facebook,
        "tap_facebook": _map_facebook,
        "meta": _map_facebook,
        "google_analytics": _map_google_analytics,
        "tap_google_analytics": _map_google_analytics,
        "linkedin_ads": _map_linkedin_ads,
        "tap_linkedin_ads": _map_linkedin_ads,
    }

    handler = tap_handlers.get(source_tap.lower().replace("-", "_"))
    if handler is None:
        return []

    return handler(stream, record)


def process_stream(
    lines: "Iterable[str]",
    *,
    source_tap: str,
    db_conn: Any = None,
) -> dict[str, int]:
    """
    Process a Singer JSON stream line by line, inserting rows into Postgres.

    If db_conn is None, rows are collected in memory (for testing).
    Returns counts: {"analytics_events": N, "ad_spend_events": N, "errors": N}
    """
    import itertools
    counts: dict[str, int] = {"analytics_events": 0, "ad_spend_events": 0, "errors": 0}

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            counts["errors"] += 1
            continue

        msg_type = msg.get("type")
        if msg_type == "STATE":
            # Forward state to stdout for run-tap.sh to capture into state file
            print(json.dumps(msg.get("value", {})))
            sys.stdout.flush()
            continue

        if msg_type != "RECORD":
            continue

        try:
            rows = map_singer_record(msg, source_tap=source_tap)
        except Exception as exc:
            print(f"[singer_to_analytics] Mapper error: {exc}", file=sys.stderr)
            counts["errors"] += 1
            continue

        for row in rows:
            table = row.pop("_table", "analytics_events")
            if db_conn is not None:
                _upsert_row(db_conn, table, row)
            counts[table] = counts.get(table, 0) + 1

    return counts


# ─────────────────────────────────────────────────────────────────────────────
# Tap-specific mappers
# ─────────────────────────────────────────────────────────────────────────────

def _map_google_ads(stream: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    """
    Map Google Ads RECORD → ad_spend_events row(s).
    Covers tap-google-ads streams: campaigns, ad_groups, ads
    Also covers YouTube Ads (flows through Google Ads API).
    """
    rows = []

    campaign_id = str(record.get("campaign_id") or record.get("campaign", {}).get("id", ""))
    ad_group_id = str(record.get("ad_group_id") or record.get("ad_group", {}).get("id") or "")
    ad_id       = str(record.get("ad_id") or record.get("id") or campaign_id)

    # Date: prefer 'date' field, fallback to 'segments_date' or today
    raw_date = record.get("date") or record.get("segments_date") or date.today().isoformat()
    occurred_at = _parse_date_to_ts(raw_date)

    # Cost is stored in micros (1 USD = 1,000,000 micros)
    cost_micros = _safe_numeric(
        record.get("cost_micros")
        or record.get("metrics_cost_micros")
        or record.get("metrics", {}).get("cost_micros", 0)
    )
    spend_usd = float(cost_micros) / 1_000_000.0

    impressions = _safe_int(
        record.get("impressions")
        or record.get("metrics_impressions")
        or record.get("metrics", {}).get("impressions", 0)
    )
    clicks = _safe_int(
        record.get("clicks")
        or record.get("metrics_clicks")
        or record.get("metrics", {}).get("clicks", 0)
    )
    conversions = _safe_int(
        record.get("conversions")
        or record.get("metrics_conversions")
        or record.get("metrics", {}).get("conversions", 0)
    )

    if not campaign_id:
        return []

    rows.append({
        "_table":       "ad_spend_events",
        "occurred_at":  occurred_at,
        "platform":     "google",
        "campaign_id":  campaign_id,
        "ad_group_id":  ad_group_id or None,
        "ad_id":        ad_id or None,
        "spend_usd":    spend_usd,
        "impressions":  impressions,
        "clicks":       clicks,
        "conversions":  conversions,
        "metadata":     json.dumps({"stream": stream, "source_tap": "tap-google-ads"}),
    })

    return rows


def _map_facebook(stream: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    """
    Map tap-facebook RECORD → ad_spend_events row(s).
    Covers streams: ads_insights, campaigns, ad_sets
    """
    rows = []

    campaign_id = str(record.get("campaign_id") or record.get("campaign", {}).get("id") or "")
    ad_set_id   = str(record.get("adset_id") or record.get("ad_set_id") or "")
    ad_id       = str(record.get("ad_id") or record.get("id") or campaign_id)

    raw_date = record.get("date_start") or record.get("date") or date.today().isoformat()
    occurred_at = _parse_date_to_ts(raw_date)

    spend = _safe_numeric(record.get("spend") or 0)
    impressions = _safe_int(record.get("impressions") or 0)
    clicks = _safe_int(record.get("clicks") or 0)
    conversions = _safe_int(
        record.get("conversions") or record.get("actions", [{}])[-1].get("value", 0)
        if record.get("actions") else 0
    )

    if not campaign_id:
        return []

    rows.append({
        "_table":       "ad_spend_events",
        "occurred_at":  occurred_at,
        "platform":     "meta",
        "campaign_id":  campaign_id,
        "ad_group_id":  ad_set_id or None,
        "ad_id":        ad_id or None,
        "spend_usd":    float(spend),
        "impressions":  impressions,
        "clicks":       clicks,
        "conversions":  conversions,
        "metadata":     json.dumps({"stream": stream, "source_tap": "tap-facebook"}),
    })

    return rows


def _map_google_analytics(stream: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    """
    Map tap-google-analytics RECORD → analytics_events row(s).
    Streams: report (GA4 custom report)
    """
    rows = []

    # GA4 dimensions are in 'dimensionValues', metrics in 'metricValues'
    # For simple tap-google-analytics, fields are flattened
    page = record.get("pagePath") or record.get("page_path") or "unknown"
    content_id = f"ga4:{page}"

    raw_date = record.get("date") or record.get("dimensionValues", [{}])[0].get("value") or date.today().isoformat()
    occurred_at = _parse_date_to_ts(raw_date)

    sessions = _safe_int(record.get("sessions") or record.get("ga_sessions") or 0)
    pageviews = _safe_int(record.get("pageviews") or record.get("screenPageViews") or 0)

    if pageviews > 0:
        rows.append({
            "_table":       "analytics_events",
            "occurred_at":  occurred_at,
            "platform":     "ga4",
            "content_id":   content_id,
            "event_type":   "view",
            "metric_value": pageviews,
            "metadata":     json.dumps({"sessions": sessions, "page": page}),
        })

    return rows


def _map_linkedin_ads(stream: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    """
    Map tap-linkedin-ads RECORD → ad_spend_events row(s).
    Streams: ad_analytics_by_campaign, ad_analytics_by_creative
    Prereq: LinkedIn Marketing Developer Platform approval (Tier 3).
    """
    rows = []

    campaign_id = str(record.get("campaign") or record.get("pivotValues", [None])[0] or "")
    ad_id       = str(record.get("creative") or campaign_id)

    raw_date = record.get("dateRange", {}).get("start", {}).get("day")
    if not raw_date:
        raw_date = date.today().isoformat()
    occurred_at = _parse_date_to_ts(str(raw_date))

    # LinkedIn cost is in local currency (USD if account currency is USD)
    spend = _safe_numeric(record.get("costInLocalCurrency") or record.get("spend") or 0)
    impressions = _safe_int(record.get("impressions") or 0)
    clicks = _safe_int(record.get("clicks") or 0)
    conversions = _safe_int(record.get("externalWebsiteConversions") or 0)

    if not campaign_id:
        return []

    rows.append({
        "_table":       "ad_spend_events",
        "occurred_at":  occurred_at,
        "platform":     "linkedin",
        "campaign_id":  campaign_id,
        "ad_group_id":  None,
        "ad_id":        ad_id or None,
        "spend_usd":    float(spend),
        "impressions":  impressions,
        "clicks":       clicks,
        "conversions":  conversions,
        "metadata":     json.dumps({"stream": stream, "source_tap": "tap-linkedin-ads"}),
    })

    return rows


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _parse_date_to_ts(raw: str) -> str:
    """Convert 'YYYY-MM-DD' or ISO datetime string → UTC ISO 8601 string."""
    if not raw:
        return datetime.now(tz=timezone.utc).isoformat()
    try:
        # Try full ISO datetime first
        if "T" in raw:
            return datetime.fromisoformat(raw.replace("Z", "+00:00")).isoformat()
        # Date only → midnight UTC
        return datetime.fromisoformat(raw).replace(tzinfo=timezone.utc).isoformat()
    except (ValueError, TypeError):
        return datetime.now(tz=timezone.utc).isoformat()


def _safe_numeric(val: Any) -> Decimal:
    """Coerce a value to Decimal, returning 0 on failure."""
    if val is None:
        return Decimal(0)
    try:
        return Decimal(str(val))
    except InvalidOperation:
        return Decimal(0)


def _safe_int(val: Any) -> int:
    """Coerce a value to int, returning 0 on failure."""
    if val is None:
        return 0
    try:
        return int(float(str(val)))
    except (ValueError, TypeError):
        return 0


def _upsert_row(conn: Any, table: str, row: dict[str, Any]) -> None:
    """
    Upsert a row into analytics_events or ad_spend_events.
    conn: psycopg2 connection or compatible.
    """
    if table == "ad_spend_events":
        sql = """
            INSERT INTO ad_spend_events
              (occurred_at, platform, campaign_id, ad_group_id, ad_id,
               spend_usd, impressions, clicks, conversions, metadata)
            VALUES
              (%(occurred_at)s::timestamptz, %(platform)s, %(campaign_id)s,
               %(ad_group_id)s, %(ad_id)s, %(spend_usd)s, %(impressions)s,
               %(clicks)s, %(conversions)s, %(metadata)s::jsonb)
            ON CONFLICT (platform, ad_id, occurred_at) DO UPDATE
              SET spend_usd    = EXCLUDED.spend_usd,
                  impressions  = EXCLUDED.impressions,
                  clicks       = EXCLUDED.clicks,
                  conversions  = EXCLUDED.conversions,
                  ingested_at  = NOW()
        """
    else:
        sql = """
            INSERT INTO analytics_events
              (occurred_at, platform, content_id, event_type, metric_value, metadata)
            VALUES
              (%(occurred_at)s::timestamptz, %(platform)s, %(content_id)s,
               %(event_type)s, %(metric_value)s, %(metadata)s::jsonb)
            ON CONFLICT (platform, content_id, event_type, occurred_at) DO UPDATE
              SET metric_value = EXCLUDED.metric_value,
                  ingested_at  = NOW()
        """

    with conn.cursor() as cur:
        cur.execute(sql, row)
    conn.commit()


# ─────────────────────────────────────────────────────────────────────────────
# CLI entrypoint
# ─────────────────────────────────────────────────────────────────────────────

def _cli() -> None:
    """
    Pipe Singer JSON stream through the mapper and insert into Postgres.

    Usage:
      tap-google-ads --config config.json --state state.json | \
        python3 singer_to_analytics.py --tap google_ads
    """
    import argparse
    import os

    parser = argparse.ArgumentParser(description="Singer → analytics_events mapper")
    parser.add_argument("--tap", required=True, help="Source tap name (google_ads, facebook, etc.)")
    parser.add_argument("--db-url", default=os.environ.get("ANALYTICS_DB_URL"),
                        help="Postgres URL (default: $ANALYTICS_DB_URL)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print rows to stdout instead of inserting")
    args = parser.parse_args()

    if not args.dry_run and not args.db_url:
        print("[singer_to_analytics] ERROR: --db-url or $ANALYTICS_DB_URL required.", file=sys.stderr)
        sys.exit(1)

    conn = None
    if not args.dry_run:
        try:
            import psycopg2
            conn = psycopg2.connect(args.db_url)
        except ImportError:
            print("[singer_to_analytics] ERROR: psycopg2 not installed. pip install psycopg2-binary", file=sys.stderr)
            sys.exit(1)

    counts = process_stream(sys.stdin, source_tap=args.tap, db_conn=conn)

    if conn:
        conn.close()

    print(f"[singer_to_analytics] Done: {counts}", file=sys.stderr)
    if counts.get("errors", 0) > 0:
        sys.exit(1)


if __name__ == "__main__":
    _cli()
