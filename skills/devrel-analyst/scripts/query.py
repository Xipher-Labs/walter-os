#!/usr/bin/env python3
"""
devrel-analyst skill — DevRel Analytics Query Engine

Queries the walter_devrel_analytics Postgres database and returns
structured markdown insights for the devrel-writer feedback loop.

Supported queries:
  top_threads(since, limit)         — top engagement content
  optimal_hours(platform)           — heatmap best posting hours
  pattern_match(topic)              — what worked for a topic
  roi_per_content_piece(since)      — engagement / ad spend ratio
  weekly_digest()                   — full weekly summary

Security:
  - All user inputs go through sanitize_for_prompt() before LLM injection.
  - SQL uses parameterized queries (psycopg2). No string interpolation.
  - Read-only: SELECT only, no INSERT/UPDATE/DELETE.

Usage:
  python3 query.py top_threads --since 30d --limit 5
  python3 query.py optimal_hours --platform twitter
  python3 query.py pattern_match --topic "solana-rpc"
  python3 query.py roi_per_content_piece --since 90d
  python3 query.py weekly_digest
  python3 query.py <any-query> --dry-run   # no DB needed

Refs: docs/specs/devrel-analytics-stack.md (AC-13, AC-16)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any, Optional

# ─────────────────────────────────────────────────────────────────────────────
# Sanitization — Phase V applies the same pattern as Phase M/T/U
# Replicates sanitizeForPrompt from apps/control-tower/lib/sanitize.ts
# ─────────────────────────────────────────────────────────────────────────────

def sanitize_for_prompt(text: str, max_len: int = 4000) -> str:
    """
    Strip control characters, Walter-OS result markers, and LLM special tokens.
    All operator/external inputs that go into LLM prompts must pass through here.

    Mirrors sanitizeForPrompt in apps/control-tower/lib/sanitize.ts.
    Refs: docs/specs/devrel-analytics-stack.md (CRITICAL note)
    """
    if not text:
        return ""
    s = str(text)

    # Strip C0 control chars except \t \n \r
    s = re.sub(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "", s)

    # Strip Walter-OS result markers
    s = re.sub(r"<<<RESULT_[A-Z_]+>>>", "", s)

    # Strip LLM special tokens
    s = re.sub(r"<\|im_(start|end)\|>", "", s)
    s = re.sub(r"<\|endoftext\|>", "", s)
    s = re.sub(r"\[INST\]|\[\/INST\]", "", s)

    if len(s) > max_len:
        s = s[:max_len] + " [truncated]"

    return s


# ─────────────────────────────────────────────────────────────────────────────
# Interval parsing
# ─────────────────────────────────────────────────────────────────────────────

def _parse_since(since: str) -> str:
    """Convert '30d', '7d', '90d' to Postgres interval string like '30 days'."""
    since = sanitize_for_prompt(since, max_len=20).strip()
    match = re.match(r"^(\d+)d$", since)
    if match:
        return f"{match.group(1)} days"
    # Allow 'NNd', 'NNw', 'NNm' shortcuts
    match_w = re.match(r"^(\d+)w$", since)
    if match_w:
        return f"{int(match_w.group(1)) * 7} days"
    # Default fallback
    return "30 days"


# ─────────────────────────────────────────────────────────────────────────────
# DB connection
# ─────────────────────────────────────────────────────────────────────────────

def _get_connection() -> Any:
    """Open psycopg2 connection from ANALYTICS_DB_URL env."""
    db_url = os.environ.get("ANALYTICS_DB_URL", "")
    if not db_url:
        raise RuntimeError(
            "ANALYTICS_DB_URL not set. "
            "Set it in .env or Infisical workspace 'walter-os'."
        )
    try:
        import psycopg2
        return psycopg2.connect(db_url)
    except ImportError:
        raise RuntimeError("psycopg2 not installed. Run: pip install psycopg2-binary")


# ─────────────────────────────────────────────────────────────────────────────
# Query functions
# ─────────────────────────────────────────────────────────────────────────────

def top_threads(
    since: str = "30d",
    limit: int = 5,
    conn: Any = None,
) -> str:
    """
    Return top N content pieces by total engagement since a given date.
    Output: Markdown table.
    """
    interval = _parse_since(since)
    limit = max(1, min(int(limit), 100))

    if conn is None:
        # DB_not_connected — return mock/dry-run output
        return (
            f"## Top {limit} Threads — Last {interval} (dry-run / DB not connected)\n\n"
            "| Rank | Title | Platform | Engagement | Has Code | Has Image |\n"
            "|------|-------|----------|------------|----------|-----------|\n"
            "| 1 | [mock] How we cut RPC latency by 40%... | twitter | 2847 | yes | no |\n"
            "| 2 | [mock] Yellowstone gRPC streaming guide | youtube | 1203 | yes | yes |\n\n"
            "_No DB connection — showing mock data. Set ANALYTICS_DB_URL to query live data._\n"
        )

    sql = """
        SELECT
            tcp.content_id,
            COALESCE(cp.title, tcp.content_id)   AS title,
            tcp.platform,
            tcp.total_engagement,
            COALESCE(cp.has_code, false)          AS has_code,
            COALESCE(cp.has_image, false)         AS has_image,
            COALESCE(cp.has_video, false)         AS has_video,
            tcp.last_event_at
        FROM mv_top_content_pieces tcp
        LEFT JOIN content_pieces cp ON cp.id = tcp.content_id
        WHERE tcp.last_event_at >= NOW() - %s::interval
        ORDER BY tcp.total_engagement DESC
        LIMIT %s
    """

    with conn.cursor() as cur:
        cur.execute(sql, (interval, limit))
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]

    if not rows:
        return f"## Top Threads — Last {interval}\n\n_No data yet. Ingest pipelines running?_\n"

    lines = [
        f"## Top {limit} Threads — Last {interval}\n",
        "| Rank | Title | Platform | Engagement | Has Code | Has Image |",
        "|------|-------|----------|------------|----------|-----------|",
    ]
    for i, row in enumerate(rows, 1):
        r = dict(zip(cols, row))
        # Sanitize title before LLM injection
        title = sanitize_for_prompt(str(r.get("title", "")), max_len=100)
        lines.append(
            f"| {i} | {title} | {r.get('platform','')} "
            f"| {int(r.get('total_engagement', 0)):,} "
            f"| {'yes' if r.get('has_code') else 'no'} "
            f"| {'yes' if r.get('has_image') else 'no'} |"
        )

    return "\n".join(lines) + "\n"


def optimal_hours(
    platform: str = "twitter",
    conn: Any = None,
) -> str:
    """
    Return heatmap of best posting hours (ART timezone) by day of week.
    Output: Markdown table.
    """
    platform = sanitize_for_prompt(platform, max_len=50).strip().lower()

    if conn is None:
        return (
            f"## Optimal Posting Hours — {platform} (dry-run / DB not connected)\n\n"
            "_No DB connection — showing mock data. Set ANALYTICS_DB_URL._\n\n"
            "Best windows (mock): Mon-Wed 10:00-12:00 ART, Thu 18:00-20:00 ART\n"
        )

    sql = """
        SELECT dow, hour_of_day, SUM(total_value) AS total_engagement
        FROM mv_hourly_heatmap
        WHERE platform = %s
          AND event_type IN ('engagement', 'like', 'click', 'retweet')
        GROUP BY dow, hour_of_day
        ORDER BY total_engagement DESC
        LIMIT 20
    """

    dow_names = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"}

    with conn.cursor() as cur:
        cur.execute(sql, (platform,))
        rows = cur.fetchall()

    if not rows:
        return f"## Optimal Hours — {platform}\n\n_No heatmap data yet._\n"

    lines = [
        f"## Optimal Posting Hours — {platform} (ART timezone)\n",
        "Top 20 windows by engagement:\n",
        "| Day | Hour (ART) | Total Engagement |",
        "|-----|------------|-----------------|",
    ]
    for dow, hour, total in rows:
        day = dow_names.get(int(dow), str(dow))
        lines.append(f"| {day} | {int(hour):02d}:00 | {int(total):,} |")

    return "\n".join(lines) + "\n"


def pattern_match(
    topic: str,
    since: str = "30d",
    conn: Any = None,
) -> str:
    """
    Find hook/format patterns that correlated with high engagement
    for content tagged with a given topic.
    Output: Markdown with insights + recommendations.
    Used by devrel-writer agent before drafting new content (AC-16).
    """
    topic = sanitize_for_prompt(topic, max_len=100).strip()
    interval = _parse_since(since)

    if conn is None:
        return (
            f"## Pattern Analysis — topic: {topic} (dry-run / DB not connected)\n\n"
            "_No DB connection — showing mock recommendations._\n\n"
            "**Top patterns for this topic (mock)**:\n"
            "- Hook style: Question hooks perform 2.3x better than statement hooks\n"
            "- Format: Threads with code snippets get 40% more engagement\n"
            "- Optimal length: 3-7 tweets per thread\n"
            "- Best time: Tuesday 10:00-11:00 ART\n"
        )

    # Search content_pieces with matching tags, join with top engagement
    sql = """
        SELECT
            cp.id,
            cp.title,
            cp.hook,
            cp.has_code,
            cp.has_image,
            cp.has_video,
            cp.word_count,
            COALESCE(tcp.total_engagement, 0) AS total_engagement
        FROM content_pieces cp
        LEFT JOIN mv_top_content_pieces tcp ON tcp.content_id = cp.id
        WHERE (
            %s = ANY(cp.tags)
            OR cp.title ILIKE '%%' || %s || '%%'
        )
          AND cp.published_at >= NOW() - %s::interval
        ORDER BY total_engagement DESC
        LIMIT 20
    """

    with conn.cursor() as cur:
        cur.execute(sql, (topic, topic, interval))
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]

    if not rows:
        return (
            f"## Pattern Analysis — topic: {topic}\n\n"
            f"_No content pieces found for topic '{topic}' in last {interval}._\n"
            "Publish content tagged with this topic to build pattern data.\n"
        )

    # Aggregate patterns
    has_code_count = sum(1 for r in rows if dict(zip(cols, r)).get("has_code"))
    has_image_count = sum(1 for r in rows if dict(zip(cols, r)).get("has_image"))
    avg_engagement = sum(dict(zip(cols, r))["total_engagement"] for r in rows) / len(rows)

    # Top hooks — sanitize before LLM
    top_hooks = [
        sanitize_for_prompt(str(dict(zip(cols, r)).get("hook") or ""), max_len=200)
        for r in rows[:3]
        if dict(zip(cols, r)).get("hook")
    ]

    lines = [
        f"## Pattern Analysis — topic: `{topic}` (last {interval})\n",
        f"Analyzed {len(rows)} content pieces.\n",
        "### Format patterns",
        f"- Code snippets: {has_code_count}/{len(rows)} pieces ({100*has_code_count//len(rows)}%)",
        f"- Images: {has_image_count}/{len(rows)} pieces ({100*has_image_count//len(rows)}%)",
        f"- Avg engagement: {avg_engagement:.0f}\n",
        "### Top hooks from high-performing pieces",
    ]
    for h in top_hooks:
        lines.append(f'- "{h}"')

    lines += [
        "\n### Recommendation",
        "Use these patterns when drafting new content on this topic.",
    ]

    return "\n".join(lines) + "\n"


def roi_per_content_piece(
    since: str = "90d",
    conn: Any = None,
) -> str:
    """
    Return engagement-per-dollar ratio for promoted content.
    Output: Markdown table sorted by ROI.
    """
    interval = _parse_since(since)

    if conn is None:
        return (
            f"## ROI per Content Piece — Last {interval} (dry-run / DB not connected)\n\n"
            "_No DB connection — showing mock data._\n\n"
            "| Rank | Title | Platform | Spend USD | Engagement | Eng/$ |\n"
            "|------|-------|----------|-----------|------------|-------|\n"
            "| 1 | [mock] Yellowstone gRPC deep dive | youtube | $45.00 | 5,200 | 115.6 |\n"
        )

    sql = """
        SELECT content_id, title, platform, total_engagement, total_spend_usd,
               engagement_per_dollar
        FROM mv_roi_per_content
        WHERE total_spend_usd > 0
        ORDER BY engagement_per_dollar DESC NULLS LAST
        LIMIT 20
    """

    with conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]

    if not rows:
        return f"## ROI per Content — Last {interval}\n\n_No ad spend data yet._\n"

    lines = [
        f"## ROI per Content Piece — Last {interval}\n",
        "| Rank | Title | Platform | Spend | Engagement | Eng/$ |",
        "|------|-------|----------|-------|------------|-------|",
    ]
    for i, row in enumerate(rows, 1):
        r = dict(zip(cols, row))
        title = sanitize_for_prompt(str(r.get("title", r.get("content_id", ""))), max_len=60)
        eng_per_dollar = r.get("engagement_per_dollar")
        eng_str = f"{eng_per_dollar:.1f}" if eng_per_dollar else "N/A"
        lines.append(
            f"| {i} | {title} | {r.get('platform','')} "
            f"| ${float(r.get('total_spend_usd', 0)):.2f} "
            f"| {int(r.get('total_engagement', 0)):,} "
            f"| {eng_str} |"
        )

    return "\n".join(lines) + "\n"


def weekly_digest(conn: Any = None) -> str:
    """
    Compose a full weekly Markdown digest for wiki/devrel/insights/.
    Called by n8n cron Mon 09:00 ART (AC-14).
    Output: Full Markdown document.
    """
    now = datetime.now(tz=timezone.utc)
    iso_week = now.strftime("%Y-W%V")

    if conn is None:
        return (
            f"# DevRel Weekly Digest — {iso_week} (dry-run / mock)\n\n"
            "> Generated: " + now.isoformat() + "\n\n"
            "## Highlights\n\n"
            "- [mock] Top thread: 'How we cut RPC latency by 40%' — 2,847 engagements\n"
            "- [mock] YouTube: 'Yellowstone gRPC guide' reached 1,200 views\n"
            "- [mock] GitHub: +42 stars this week\n\n"
            "## Top Content (last 7d)\n\n"
            "_dry-run mode — no DB connection_\n\n"
            "## Platform Breakdown\n\n"
            "_Connect ANALYTICS_DB_URL for live data._\n\n"
            "## Recommendations\n\n"
            "- Continue publishing gRPC content — strong engagement signal\n"
            "- Optimal posting: Tuesday 10:00-11:00 ART\n"
        )

    # Build digest from live queries
    top = top_threads(since="7d", limit=5, conn=conn)
    hours = optimal_hours(platform="twitter", conn=conn)
    roi = roi_per_content_piece(since="30d", conn=conn)

    return "\n\n".join([
        f"# DevRel Weekly Digest — {iso_week}",
        f"> Generated: {now.isoformat()}\n",
        "## Top Content (last 7d)\n\n" + top,
        "## Best Posting Windows (Twitter)\n\n" + hours,
        "## Ad ROI (last 30d)\n\n" + roi,
    ])


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

QUERIES = {
    "top_threads":          top_threads,
    "optimal_hours":        optimal_hours,
    "pattern_match":        pattern_match,
    "roi_per_content_piece": roi_per_content_piece,
    "roi_per_content":      roi_per_content_piece,  # alias
    "weekly_digest":        weekly_digest,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="devrel-analyst",
        description=(
            "Query the walter_devrel_analytics DB for DevRel insights.\n"
            "Usage: python3 query.py <query> [args]\n"
            "       python3 query.py <query> --dry-run   (no DB needed)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Supported queries:\n"
            "  top_threads           Top N content pieces by engagement\n"
            "  optimal_hours         Best posting hours heatmap\n"
            "  pattern_match         Hook/format patterns for a topic\n"
            "  roi_per_content_piece Engagement / ad spend ratio\n"
            "  weekly_digest         Full weekly Markdown digest\n"
        ),
    )
    parser.add_argument(
        "query",
        nargs="?",
        choices=list(QUERIES.keys()),
        help="Query to run",
    )
    parser.add_argument("--since",    default="30d",    help="Lookback window (e.g. 30d, 7d, 90d)")
    parser.add_argument("--limit",    type=int, default=5, help="Max rows (top_threads)")
    parser.add_argument("--platform", default="twitter", help="Platform filter (optimal_hours)")
    parser.add_argument("--topic",    default="",       help="Topic for pattern_match")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Return mock output without connecting to Postgres",
    )
    parser.add_argument("--output", default="-", help="Output file path (default: stdout)")

    args = parser.parse_args()

    if args.query is None:
        parser.print_help()
        sys.exit(0)

    conn = None
    if not args.dry_run:
        try:
            conn = _get_connection()
        except RuntimeError as exc:
            print(f"[devrel-analyst] Warning: {exc}", file=sys.stderr)
            print("[devrel-analyst] Falling back to dry-run mode.", file=sys.stderr)
            # Don't exit — produce dry-run output so weekly digest cron doesn't fail hard

    fn = QUERIES[args.query]
    query_kwargs: dict[str, Any] = {"conn": conn}

    if args.query == "top_threads":
        query_kwargs.update({"since": args.since, "limit": args.limit})
    elif args.query == "optimal_hours":
        query_kwargs.update({"platform": args.platform})
    elif args.query == "pattern_match":
        query_kwargs.update({"topic": args.topic, "since": args.since})
    elif args.query in ("roi_per_content_piece", "roi_per_content"):
        query_kwargs.update({"since": args.since})
    # weekly_digest takes no extra args

    try:
        result = fn(**query_kwargs)
    finally:
        if conn:
            conn.close()

    if args.output == "-":
        print(result)
    else:
        with open(args.output, "w") as f:
            f.write(result)
        print(f"[devrel-analyst] Written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
