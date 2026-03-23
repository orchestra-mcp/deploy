-- 008_create_health.sql
-- Health tracking: profiles, water, meals, caffeine, pomodoro, sleep, snapshots.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Health Profiles
-- =============================================================================

CREATE TABLE IF NOT EXISTS health_profiles (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    height_cm           FLOAT,
    weight_kg           FLOAT,
    target_water_ml     INTEGER     DEFAULT 2500,
    work_window_start   TEXT        DEFAULT '09:00',
    work_window_end     TEXT        DEFAULT '17:00',
    sleep_time          TEXT        DEFAULT '23:00',
    wake_time           TEXT        DEFAULT '07:00',
    pomodoro_work_min   INTEGER     DEFAULT 25,
    pomodoro_break_min  INTEGER     DEFAULT 5,
    gerd_shutdown_hours FLOAT       DEFAULT 3,
    caffeine_delay_hours FLOAT      DEFAULT 2,
    conditions          TEXT[]      DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_health_profiles_user_id ON health_profiles (user_id);

COMMENT ON TABLE health_profiles IS 'Per-user health configuration and targets';
COMMENT ON COLUMN health_profiles.conditions IS 'Array of health conditions (e.g., gerd, gout)';

-- =============================================================================
-- Water Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS water_logs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_ml       INTEGER         NOT NULL,
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    source          TEXT            DEFAULT '',
    is_gout_flush   BOOLEAN         DEFAULT false,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_water_logs_user_id   ON water_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_water_logs_logged_at ON water_logs (user_id, logged_at);

COMMENT ON TABLE water_logs IS 'Water intake tracking entries';

-- =============================================================================
-- Meal Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS meal_logs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT            NOT NULL DEFAULT '',
    is_safe         BOOLEAN         DEFAULT true,
    category        TEXT            DEFAULT '',
    triggers        TEXT[]          DEFAULT '{}',
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    notes           TEXT            DEFAULT '',
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_meal_logs_user_id   ON meal_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_meal_logs_logged_at ON meal_logs (user_id, logged_at);

COMMENT ON TABLE meal_logs IS 'Meal tracking with GERD safety and trigger analysis';

-- =============================================================================
-- Caffeine Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS caffeine_logs (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    drink_type              TEXT        NOT NULL DEFAULT '',
    is_clean                BOOLEAN     DEFAULT true,
    caffeine_mg             FLOAT       DEFAULT 0,
    sugar_g                 FLOAT       DEFAULT 0,
    logged_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    within_cortisol_window  BOOLEAN     DEFAULT false,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_caffeine_logs_user_id   ON caffeine_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_caffeine_logs_logged_at ON caffeine_logs (user_id, logged_at);

COMMENT ON TABLE caffeine_logs IS 'Caffeine intake tracking with cortisol window awareness';

-- =============================================================================
-- Pomodoro Sessions
-- =============================================================================

CREATE TABLE IF NOT EXISTS pomodoro_sessions (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at            TIMESTAMPTZ,
    duration_min        INTEGER     DEFAULT 25,
    break_duration_min  INTEGER     DEFAULT 5,
    type                TEXT        DEFAULT 'work'
                                    CHECK (type IN ('work', 'short_break', 'long_break')),
    completed           BOOLEAN     DEFAULT false,
    stood_up            BOOLEAN     DEFAULT false,
    walked_min          INTEGER     DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pomodoro_sessions_user_id    ON pomodoro_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_pomodoro_sessions_started_at ON pomodoro_sessions (user_id, started_at);

COMMENT ON TABLE pomodoro_sessions IS 'Pomodoro timer sessions with movement tracking';

-- =============================================================================
-- Sleep Configs
-- =============================================================================

CREATE TABLE IF NOT EXISTS sleep_configs (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_bedtime          TEXT        DEFAULT '23:00',
    shutdown_started_at     TIMESTAMPTZ,
    shutdown_active         BOOLEAN     DEFAULT false,
    last_meal_at            TIMESTAMPTZ,
    allowed_items           TEXT[]      DEFAULT '{}',
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sleep_configs_user_id ON sleep_configs (user_id);

COMMENT ON TABLE sleep_configs IS 'Sleep hygiene configuration and shutdown state';

-- =============================================================================
-- Sleep Logs
-- =============================================================================

CREATE TABLE IF NOT EXISTS sleep_logs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    duration_hours  FLOAT           DEFAULT 0,
    quality_score   INTEGER         DEFAULT 0
                                    CHECK (quality_score >= 0 AND quality_score <= 10),
    notes           TEXT            DEFAULT '',
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sleep_logs_user_id   ON sleep_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_sleep_logs_logged_at ON sleep_logs (user_id, logged_at);

COMMENT ON TABLE sleep_logs IS 'Daily sleep duration and quality tracking';

-- =============================================================================
-- Health Snapshots (daily aggregates)
-- =============================================================================

CREATE TABLE IF NOT EXISTS health_snapshots (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date                DATE        NOT NULL,
    weight_kg           FLOAT,
    body_fat_pct        FLOAT,
    steps               INTEGER     DEFAULT 0,
    active_energy_cal   FLOAT       DEFAULT 0,
    avg_heart_rate      FLOAT,
    sleep_hours         FLOAT       DEFAULT 0,
    water_ml            INTEGER     DEFAULT 0,
    meals_count         INTEGER     DEFAULT 0,
    caffeine_mg         FLOAT       DEFAULT 0,
    pomodoro_count      INTEGER     DEFAULT 0,
    gerd_safe           BOOLEAN     DEFAULT true,
    nutrition_score     FLOAT       DEFAULT 0,
    caffeine_score      FLOAT       DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_health_snapshots_user_date
    ON health_snapshots (user_id, date);

COMMENT ON TABLE health_snapshots IS 'Daily health metric aggregations for trends and reporting';
