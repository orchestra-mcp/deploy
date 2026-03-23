-- 018_enable_realtime.sql
-- Enable Supabase Realtime publication for tables that need live sync.
-- Only includes tables where real-time updates benefit the user experience.
-- Idempotent: drops and recreates the publication.

BEGIN;

-- Drop if exists to make idempotent
DROP PUBLICATION IF EXISTS supabase_realtime;

-- Create publication with specific tables
CREATE PUBLICATION supabase_realtime FOR TABLE
    -- Core project data (synced across web, mobile, desktop)
    features,
    plans,
    requests,
    notes,
    docs,

    -- AI & sessions
    ai_sessions,
    session_turns,
    delegations,

    -- Team collaboration
    persons,
    tunnels,

    -- Settings & notifications
    notifications,
    user_settings,

    -- Feature flags (for real-time flag evaluation)
    feature_flags,
    feature_flag_overrides,

    -- Community (for live updates)
    community_posts,
    community_likes,
    comments;

COMMENT ON PUBLICATION supabase_realtime IS 'Tables enabled for Supabase Realtime subscriptions';

COMMIT;
