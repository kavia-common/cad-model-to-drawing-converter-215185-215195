# CAD Database (PostgreSQL)

This container provides the PostgreSQL database for the CAD model to drawing converter platform. It stores users, API keys, uploaded files metadata, conversion jobs, and audit logs.

Contents:
- schema.sql: Full database schema (idempotent).
- startup.sh: Boots PostgreSQL, creates database/user, applies schema.
- backup_db.sh and restore_db.sh: Utilities to back up/restore the database.
- db_visualizer/: Simple DB viewer helper with env file.

## Quick start

1) Start the database and apply the schema:
   ./startup.sh

2) Connection info:
   - psql command: stored in db_connection.txt
   - DATABASE_URL: stored in DATABASE_URL.txt
   - Visualizer env: db_visualizer/postgres.env

Default credentials (for local dev):
- DB: myapp
- User: appuser
- Password: dbuser123
- Port: 5000

Connection URL example:
postgresql://appuser:dbuser123@localhost:5000/myapp

Note: These are development defaults. In production, provide secure values.

## Environment variables

This container publishes the following variables for tools:
- POSTGRES_URL
- POSTGRES_USER
- POSTGRES_PASSWORD
- POSTGRES_DB
- POSTGRES_PORT

These are also written to db_visualizer/postgres.env for convenience. For application services, define:
- DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DB

Do not hardcode credentials; use your orchestrator to supply them.

## Schema overview

Tables and types:
- users: End users and admins. Unique email, password_hash, flags, timestamps.
- api_keys: Per-user API key metadata. Stores salted/hashed keys (api_key_hash), searchable by prefix and last four.
- files: Metadata about uploaded CAD files and generated artifacts (PDF, DXF, previews, logs). Tracks size, checksum, kind, and metadata JSONB.
- jobs: Conversion jobs linking input files to outputs with status, priority, timing, settings JSONB.
- audit_logs: Security and activity log for traceability.

Enums:
- file_kind: source | preview | drawing_pdf | drawing_dxf | log
- job_status: queued | running | succeeded | failed | canceled
- audit_action: login | logout | upload | download | convert_start | convert_finish | convert_fail | apikey_create | apikey_revoke | permissions_update | delete

Indexes:
- Appropriate indexes on foreign keys, timestamps, status, kind, JSONB GIN indexes for metadata/settings.

Idempotency:
- schema.sql uses IF NOT EXISTS guards and can be executed repeatedly.

## Applying schema

startup.sh will automatically apply schema.sql using:
psql -h localhost -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -f schema.sql

It first attempts with application user to ensure correct ownership, then falls back to postgres superuser if needed. The operation is idempotent.

You can also apply manually:
PGPASSWORD="$POSTGRES_PASSWORD" psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema.sql

## Backend integration

The backend container (FastAPI) should use the DATABASE_URL environment variable to connect. Example FastAPI settings:

- Env var: DATABASE_URL (required)
- Example: DATABASE_URL=postgresql://appuser:dbuser123@cad_database:5000/myapp

ORM compatibility:
- SQLAlchemy / asyncpg / psycopg2 can use this URL.
- Ensure the driver is present if using dialect-specific URLs (e.g., postgresql+psycopg2://).

Migrations:
- This project provides a baseline schema via schema.sql. If you later introduce Alembic or another migration tool, point it to the same DATABASE_URL and manage versioning there.

## Security notes

- In production, do not commit real API key material. Only hashes are stored (api_key_hash).
- Rotate credentials and restrict network access.
- Consider enabling TLS for database connections and auditing logs externally.

## Utilities

Backup:
./backup_db.sh

Restore:
./restore_db.sh

Visualizer:
source db_visualizer/postgres.env
node cad_database/db_visualizer/server.js --host 0.0.0.0

This starts a small viewer for development convenience.
