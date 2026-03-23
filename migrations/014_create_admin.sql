-- 014_create_admin.sql
-- Admin tables: badges, wallets, points, GitHub repos/issues.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Badge Definitions
-- =============================================================================

CREATE TABLE IF NOT EXISTS badge_definitions (
    id                  BIGSERIAL   PRIMARY KEY,
    slug                TEXT        UNIQUE NOT NULL,
    name                TEXT        NOT NULL DEFAULT '',
    description         TEXT        DEFAULT '',
    category            TEXT        DEFAULT '',
    icon                TEXT        DEFAULT '',
    color               TEXT        DEFAULT '',
    points_threshold    INTEGER     DEFAULT 0,
    sort_order          INTEGER     DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_badge_definitions_slug     ON badge_definitions (slug);
CREATE INDEX IF NOT EXISTS idx_badge_definitions_category ON badge_definitions (category);

COMMENT ON TABLE badge_definitions IS 'Gamification badge definitions with thresholds';

-- =============================================================================
-- User Badges
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_badges (
    id                      BIGSERIAL   PRIMARY KEY,
    user_id                 BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge_definition_id     BIGINT      NOT NULL REFERENCES badge_definitions(id) ON DELETE CASCADE,
    awarded_at              TIMESTAMPTZ DEFAULT NOW(),
    note                    TEXT        DEFAULT '',
    created_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_badges_user_badge
    ON user_badges (user_id, badge_definition_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user_id ON user_badges (user_id);

COMMENT ON TABLE user_badges IS 'Badges awarded to users (one per badge type per user)';

-- =============================================================================
-- User Wallets (points balance)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_wallets (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance             INTEGER     DEFAULT 0,
    lifetime_earned     INTEGER     DEFAULT 0,
    last_transaction_at TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_wallets_user_id ON user_wallets (user_id);

COMMENT ON TABLE user_wallets IS 'Gamification points wallet per user';

-- =============================================================================
-- Points Transactions
-- =============================================================================

CREATE TABLE IF NOT EXISTS points_transactions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount          INTEGER         NOT NULL,
    type            TEXT            NOT NULL DEFAULT 'earn'
                                    CHECK (type IN ('earn', 'spend', 'bonus', 'penalty', 'refund')),
    source          TEXT            DEFAULT 'system',
    reference_id    TEXT            DEFAULT '',
    description     TEXT            DEFAULT '',
    balance_after   INTEGER         DEFAULT 0,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_points_transactions_user_id ON points_transactions (user_id);
CREATE INDEX IF NOT EXISTS idx_points_transactions_type    ON points_transactions (type);
CREATE INDEX IF NOT EXISTS idx_points_transactions_created ON points_transactions (created_at);

COMMENT ON TABLE points_transactions IS 'Ledger of all gamification points transactions';

-- =============================================================================
-- GitHub Repos (synced from GitHub)
-- =============================================================================

CREATE TABLE IF NOT EXISTS github_repos (
    id              BIGSERIAL       PRIMARY KEY,
    owner           TEXT            NOT NULL DEFAULT '',
    name            TEXT            NOT NULL DEFAULT '',
    full_name       TEXT            UNIQUE NOT NULL,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_github_repos_full_name  ON github_repos (full_name);
CREATE INDEX IF NOT EXISTS idx_github_repos_deleted_at ON github_repos (deleted_at);

COMMENT ON TABLE github_repos IS 'GitHub repositories synced for issue tracking';

-- =============================================================================
-- GitHub Issues (synced from GitHub)
-- =============================================================================

CREATE TABLE IF NOT EXISTS github_issues (
    id              BIGSERIAL       PRIMARY KEY,
    github_id       BIGINT          NOT NULL DEFAULT 0,
    repo            TEXT            NOT NULL DEFAULT '',
    title           TEXT            NOT NULL DEFAULT '',
    body            TEXT            DEFAULT '',
    state           TEXT            DEFAULT 'open'
                                    CHECK (state IN ('open', 'closed')),
    type            TEXT            DEFAULT '',
    author          TEXT            DEFAULT '',
    author_avatar   TEXT            DEFAULT '',
    labels          TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_github_issues_github_id  ON github_issues (github_id);
CREATE INDEX IF NOT EXISTS idx_github_issues_repo       ON github_issues (repo);
CREATE INDEX IF NOT EXISTS idx_github_issues_state      ON github_issues (state);
CREATE INDEX IF NOT EXISTS idx_github_issues_deleted_at ON github_issues (deleted_at);

COMMENT ON TABLE github_issues IS 'GitHub issues synced for dashboard display';
