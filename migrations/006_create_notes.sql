-- 006_create_notes.sql
-- Notes, note revisions, and docs.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Notes
-- =============================================================================

CREATE TABLE IF NOT EXISTS notes (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL DEFAULT '',
    body            TEXT            DEFAULT '',
    icon            TEXT            DEFAULT '',
    color           TEXT            DEFAULT '',
    tags            JSONB           DEFAULT '[]',
    linked_feature  TEXT            DEFAULT '',
    pinned          BOOLEAN         DEFAULT false,
    deleted         BOOLEAN         DEFAULT false,
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notes_user_id        ON notes (user_id);
CREATE INDEX IF NOT EXISTS idx_notes_project_id     ON notes (project_id);
CREATE INDEX IF NOT EXISTS idx_notes_pinned         ON notes (pinned) WHERE pinned = true;
CREATE INDEX IF NOT EXISTS idx_notes_linked_feature ON notes (linked_feature) WHERE linked_feature != '';
CREATE INDEX IF NOT EXISTS idx_notes_deleted_at     ON notes (deleted_at);

COMMENT ON TABLE notes IS 'User notes with tagging, pinning, and feature linking';

-- =============================================================================
-- Note Revisions
-- =============================================================================

CREATE TABLE IF NOT EXISTS note_revisions (
    id              BIGSERIAL       PRIMARY KEY,
    note_id         UUID            NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    content         TEXT            NOT NULL DEFAULT '',
    version         INTEGER         NOT NULL,
    user_id         BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    device_id       TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_note_revisions_note_id ON note_revisions (note_id);
CREATE INDEX IF NOT EXISTS idx_note_revisions_version ON note_revisions (note_id, version);

COMMENT ON TABLE note_revisions IS 'Versioned history of note content changes';

-- =============================================================================
-- Docs
-- =============================================================================

CREATE TABLE IF NOT EXISTS docs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id      UUID            REFERENCES projects(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL DEFAULT '',
    slug            TEXT            NOT NULL DEFAULT '',
    body            TEXT            DEFAULT '',
    category        TEXT            DEFAULT '',
    tags            JSONB           DEFAULT '[]',
    parent_id       TEXT            DEFAULT '',
    position        INTEGER         DEFAULT 0,
    published       BOOLEAN         DEFAULT false,
    published_at    TIMESTAMPTZ,
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_docs_user_id    ON docs (user_id);
CREATE INDEX IF NOT EXISTS idx_docs_project_id ON docs (project_id);
CREATE INDEX IF NOT EXISTS idx_docs_slug       ON docs (slug);
CREATE INDEX IF NOT EXISTS idx_docs_category   ON docs (category);
CREATE INDEX IF NOT EXISTS idx_docs_published  ON docs (published) WHERE published = true;
CREATE INDEX IF NOT EXISTS idx_docs_deleted_at ON docs (deleted_at);

COMMENT ON TABLE docs IS 'Structured documentation pages with hierarchy and publishing';
