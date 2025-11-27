-- cad_database schema for CAD model to drawing converter
-- This script is idempotent and safe to run multiple times.

-- Extension for UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

-- Trigger to update updated_at on users
CREATE OR REPLACE FUNCTION set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_users_timestamp ON public.users;
CREATE TRIGGER set_users_timestamp
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE PROCEDURE set_timestamp();

-- API KEYS
CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    api_key_hash TEXT NOT NULL,
    prefix TEXT NOT NULL,
    last_four TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_api_key_user_name UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON public.api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_prefix ON public.api_keys(prefix);
CREATE INDEX IF NOT EXISTS idx_api_keys_expires_at ON public.api_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_api_keys_is_revoked ON public.api_keys(is_revoked);

-- FILES (uploaded CAD files and generated artifacts metadata)
CREATE TYPE IF NOT EXISTS file_kind AS ENUM ('source', 'preview', 'drawing_pdf', 'drawing_dxf', 'log');

CREATE TABLE IF NOT EXISTS public.files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    original_filename TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    mime_type TEXT,
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    checksum_sha256 TEXT,
    kind file_kind NOT NULL DEFAULT 'source',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_files_user_id ON public.files(user_id);
CREATE INDEX IF NOT EXISTS idx_files_kind ON public.files(kind);
CREATE INDEX IF NOT EXISTS idx_files_created_at ON public.files(created_at);
CREATE INDEX IF NOT EXISTS idx_files_is_deleted ON public.files(is_deleted);
CREATE INDEX IF NOT EXISTS idx_files_metadata_gin ON public.files USING GIN (metadata);

-- JOBS (conversion jobs)
CREATE TYPE IF NOT EXISTS job_status AS ENUM ('queued', 'running', 'succeeded', 'failed', 'canceled');

CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    input_file_id UUID NOT NULL REFERENCES public.files(id) ON DELETE RESTRICT,
    status job_status NOT NULL DEFAULT 'queued',
    priority INTEGER NOT NULL DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    error_message TEXT,
    output_pdf_file_id UUID REFERENCES public.files(id) ON DELETE SET NULL,
    output_dxf_file_id UUID REFERENCES public.files(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settings JSONB NOT NULL DEFAULT '{}' -- conversion configuration
);

DROP TRIGGER IF EXISTS set_jobs_timestamp ON public.jobs;
CREATE TRIGGER set_jobs_timestamp
BEFORE UPDATE ON public.jobs
FOR EACH ROW
EXECUTE PROCEDURE set_timestamp();

CREATE INDEX IF NOT EXISTS idx_jobs_user_id ON public.jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_jobs_input_file_id ON public.jobs(input_file_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON public.jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON public.jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_settings_gin ON public.jobs USING GIN (settings);

-- AUDIT LOGS (security and actions)
CREATE TYPE IF NOT EXISTS audit_action AS ENUM (
  'login', 'logout', 'upload', 'download', 'convert_start', 'convert_finish', 'convert_fail',
  'apikey_create', 'apikey_revoke', 'permissions_update', 'delete'
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    action audit_action NOT NULL,
    entity_type TEXT,
    entity_id TEXT,
    event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT,
    details JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_time ON public.audit_logs(event_time);
CREATE INDEX IF NOT EXISTS idx_audit_logs_details_gin ON public.audit_logs USING GIN (details);

-- Helpful views
CREATE OR REPLACE VIEW public.v_jobs_overview AS
SELECT
  j.id,
  j.status,
  j.priority,
  j.created_at,
  j.started_at,
  j.finished_at,
  u.email as user_email,
  f.original_filename as input_filename
FROM public.jobs j
LEFT JOIN public.users u ON u.id = j.user_id
LEFT JOIN public.files f ON f.id = j.input_file_id;

-- Seed an admin user placeholder (email unique; only inserted if not exists).
-- Replace password_hash during real deployment.
INSERT INTO public.users (id, email, password_hash, full_name, is_admin)
SELECT uuid_generate_v4(), 'admin@example.com', 'REPLACE_WITH_HASH', 'Administrator', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'admin@example.com');
