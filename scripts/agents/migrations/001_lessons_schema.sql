-- 001_lessons_schema.sql — Cross-agent lesson broker schema
-- Target: SQLite (lessons.db) — used locally on each peer
--
-- Note: This file contains two parts:
--   Part 1: Core table (always runs, no FTS5 required)
--   Part 2: FTS5 virtual table + triggers (optional, requires FTS5 module)
--
-- For Postgres (walter_lessons DB on walter-vm), use equivalent types:
--   TEXT PRIMARY KEY -> UUID PRIMARY KEY DEFAULT gen_random_uuid()
--   BLOB -> BYTEA
--   REAL -> FLOAT
--
-- Operator prereqs:
--   - LESSONS_DB_URL for Postgres mode (see council-v2-prereqs.md §M-prereq-3)
--   - Embedding model (see council-v2-prereqs.md §M-prereq-4)
--
-- Refs: docs/specs/walter-council-v2.md T-9 Improvement 4

CREATE TABLE IF NOT EXISTS lessons (
  id          TEXT PRIMARY KEY,
  source_agent TEXT NOT NULL,
  tags        TEXT,
  headline    TEXT NOT NULL,
  body        TEXT,
  embedding   BLOB,
  context     TEXT,
  created_at  TEXT NOT NULL,
  confidence  REAL NOT NULL DEFAULT 1.0
);

CREATE INDEX IF NOT EXISTS idx_lessons_agent ON lessons(source_agent);
CREATE INDEX IF NOT EXISTS idx_lessons_confidence ON lessons(confidence);

-- FTS5 virtual table for keyword search fallback.
-- Note: this block is run with || true — sqlite3 builds without FTS5 will
-- skip it gracefully. Detection at runtime: _lessons_has_fts5().
CREATE VIRTUAL TABLE IF NOT EXISTS lessons_fts USING fts5(
  headline, body, content='lessons', content_rowid='rowid'
);

CREATE TRIGGER IF NOT EXISTS lessons_ai AFTER INSERT ON lessons BEGIN
  INSERT INTO lessons_fts(rowid, headline, body)
  VALUES (new.rowid, new.headline, new.body);
END;

CREATE TRIGGER IF NOT EXISTS lessons_ad AFTER DELETE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body)
  VALUES ('delete', old.rowid, old.headline, old.body);
END;

CREATE TRIGGER IF NOT EXISTS lessons_au AFTER UPDATE ON lessons BEGIN
  INSERT INTO lessons_fts(lessons_fts, rowid, headline, body)
  VALUES ('delete', old.rowid, old.headline, old.body);
  INSERT INTO lessons_fts(rowid, headline, body)
  VALUES (new.rowid, new.headline, new.body);
END;
