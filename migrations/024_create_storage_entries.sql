-- =============================================================================
-- Migration 024: MCP Storage Entries
--
-- PostgREST-accessible table for MCP storage mirroring.
-- The local MCP CLI writes to markdown files (primary) and mirrors writes
-- to this table via PostgREST (secondary) for cloud sync.
--
-- Path format: "projects/<slug>/features/FEAT-001.md"
-- Content: full markdown body with YAML frontmatter
-- Metadata: structured JSONB (status, priority, labels, etc.)
-- =============================================================================

-- ─── Table ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.storage_entries (
    id          BIGSERIAL PRIMARY KEY,
    workspace   TEXT        NOT NULL,
    path        TEXT        NOT NULL,
    content     TEXT        NOT NULL DEFAULT '',
    metadata    JSONB,
    version     BIGINT      NOT NULL DEFAULT 1,
    size        BIGINT      NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_workspace_path UNIQUE (workspace, path)
);

COMMENT ON TABLE public.storage_entries IS 'MCP storage mirror — cloud copy of local .projects/ markdown files';
COMMENT ON COLUMN public.storage_entries.workspace IS 'Workspace identifier (hashed project path)';
COMMENT ON COLUMN public.storage_entries.path IS 'Storage path, e.g. projects/my-app/features/FEAT-001.md';
COMMENT ON COLUMN public.storage_entries.content IS 'Full markdown body with YAML frontmatter';
COMMENT ON COLUMN public.storage_entries.metadata IS 'Structured fields extracted from frontmatter (status, priority, labels, etc.)';
COMMENT ON COLUMN public.storage_entries.version IS 'Monotonic version counter for optimistic concurrency (CAS)';

-- ─── Indexes ──────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_storage_entries_workspace_path
    ON public.storage_entries (workspace, path);

CREATE INDEX IF NOT EXISTS idx_storage_entries_workspace_prefix
    ON public.storage_entries (workspace, path text_pattern_ops);

CREATE INDEX IF NOT EXISTS idx_storage_entries_metadata
    ON public.storage_entries USING gin (metadata jsonb_path_ops);

-- ─── Auto-increment version on update ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION storage_entries_version_bump()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version := OLD.version + 1;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_storage_entries_version ON public.storage_entries;
CREATE TRIGGER trg_storage_entries_version
    BEFORE UPDATE ON public.storage_entries
    FOR EACH ROW
    EXECUTE FUNCTION storage_entries_version_bump();

-- ─── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE public.storage_entries ENABLE ROW LEVEL SECURITY;

-- Service role can do everything (used by MCP CLI via SERVICE_ROLE_KEY)
CREATE POLICY storage_entries_service_all ON public.storage_entries
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Authenticated users can read entries (for dashboard/web access)
CREATE POLICY storage_entries_auth_select ON public.storage_entries
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- ─── Grant ────────────────────────────────────────────────────────────────────

GRANT SELECT ON public.storage_entries TO authenticated;
GRANT ALL ON public.storage_entries TO service_role;
GRANT USAGE, SELECT ON SEQUENCE storage_entries_id_seq TO service_role;
