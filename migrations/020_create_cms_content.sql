-- 020_create_cms_content.sql
-- Dynamic CMS with multi-language (i18n) support for orchestra-mcp.dev.
-- Languages registry, page/post translations, dynamic content sections,
-- downloads, solutions, and documentation with full i18n.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Languages — Supported languages registry
-- =============================================================================

CREATE TABLE IF NOT EXISTS languages (
    id              SERIAL          PRIMARY KEY,
    code            TEXT            UNIQUE NOT NULL,
    name            TEXT            NOT NULL,
    native_name     TEXT,
    direction       TEXT            DEFAULT 'ltr'
                                    CHECK (direction IN ('ltr', 'rtl')),
    is_default      BOOLEAN         DEFAULT false,
    is_active       BOOLEAN         DEFAULT true,
    sort_order      INTEGER         DEFAULT 0,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_languages_code       ON languages (code);
CREATE INDEX IF NOT EXISTS idx_languages_is_active  ON languages (is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_languages_sort_order  ON languages (sort_order);

COMMENT ON TABLE languages IS 'Supported languages registry for multi-language CMS content';

-- =============================================================================
-- Page Translations — i18n for CMS pages
-- =============================================================================

CREATE TABLE IF NOT EXISTS page_translations (
    id                  BIGSERIAL       PRIMARY KEY,
    page_id             BIGINT          NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    language_code       TEXT            NOT NULL REFERENCES languages(code),
    title               TEXT            NOT NULL DEFAULT '',
    body                TEXT            DEFAULT '',
    meta_title          TEXT            DEFAULT '',
    meta_description    TEXT            DEFAULT '',
    slug                TEXT            NOT NULL DEFAULT '',
    status              TEXT            DEFAULT 'draft'
                                        CHECK (status IN ('draft', 'published', 'archived')),
    published_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(page_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_page_translations_page_id        ON page_translations (page_id);
CREATE INDEX IF NOT EXISTS idx_page_translations_language_code   ON page_translations (language_code);
CREATE INDEX IF NOT EXISTS idx_page_translations_slug            ON page_translations (slug);
CREATE INDEX IF NOT EXISTS idx_page_translations_status          ON page_translations (status);

COMMENT ON TABLE page_translations IS 'Localized translations for CMS pages with SEO metadata';

-- =============================================================================
-- Post Translations — i18n for blog posts
-- =============================================================================

CREATE TABLE IF NOT EXISTS post_translations (
    id                  BIGSERIAL       PRIMARY KEY,
    post_id             BIGINT          NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    language_code       TEXT            NOT NULL REFERENCES languages(code),
    title               TEXT            NOT NULL DEFAULT '',
    body                TEXT            DEFAULT '',
    excerpt             TEXT            DEFAULT '',
    meta_title          TEXT            DEFAULT '',
    meta_description    TEXT            DEFAULT '',
    slug                TEXT            NOT NULL DEFAULT '',
    status              TEXT            DEFAULT 'draft'
                                        CHECK (status IN ('draft', 'published', 'archived')),
    published_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(post_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_post_translations_post_id        ON post_translations (post_id);
CREATE INDEX IF NOT EXISTS idx_post_translations_language_code   ON post_translations (language_code);
CREATE INDEX IF NOT EXISTS idx_post_translations_slug            ON post_translations (slug);
CREATE INDEX IF NOT EXISTS idx_post_translations_status          ON post_translations (status);

COMMENT ON TABLE post_translations IS 'Localized translations for blog posts with SEO metadata';

-- =============================================================================
-- Content Sections — Dynamic sections for homepage/solutions/downloads
-- =============================================================================

CREATE TABLE IF NOT EXISTS content_sections (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    section_type    TEXT            NOT NULL
                                    CHECK (section_type IN (
                                        'hero', 'features', 'pricing', 'testimonials',
                                        'faq', 'cta', 'downloads', 'solutions',
                                        'partners', 'stats', 'custom'
                                    )),
    page_key        TEXT            NOT NULL,
    sort_order      INTEGER         DEFAULT 0,
    is_active       BOOLEAN         DEFAULT true,
    config          JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_sections_page_key    ON content_sections (page_key);
CREATE INDEX IF NOT EXISTS idx_content_sections_section_type ON content_sections (section_type);
CREATE INDEX IF NOT EXISTS idx_content_sections_sort_order  ON content_sections (sort_order);
CREATE INDEX IF NOT EXISTS idx_content_sections_is_active   ON content_sections (is_active) WHERE is_active = true;

COMMENT ON TABLE content_sections IS 'Dynamic page sections (hero, features, pricing, etc.) composable per page';

-- =============================================================================
-- Content Section Translations — i18n for sections
-- =============================================================================

CREATE TABLE IF NOT EXISTS content_section_translations (
    id              BIGSERIAL       PRIMARY KEY,
    section_id      UUID            NOT NULL REFERENCES content_sections(id) ON DELETE CASCADE,
    language_code   TEXT            NOT NULL REFERENCES languages(code),
    title           TEXT            DEFAULT '',
    subtitle        TEXT            DEFAULT '',
    body            TEXT            DEFAULT '',
    items           JSONB           DEFAULT '[]',
    cta_label       TEXT            DEFAULT '',
    cta_url         TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(section_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_content_section_trans_section_id     ON content_section_translations (section_id);
CREATE INDEX IF NOT EXISTS idx_content_section_trans_language_code  ON content_section_translations (language_code);

COMMENT ON TABLE content_section_translations IS 'Localized translations for dynamic content sections with structured items';

-- =============================================================================
-- Downloads — Platform download links
-- =============================================================================

CREATE TABLE IF NOT EXISTS downloads (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    platform        TEXT            NOT NULL
                                    CHECK (platform IN (
                                        'macos', 'windows', 'linux', 'ios', 'android',
                                        'web', 'cli', 'vscode', 'jetbrains', 'other'
                                    )),
    version         TEXT            NOT NULL DEFAULT '',
    download_url    TEXT            NOT NULL DEFAULT '',
    release_notes   TEXT            DEFAULT '',
    file_size_bytes BIGINT          DEFAULT 0,
    checksum        TEXT            DEFAULT '',
    is_latest       BOOLEAN         DEFAULT false,
    is_active       BOOLEAN         DEFAULT true,
    download_count  INTEGER         DEFAULT 0,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_downloads_platform   ON downloads (platform);
CREATE INDEX IF NOT EXISTS idx_downloads_is_latest  ON downloads (is_latest) WHERE is_latest = true;
CREATE INDEX IF NOT EXISTS idx_downloads_is_active  ON downloads (is_active) WHERE is_active = true;

COMMENT ON TABLE downloads IS 'Platform download links with version tracking and checksums';

-- =============================================================================
-- Solutions — Solutions/use-cases showcase
-- =============================================================================

CREATE TABLE IF NOT EXISTS solutions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            TEXT            UNIQUE NOT NULL,
    icon            TEXT            DEFAULT '',
    cover_image     TEXT            DEFAULT '',
    sort_order      INTEGER         DEFAULT 0,
    is_active       BOOLEAN         DEFAULT true,
    tags            JSONB           DEFAULT '[]',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_solutions_slug       ON solutions (slug);
CREATE INDEX IF NOT EXISTS idx_solutions_sort_order ON solutions (sort_order);
CREATE INDEX IF NOT EXISTS idx_solutions_is_active  ON solutions (is_active) WHERE is_active = true;

COMMENT ON TABLE solutions IS 'Solutions and use-case showcases for the platform landing pages';

-- =============================================================================
-- Solution Translations — i18n for solutions
-- =============================================================================

CREATE TABLE IF NOT EXISTS solution_translations (
    id                  BIGSERIAL       PRIMARY KEY,
    solution_id         UUID            NOT NULL REFERENCES solutions(id) ON DELETE CASCADE,
    language_code       TEXT            NOT NULL REFERENCES languages(code),
    title               TEXT            NOT NULL DEFAULT '',
    subtitle            TEXT            DEFAULT '',
    body                TEXT            DEFAULT '',
    meta_title          TEXT            DEFAULT '',
    meta_description    TEXT            DEFAULT '',
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(solution_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_solution_trans_solution_id    ON solution_translations (solution_id);
CREATE INDEX IF NOT EXISTS idx_solution_trans_language_code  ON solution_translations (language_code);

COMMENT ON TABLE solution_translations IS 'Localized translations for solutions with SEO metadata';

-- =============================================================================
-- Doc Categories — Documentation categories (hierarchical)
-- =============================================================================

CREATE TABLE IF NOT EXISTS doc_categories (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            TEXT            UNIQUE NOT NULL,
    parent_id       UUID            REFERENCES doc_categories(id) ON DELETE SET NULL,
    sort_order      INTEGER         DEFAULT 0,
    is_active       BOOLEAN         DEFAULT true,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_categories_slug       ON doc_categories (slug);
CREATE INDEX IF NOT EXISTS idx_doc_categories_parent_id  ON doc_categories (parent_id);
CREATE INDEX IF NOT EXISTS idx_doc_categories_sort_order ON doc_categories (sort_order);
CREATE INDEX IF NOT EXISTS idx_doc_categories_is_active  ON doc_categories (is_active) WHERE is_active = true;

COMMENT ON TABLE doc_categories IS 'Hierarchical documentation categories with self-referencing parent';

-- =============================================================================
-- Doc Category Translations — i18n for doc categories
-- =============================================================================

CREATE TABLE IF NOT EXISTS doc_category_translations (
    id              BIGSERIAL       PRIMARY KEY,
    category_id     UUID            NOT NULL REFERENCES doc_categories(id) ON DELETE CASCADE,
    language_code   TEXT            NOT NULL REFERENCES languages(code),
    title           TEXT            NOT NULL DEFAULT '',
    description     TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(category_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_doc_category_trans_category_id    ON doc_category_translations (category_id);
CREATE INDEX IF NOT EXISTS idx_doc_category_trans_language_code  ON doc_category_translations (language_code);

COMMENT ON TABLE doc_category_translations IS 'Localized translations for documentation categories';

-- =============================================================================
-- Doc Articles — Documentation articles
-- =============================================================================

CREATE TABLE IF NOT EXISTS doc_articles (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID            REFERENCES doc_categories(id) ON DELETE SET NULL,
    slug            TEXT            NOT NULL,
    sort_order      INTEGER         DEFAULT 0,
    is_active       BOOLEAN         DEFAULT true,
    tags            JSONB           DEFAULT '[]',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(category_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_doc_articles_category_id ON doc_articles (category_id);
CREATE INDEX IF NOT EXISTS idx_doc_articles_slug        ON doc_articles (slug);
CREATE INDEX IF NOT EXISTS idx_doc_articles_sort_order  ON doc_articles (sort_order);
CREATE INDEX IF NOT EXISTS idx_doc_articles_is_active   ON doc_articles (is_active) WHERE is_active = true;

COMMENT ON TABLE doc_articles IS 'Documentation articles scoped to categories with slug uniqueness per category';

-- =============================================================================
-- Doc Article Translations — i18n for doc articles
-- =============================================================================

CREATE TABLE IF NOT EXISTS doc_article_translations (
    id                  BIGSERIAL       PRIMARY KEY,
    article_id          UUID            NOT NULL REFERENCES doc_articles(id) ON DELETE CASCADE,
    language_code       TEXT            NOT NULL REFERENCES languages(code),
    title               TEXT            NOT NULL DEFAULT '',
    body                TEXT            DEFAULT '',
    meta_title          TEXT            DEFAULT '',
    meta_description    TEXT            DEFAULT '',
    status              TEXT            DEFAULT 'draft'
                                        CHECK (status IN ('draft', 'published', 'archived')),
    published_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(article_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_doc_article_trans_article_id     ON doc_article_translations (article_id);
CREATE INDEX IF NOT EXISTS idx_doc_article_trans_language_code  ON doc_article_translations (language_code);
CREATE INDEX IF NOT EXISTS idx_doc_article_trans_status         ON doc_article_translations (status);

COMMENT ON TABLE doc_article_translations IS 'Localized translations for documentation articles with publication workflow';

-- =============================================================================
-- Seed default languages
-- =============================================================================

INSERT INTO languages (code, name, native_name, direction, is_default, is_active, sort_order) VALUES
    ('en', 'English',            'English',      'ltr', true,  true, 0),
    ('ar', 'Arabic',             'العربية',      'rtl', false, true, 1),
    ('es', 'Spanish',            'Español',       'ltr', false, true, 2),
    ('fr', 'French',             'Français',      'ltr', false, true, 3),
    ('de', 'German',             'Deutsch',       'ltr', false, true, 4),
    ('ja', 'Japanese',           '日本語',        'ltr', false, true, 5),
    ('zh', 'Chinese Simplified', '简体中文',      'ltr', false, true, 6),
    ('ko', 'Korean',             '한국어',        'ltr', false, true, 7),
    ('pt', 'Portuguese',         'Português',     'ltr', false, true, 8),
    ('ru', 'Russian',            'Русский',       'ltr', false, true, 9)
ON CONFLICT (code) DO NOTHING;
