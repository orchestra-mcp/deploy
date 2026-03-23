-- Migration 025: Device codes for RFC 8628 device authorization flow.
-- Used by the device-auth edge function for CLI/headless auth.

CREATE TABLE IF NOT EXISTS device_codes (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_code  TEXT NOT NULL UNIQUE,
    user_code    TEXT NOT NULL UNIQUE,
    status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),
    access_token TEXT,
    expires_at   TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_codes_user_code ON device_codes (user_code) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_device_codes_expires ON device_codes (expires_at);

-- Auto-cleanup expired codes (runs via pg_cron or application-level reaper).
-- For now, the edge function deletes codes after successful token exchange.

-- RLS: Only service_role can access device_codes (edge functions use service key).
ALTER TABLE device_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_all" ON device_codes
    FOR ALL TO service_role USING (true) WITH CHECK (true);
