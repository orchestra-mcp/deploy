-- 012_create_presentations.sql
-- Presentations and slides.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Presentations
-- =============================================================================

CREATE TABLE IF NOT EXISTS presentations (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE SET NULL,
    title           TEXT            NOT NULL DEFAULT '',
    slug            TEXT            NOT NULL DEFAULT '',
    description     TEXT            DEFAULT '',
    theme           JSONB           DEFAULT '{}',
    visibility      TEXT            DEFAULT 'private'
                                    CHECK (visibility IN ('private', 'team', 'public')),
    slide_count     INTEGER         DEFAULT 0,
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_presentations_user_id    ON presentations (user_id);
CREATE INDEX IF NOT EXISTS idx_presentations_team_id    ON presentations (team_id);
CREATE INDEX IF NOT EXISTS idx_presentations_slug       ON presentations (slug);
CREATE INDEX IF NOT EXISTS idx_presentations_deleted_at ON presentations (deleted_at);

COMMENT ON TABLE presentations IS 'Slide deck presentations with theming and visibility';

-- =============================================================================
-- Presentation Slides
-- =============================================================================

CREATE TABLE IF NOT EXISTS presentation_slides (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    presentation_id     UUID        NOT NULL REFERENCES presentations(id) ON DELETE CASCADE,
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slide_number        INTEGER     NOT NULL DEFAULT 0,
    layout              TEXT        DEFAULT 'default',
    title               TEXT        DEFAULT '',
    content             TEXT        DEFAULT '',
    notes               TEXT        DEFAULT '',
    properties          JSONB       DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_presentation_slides_presentation_id
    ON presentation_slides (presentation_id);
CREATE INDEX IF NOT EXISTS idx_presentation_slides_order
    ON presentation_slides (presentation_id, slide_number);

COMMENT ON TABLE presentation_slides IS 'Individual slides within a presentation';
