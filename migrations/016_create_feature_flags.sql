-- 016_create_feature_flags.sql
-- Feature flags, A/B testing experiments, overrides, and assignments.
-- PostgreSQL-native feature flag evaluation with deterministic hashing.
-- Idempotent: safe to run multiple times.

-- =============================================================================
-- Feature Flags
-- =============================================================================

CREATE TABLE IF NOT EXISTS feature_flags (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    key             TEXT            UNIQUE NOT NULL,
    name            TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    flag_type       TEXT            NOT NULL DEFAULT 'boolean'
                                    CHECK (flag_type IN ('boolean', 'percentage', 'variant', 'user_list')),
    enabled         BOOLEAN         DEFAULT false,
    percentage      INTEGER         DEFAULT 0
                                    CHECK (percentage >= 0 AND percentage <= 100),
    variants        JSONB           DEFAULT '[]',
    user_ids        JSONB           DEFAULT '[]',
    team_ids        JSONB           DEFAULT '[]',
    rules           JSONB           DEFAULT '[]',
    metadata        JSONB           DEFAULT '{}',
    stale_at        TIMESTAMPTZ,
    created_by      BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_key ON feature_flags(key);
CREATE INDEX IF NOT EXISTS idx_feature_flags_enabled ON feature_flags(enabled) WHERE enabled = true;

COMMENT ON TABLE feature_flags IS 'Feature flags for gradual rollout, A/B testing, and kill switches';
COMMENT ON COLUMN feature_flags.key IS 'Unique flag identifier, e.g. dark_mode, new_editor';
COMMENT ON COLUMN feature_flags.flag_type IS 'One of: boolean, percentage, variant, user_list';
COMMENT ON COLUMN feature_flags.variants IS 'For A/B tests: [{"key":"control","weight":50},{"key":"variant_a","weight":50}]';
COMMENT ON COLUMN feature_flags.rules IS 'Advanced targeting rules: [{"attribute":"role","operator":"eq","value":"admin"}]';
COMMENT ON COLUMN feature_flags.stale_at IS 'Date when this flag should be reviewed for cleanup';

-- =============================================================================
-- Feature Flag Overrides (per-user or per-team)
-- =============================================================================

CREATE TABLE IF NOT EXISTS feature_flag_overrides (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_id         UUID            NOT NULL REFERENCES feature_flags(id) ON DELETE CASCADE,
    user_id         BIGINT          REFERENCES users(id) ON DELETE CASCADE,
    team_id         UUID            REFERENCES teams(id) ON DELETE CASCADE,
    variant         TEXT            DEFAULT '',
    enabled         BOOLEAN         NOT NULL,
    reason          TEXT            DEFAULT '',
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    CONSTRAINT chk_override_target CHECK (
        (user_id IS NOT NULL AND team_id IS NULL) OR
        (user_id IS NULL AND team_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_flag_override_user ON feature_flag_overrides(flag_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_flag_override_team ON feature_flag_overrides(flag_id, team_id) WHERE team_id IS NOT NULL;

COMMENT ON TABLE feature_flag_overrides IS 'Per-user or per-team overrides for feature flags';
COMMENT ON COLUMN feature_flag_overrides.reason IS 'Human-readable reason for this override';
COMMENT ON COLUMN feature_flag_overrides.expires_at IS 'Auto-expire override after this timestamp';

-- =============================================================================
-- A/B Test Experiments
-- =============================================================================

CREATE TABLE IF NOT EXISTS experiments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_id         UUID            NOT NULL REFERENCES feature_flags(id) ON DELETE CASCADE,
    name            TEXT            NOT NULL,
    description     TEXT            DEFAULT '',
    hypothesis      TEXT            DEFAULT '',
    status          TEXT            DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'running', 'paused', 'completed', 'archived')),
    start_date      TIMESTAMPTZ,
    end_date        TIMESTAMPTZ,
    target_sample_size INTEGER      DEFAULT 0,
    goals           JSONB           DEFAULT '[]',
    results         JSONB           DEFAULT '{}',
    winner_variant  TEXT            DEFAULT '',
    created_by      BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_experiments_flag ON experiments(flag_id);
CREATE INDEX IF NOT EXISTS idx_experiments_status ON experiments(status) WHERE status = 'running';

COMMENT ON TABLE experiments IS 'A/B test experiments linked to feature flags';
COMMENT ON COLUMN experiments.hypothesis IS 'What the experiment is testing';
COMMENT ON COLUMN experiments.goals IS 'Experiment goals: [{"name":"signup_rate","type":"conversion"},{"name":"revenue","type":"numeric"}]';
COMMENT ON COLUMN experiments.winner_variant IS 'Variant key that won the experiment (set on completion)';

-- =============================================================================
-- Experiment Assignments (sticky user-to-variant mapping)
-- =============================================================================

CREATE TABLE IF NOT EXISTS experiment_assignments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id   UUID            NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    variant         TEXT            NOT NULL,
    assigned_at     TIMESTAMPTZ     DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_experiment_assignment_user ON experiment_assignments(experiment_id, user_id);

COMMENT ON TABLE experiment_assignments IS 'Sticky assignment of users to experiment variants';

-- =============================================================================
-- evaluate_feature_flag() — PostgreSQL function for server-side flag evaluation
-- =============================================================================

CREATE OR REPLACE FUNCTION evaluate_feature_flag(
    p_flag_key TEXT,
    p_user_id BIGINT,
    p_team_id UUID DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_flag RECORD;
    v_override RECORD;
    v_result JSONB;
BEGIN
    -- Get the flag
    SELECT * INTO v_flag FROM feature_flags WHERE key = p_flag_key;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('enabled', false, 'variant', 'control', 'reason', 'flag_not_found');
    END IF;

    -- Global kill switch
    IF NOT v_flag.enabled THEN
        RETURN jsonb_build_object('enabled', false, 'variant', 'control', 'reason', 'globally_disabled');
    END IF;

    -- Check user override first
    SELECT * INTO v_override FROM feature_flag_overrides
    WHERE flag_id = v_flag.id AND user_id = p_user_id
    AND (expires_at IS NULL OR expires_at > NOW());
    IF FOUND THEN
        RETURN jsonb_build_object('enabled', v_override.enabled, 'variant', COALESCE(NULLIF(v_override.variant, ''), 'control'), 'reason', 'user_override');
    END IF;

    -- Check team override
    IF p_team_id IS NOT NULL THEN
        SELECT * INTO v_override FROM feature_flag_overrides
        WHERE flag_id = v_flag.id AND team_id = p_team_id
        AND (expires_at IS NULL OR expires_at > NOW());
        IF FOUND THEN
            RETURN jsonb_build_object('enabled', v_override.enabled, 'variant', COALESCE(NULLIF(v_override.variant, ''), 'control'), 'reason', 'team_override');
        END IF;
    END IF;

    -- Evaluate by flag type
    CASE v_flag.flag_type
        WHEN 'boolean' THEN
            RETURN jsonb_build_object('enabled', true, 'variant', 'control', 'reason', 'boolean_enabled');
        WHEN 'percentage' THEN
            -- Deterministic hash: same user always gets same result for same flag
            IF (abs(hashtext(v_flag.key || '::' || p_user_id::TEXT)) % 100) < v_flag.percentage THEN
                RETURN jsonb_build_object('enabled', true, 'variant', 'control', 'reason', 'percentage_included');
            ELSE
                RETURN jsonb_build_object('enabled', false, 'variant', 'control', 'reason', 'percentage_excluded');
            END IF;
        WHEN 'user_list' THEN
            IF v_flag.user_ids ? p_user_id::TEXT THEN
                RETURN jsonb_build_object('enabled', true, 'variant', 'control', 'reason', 'user_list_match');
            ELSE
                RETURN jsonb_build_object('enabled', false, 'variant', 'control', 'reason', 'user_list_no_match');
            END IF;
        WHEN 'variant' THEN
            -- Deterministic variant assignment based on hash
            DECLARE
                v_variants JSONB;
                v_total_weight INTEGER := 0;
                v_hash_val INTEGER;
                v_cumulative INTEGER := 0;
                v_item JSONB;
            BEGIN
                v_variants := v_flag.variants;
                -- Calculate total weight
                FOR v_item IN SELECT jsonb_array_elements(v_variants) LOOP
                    v_total_weight := v_total_weight + (v_item->>'weight')::INTEGER;
                END LOOP;
                IF v_total_weight = 0 THEN
                    RETURN jsonb_build_object('enabled', true, 'variant', 'control', 'reason', 'no_weights');
                END IF;
                v_hash_val := abs(hashtext(v_flag.key || '::' || p_user_id::TEXT)) % v_total_weight;
                FOR v_item IN SELECT jsonb_array_elements(v_variants) LOOP
                    v_cumulative := v_cumulative + (v_item->>'weight')::INTEGER;
                    IF v_hash_val < v_cumulative THEN
                        RETURN jsonb_build_object('enabled', true, 'variant', v_item->>'key', 'reason', 'variant_assigned');
                    END IF;
                END LOOP;
                RETURN jsonb_build_object('enabled', true, 'variant', 'control', 'reason', 'variant_fallback');
            END;
        ELSE
            RETURN jsonb_build_object('enabled', false, 'variant', 'control', 'reason', 'unknown_flag_type');
    END CASE;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION evaluate_feature_flag IS 'Evaluate a feature flag for a specific user, checking overrides and rules';
