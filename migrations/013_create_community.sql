-- 013_create_community.sql
-- Community posts, likes, comments, issues, sponsors, contact, pages, and blog posts.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Community Posts
-- =============================================================================

CREATE TABLE IF NOT EXISTS community_posts (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT            NOT NULL DEFAULT '',
    content         TEXT            DEFAULT '',
    icon            TEXT            DEFAULT '',
    color           TEXT            DEFAULT '',
    media           TEXT            DEFAULT '',
    tags            JSONB           DEFAULT '[]',
    status          TEXT            DEFAULT 'published'
                                    CHECK (status IN ('draft', 'published', 'hidden', 'flagged')),
    likes_count     INTEGER         DEFAULT 0,
    comments_count  INTEGER         DEFAULT 0,
    parent_id       BIGINT          REFERENCES community_posts(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_community_posts_user_id    ON community_posts (user_id);
CREATE INDEX IF NOT EXISTS idx_community_posts_status     ON community_posts (status);
CREATE INDEX IF NOT EXISTS idx_community_posts_parent_id  ON community_posts (parent_id);
CREATE INDEX IF NOT EXISTS idx_community_posts_deleted_at ON community_posts (deleted_at);

COMMENT ON TABLE community_posts IS 'User-generated community discussion posts with threading';

-- =============================================================================
-- Community Likes
-- =============================================================================

CREATE TABLE IF NOT EXISTS community_likes (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id         BIGINT          NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_community_likes_user_post
    ON community_likes (user_id, post_id);

COMMENT ON TABLE community_likes IS 'One like per user per community post';

-- =============================================================================
-- Comments (generic, entity-polymorphic)
-- =============================================================================

CREATE TABLE IF NOT EXISTS comments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type     TEXT            NOT NULL DEFAULT '',
    entity_id       UUID            NOT NULL,
    body            TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'active'
                                    CHECK (status IN ('active', 'hidden', 'flagged', 'deleted')),
    resolved        BOOLEAN         DEFAULT false,
    version         INTEGER         DEFAULT 1,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_comments_user_id    ON comments (user_id);
CREATE INDEX IF NOT EXISTS idx_comments_entity     ON comments (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_comments_deleted_at ON comments (deleted_at);

COMMENT ON TABLE comments IS 'Polymorphic comments attachable to any entity type';

-- =============================================================================
-- Issues (bug tracker / feedback)
-- =============================================================================

CREATE TABLE IF NOT EXISTS issues (
    id                  BIGSERIAL   PRIMARY KEY,
    title               TEXT        NOT NULL DEFAULT '',
    body                TEXT        DEFAULT '',
    status              TEXT        DEFAULT 'open'
                                    CHECK (status IN ('open', 'in-progress', 'resolved', 'closed', 'wontfix')),
    priority            TEXT        DEFAULT 'medium'
                                    CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    reporter_user_id    BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    assignee_id         BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    labels              JSONB       DEFAULT '[]',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_issues_status           ON issues (status);
CREATE INDEX IF NOT EXISTS idx_issues_priority         ON issues (priority);
CREATE INDEX IF NOT EXISTS idx_issues_reporter_user_id ON issues (reporter_user_id);
CREATE INDEX IF NOT EXISTS idx_issues_assignee_id      ON issues (assignee_id);
CREATE INDEX IF NOT EXISTS idx_issues_deleted_at       ON issues (deleted_at);

COMMENT ON TABLE issues IS 'Platform issue/bug tracker for user feedback and reports';

-- =============================================================================
-- Sponsors
-- =============================================================================

CREATE TABLE IF NOT EXISTS sponsors (
    id              BIGSERIAL       PRIMARY KEY,
    name            TEXT            NOT NULL DEFAULT '',
    tier            TEXT            DEFAULT 'bronze'
                                    CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum', 'diamond')),
    logo_url        TEXT            DEFAULT '',
    website_url     TEXT            DEFAULT '',
    description     TEXT            DEFAULT '',
    sort_order      INTEGER         DEFAULT 0,
    status          TEXT            DEFAULT 'active'
                                    CHECK (status IN ('active', 'inactive', 'pending')),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sponsors_status     ON sponsors (status);
CREATE INDEX IF NOT EXISTS idx_sponsors_sort_order ON sponsors (sort_order);

COMMENT ON TABLE sponsors IS 'Platform sponsors displayed on public pages';

-- =============================================================================
-- Contact Messages
-- =============================================================================

CREATE TABLE IF NOT EXISTS contact_messages (
    id              BIGSERIAL       PRIMARY KEY,
    name            TEXT            NOT NULL DEFAULT '',
    email           TEXT            NOT NULL DEFAULT '',
    subject         TEXT            DEFAULT '',
    message         TEXT            NOT NULL DEFAULT '',
    status          TEXT            DEFAULT 'new'
                                    CHECK (status IN ('new', 'read', 'replied', 'archived')),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_contact_messages_status     ON contact_messages (status);
CREATE INDEX IF NOT EXISTS idx_contact_messages_deleted_at ON contact_messages (deleted_at);

COMMENT ON TABLE contact_messages IS 'Public contact form submissions';

-- =============================================================================
-- Pages (CMS)
-- =============================================================================

CREATE TABLE IF NOT EXISTS pages (
    id              BIGSERIAL       PRIMARY KEY,
    title           TEXT            NOT NULL DEFAULT '',
    slug            TEXT            UNIQUE NOT NULL,
    body            TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'published', 'archived')),
    locale          TEXT            DEFAULT 'en',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pages_slug       ON pages (slug);
CREATE INDEX IF NOT EXISTS idx_pages_status     ON pages (status);
CREATE INDEX IF NOT EXISTS idx_pages_deleted_at ON pages (deleted_at);

COMMENT ON TABLE pages IS 'Static CMS pages (about, terms, privacy, etc.)';

-- =============================================================================
-- Posts (Blog)
-- =============================================================================

CREATE TABLE IF NOT EXISTS posts (
    id              BIGSERIAL       PRIMARY KEY,
    title           TEXT            NOT NULL DEFAULT '',
    slug            TEXT            UNIQUE NOT NULL,
    body            TEXT            DEFAULT '',
    excerpt         TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'published', 'archived')),
    category        TEXT            DEFAULT '',
    locale          TEXT            DEFAULT 'en',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_posts_slug       ON posts (slug);
CREATE INDEX IF NOT EXISTS idx_posts_status     ON posts (status);
CREATE INDEX IF NOT EXISTS idx_posts_category   ON posts (category);
CREATE INDEX IF NOT EXISTS idx_posts_deleted_at ON posts (deleted_at);

COMMENT ON TABLE posts IS 'Blog posts with slugs, categories, and i18n locale';
