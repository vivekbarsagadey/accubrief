# Database Schema - AccuBrief

## Overview

AccuBrief uses PostgreSQL as the primary database for storing metadata about sessions, participants, recordings, summaries, and digital signatures. This document describes the complete database schema, relationships, and migration strategy.

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                     │
│  ┌──────────────┐         ┌──────────────────┐         ┌─────────────────┐         │
│  │    Tenant    │────────<│     Session      │>───────<│   Participant   │         │
│  └──────────────┘         └──────────────────┘         └─────────────────┘         │
│         │                         │                                                 │
│         │                         │                                                 │
│         │                         ├────────────<┌─────────────────┐                │
│         │                         │             │    Recording    │                │
│         │                         │             └─────────────────┘                │
│         │                         │                                                 │
│         │                         └────────────<┌─────────────────┐                │
│         │                                       │     Summary     │                │
│         │                                       └────────┬────────┘                │
│         │                                                │                          │
│         │                                                │                          │
│         │                                                ▼                          │
│         │                                       ┌─────────────────┐                │
│         │                                       │    Signature    │                │
│         │                                       └────────┬────────┘                │
│         │                                                │                          │
│         │                                                ▼                          │
│         └───────────────────────────────────────┌─────────────────┐                │
│                                                 │   SigningKey    │                │
│                                                 └─────────────────┘                │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

Legend:
  ───< : One-to-Many relationship
  >─── : Many-to-One relationship
```

## Tables

### 1. tenants

Stores tenant/organization information for multi-tenancy.

```sql
CREATE TABLE tenants (
    id              VARCHAR(36) PRIMARY KEY,              -- 'ten_xxx'
    name            VARCHAR(255) NOT NULL,
    api_key_hash    VARCHAR(64) NOT NULL UNIQUE,          -- SHA-256 of API key
    webhook_url     TEXT,
    webhook_secret  VARCHAR(64),                          -- For HMAC signing
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Audit fields
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE,
    created_by      VARCHAR(36),
    updated_by      VARCHAR(36),
    deleted_by      VARCHAR(36),
    
    -- Indexes
    CONSTRAINT tenants_api_key_hash_unique UNIQUE (api_key_hash)
);

CREATE INDEX idx_tenants_is_active ON tenants(is_active) WHERE deleted_at IS NULL;
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'ten_' prefix |
| name | VARCHAR(255) | No | Organization name |
| api_key_hash | VARCHAR(64) | No | SHA-256 hash of API key |
| webhook_url | TEXT | Yes | Default webhook URL |
| webhook_secret | VARCHAR(64) | Yes | Secret for webhook HMAC |
| is_active | BOOLEAN | No | Tenant active status |

---

### 2. sessions

Stores video session information.

```sql
CREATE TYPE session_status AS ENUM (
    'scheduled',
    'active',
    'ended',
    'processing',
    'completed',
    'failed'
);

CREATE TABLE sessions (
    id                      VARCHAR(36) PRIMARY KEY,      -- 'sess_xxx'
    tenant_id               VARCHAR(36) NOT NULL REFERENCES tenants(id),
    status                  session_status NOT NULL DEFAULT 'scheduled',
    
    -- Configuration
    auto_start_recording    BOOLEAN NOT NULL DEFAULT TRUE,
    webhook_url             TEXT,                         -- Override tenant webhook
    
    -- Timestamps
    created_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    started_at              TIMESTAMP WITH TIME ZONE,
    ended_at                TIMESTAMP WITH TIME ZONE,
    updated_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Audit fields
    deleted_at              TIMESTAMP WITH TIME ZONE,
    created_by              VARCHAR(36),
    updated_by              VARCHAR(36),
    deleted_by              VARCHAR(36),
    
    -- Constraints
    CONSTRAINT fk_sessions_tenant FOREIGN KEY (tenant_id) 
        REFERENCES tenants(id) ON DELETE RESTRICT
);

CREATE INDEX idx_sessions_tenant_id ON sessions(tenant_id);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_created_at ON sessions(created_at DESC);
CREATE INDEX idx_sessions_tenant_status ON sessions(tenant_id, status) 
    WHERE deleted_at IS NULL;
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'sess_' prefix |
| tenant_id | VARCHAR(36) | No | Foreign key to tenants |
| status | session_status | No | Current session status |
| auto_start_recording | BOOLEAN | No | Auto-start recording flag |
| webhook_url | TEXT | Yes | Session-specific webhook URL |
| started_at | TIMESTAMP | Yes | When session became active |
| ended_at | TIMESTAMP | Yes | When session was ended |

---

### 3. participants

Stores participant information for each session.

```sql
CREATE TYPE participant_role AS ENUM ('host', 'client');

CREATE TABLE participants (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'part_xxx'
    session_id          VARCHAR(36) NOT NULL REFERENCES sessions(id),
    name                VARCHAR(255) NOT NULL,
    role                participant_role NOT NULL,
    external_user_id    VARCHAR(255),                     -- Host app's user ID
    
    -- Connection info
    joined_at           TIMESTAMP WITH TIME ZONE,
    left_at             TIMESTAMP WITH TIME ZONE,
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_participants_session FOREIGN KEY (session_id) 
        REFERENCES sessions(id) ON DELETE CASCADE,
    CONSTRAINT uq_participants_session_role UNIQUE (session_id, role)
);

CREATE INDEX idx_participants_session_id ON participants(session_id);
CREATE INDEX idx_participants_external_user ON participants(external_user_id);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'part_' prefix |
| session_id | VARCHAR(36) | No | Foreign key to sessions |
| name | VARCHAR(255) | No | Display name |
| role | participant_role | No | 'host' or 'client' |
| external_user_id | VARCHAR(255) | Yes | Integrator's user ID |
| joined_at | TIMESTAMP | Yes | When participant joined |
| left_at | TIMESTAMP | Yes | When participant left |

---

### 4. recordings

Stores recording metadata (actual files in object storage).

```sql
CREATE TYPE recording_status AS ENUM ('uploading', 'uploaded', 'processing', 'processed', 'failed');

CREATE TABLE recordings (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'rec_xxx'
    session_id          VARCHAR(36) NOT NULL REFERENCES sessions(id),
    tenant_id           VARCHAR(36) NOT NULL REFERENCES tenants(id),
    
    -- File info
    file_path           TEXT NOT NULL,                    -- S3/MinIO path
    file_size           BIGINT,                           -- Size in bytes
    mime_type           VARCHAR(100) NOT NULL DEFAULT 'video/webm',
    duration_seconds    INTEGER,                          -- Duration in seconds
    
    -- Status
    status              recording_status NOT NULL DEFAULT 'uploading',
    error_message       TEXT,
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE,
    created_by          VARCHAR(36),
    updated_by          VARCHAR(36),
    deleted_by          VARCHAR(36),
    
    -- Constraints
    CONSTRAINT fk_recordings_session FOREIGN KEY (session_id) 
        REFERENCES sessions(id) ON DELETE RESTRICT,
    CONSTRAINT fk_recordings_tenant FOREIGN KEY (tenant_id) 
        REFERENCES tenants(id) ON DELETE RESTRICT
);

CREATE INDEX idx_recordings_session_id ON recordings(session_id);
CREATE INDEX idx_recordings_tenant_id ON recordings(tenant_id);
CREATE INDEX idx_recordings_status ON recordings(status);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'rec_' prefix |
| session_id | VARCHAR(36) | No | Foreign key to sessions |
| tenant_id | VARCHAR(36) | No | Foreign key to tenants |
| file_path | TEXT | No | S3/MinIO object path |
| file_size | BIGINT | Yes | File size in bytes |
| mime_type | VARCHAR(100) | No | MIME type (video/webm, etc.) |
| duration_seconds | INTEGER | Yes | Recording duration |
| status | recording_status | No | Processing status |

---

### 5. summaries

Stores AI-generated summary information.

```sql
CREATE TYPE summary_status AS ENUM ('pending', 'processing', 'ready', 'failed');

CREATE TABLE summaries (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'sum_xxx'
    session_id          VARCHAR(36) NOT NULL REFERENCES sessions(id),
    tenant_id           VARCHAR(36) NOT NULL REFERENCES tenants(id),
    
    -- Content
    json_data           JSONB NOT NULL,                   -- Structured summary
    pdf_path            TEXT,                             -- S3 path to PDF
    
    -- Metadata
    language            VARCHAR(10) DEFAULT 'en',
    word_count          INTEGER,
    
    -- Status
    status              summary_status NOT NULL DEFAULT 'pending',
    signed              BOOLEAN NOT NULL DEFAULT FALSE,
    signature_id        VARCHAR(36) REFERENCES signatures(id),
    
    -- Timestamps
    generated_at        TIMESTAMP WITH TIME ZONE,
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE,
    created_by          VARCHAR(36),
    updated_by          VARCHAR(36),
    deleted_by          VARCHAR(36),
    
    -- Constraints
    CONSTRAINT fk_summaries_session FOREIGN KEY (session_id) 
        REFERENCES sessions(id) ON DELETE RESTRICT,
    CONSTRAINT fk_summaries_tenant FOREIGN KEY (tenant_id) 
        REFERENCES tenants(id) ON DELETE RESTRICT
);

CREATE INDEX idx_summaries_session_id ON summaries(session_id);
CREATE INDEX idx_summaries_tenant_id ON summaries(tenant_id);
CREATE INDEX idx_summaries_status ON summaries(status);
CREATE INDEX idx_summaries_signed ON summaries(signed);

-- GIN index for JSONB queries
CREATE INDEX idx_summaries_json_data ON summaries USING GIN (json_data);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'sum_' prefix |
| session_id | VARCHAR(36) | No | Foreign key to sessions |
| tenant_id | VARCHAR(36) | No | Foreign key to tenants |
| json_data | JSONB | No | Structured summary content |
| pdf_path | TEXT | Yes | S3 path to generated PDF |
| status | summary_status | No | Generation status |
| signed | BOOLEAN | No | Whether summary is signed |
| signature_id | VARCHAR(36) | Yes | Foreign key to signatures |
| generated_at | TIMESTAMP | Yes | When summary was generated |

#### json_data Structure

```json
{
  "conversationOverview": "Summary text...",
  "participants": [
    {"name": "Dr. Smith", "role": "host", "speakerId": "Speaker 1"}
  ],
  "questionsAndAnswers": [
    {"question": "...", "askedBy": "Speaker 1", "answer": "...", "answeredBy": "Speaker 2"}
  ],
  "decisions": ["Decision 1", "Decision 2"],
  "actionItems": [
    {"action": "...", "assignedTo": "...", "dueDate": "2025-01-01"}
  ]
}
```

---

### 6. signing_keys

Stores RSA public keys for signature verification.

```sql
CREATE TABLE signing_keys (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'key_xxx'
    tenant_id           VARCHAR(36) REFERENCES tenants(id), -- NULL for global keys
    
    -- Key data
    public_key_pem      TEXT NOT NULL,                    -- PEM encoded public key
    algorithm           VARCHAR(20) NOT NULL DEFAULT 'RS256',
    key_size            INTEGER NOT NULL DEFAULT 2048,
    
    -- Lifecycle
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    revoked_at          TIMESTAMP WITH TIME ZONE,
    revocation_reason   TEXT,
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by          VARCHAR(36),
    updated_by          VARCHAR(36)
);

CREATE INDEX idx_signing_keys_is_active ON signing_keys(is_active);
CREATE INDEX idx_signing_keys_tenant_id ON signing_keys(tenant_id);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'key_' prefix |
| tenant_id | VARCHAR(36) | Yes | NULL for global, FK for tenant-specific |
| public_key_pem | TEXT | No | PEM-encoded public key |
| algorithm | VARCHAR(20) | No | Signing algorithm (RS256) |
| key_size | INTEGER | No | Key size in bits (2048) |
| is_active | BOOLEAN | No | Whether key is active for signing |
| expires_at | TIMESTAMP | Yes | Key expiration time |
| revoked_at | TIMESTAMP | Yes | When key was revoked |

---

### 7. signatures

Stores digital signatures for summaries.

```sql
CREATE TABLE signatures (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'sig_xxx'
    summary_id          VARCHAR(36) NOT NULL REFERENCES summaries(id),
    public_key_id       VARCHAR(36) NOT NULL REFERENCES signing_keys(id),
    
    -- Signature data
    document_hash       VARCHAR(100) NOT NULL,            -- 'SHA256:...'
    signature_value     TEXT NOT NULL,                    -- Base64 encoded
    algorithm           VARCHAR(20) NOT NULL DEFAULT 'RS256',
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_signatures_summary FOREIGN KEY (summary_id) 
        REFERENCES summaries(id) ON DELETE RESTRICT,
    CONSTRAINT fk_signatures_public_key FOREIGN KEY (public_key_id) 
        REFERENCES signing_keys(id) ON DELETE RESTRICT,
    CONSTRAINT uq_signatures_summary UNIQUE (summary_id)
);

CREATE INDEX idx_signatures_summary_id ON signatures(summary_id);
CREATE INDEX idx_signatures_public_key_id ON signatures(public_key_id);
CREATE INDEX idx_signatures_document_hash ON signatures(document_hash);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'sig_' prefix |
| summary_id | VARCHAR(36) | No | Foreign key to summaries |
| public_key_id | VARCHAR(36) | No | Foreign key to signing_keys |
| document_hash | VARCHAR(100) | No | SHA256 hash (SHA256:xxx) |
| signature_value | TEXT | No | Base64-encoded signature |
| algorithm | VARCHAR(20) | No | Algorithm used (RS256) |

---

### 8. webhook_deliveries

Tracks webhook delivery attempts for debugging and retry.

```sql
CREATE TYPE delivery_status AS ENUM ('pending', 'success', 'failed', 'retrying');

CREATE TABLE webhook_deliveries (
    id                  VARCHAR(36) PRIMARY KEY,          -- 'whd_xxx'
    tenant_id           VARCHAR(36) NOT NULL REFERENCES tenants(id),
    session_id          VARCHAR(36) REFERENCES sessions(id),
    
    -- Event info
    event_type          VARCHAR(50) NOT NULL,             -- 'summary.ready', etc.
    payload             JSONB NOT NULL,
    webhook_url         TEXT NOT NULL,
    
    -- Delivery status
    status              delivery_status NOT NULL DEFAULT 'pending',
    attempt_count       INTEGER NOT NULL DEFAULT 0,
    last_attempt_at     TIMESTAMP WITH TIME ZONE,
    next_attempt_at     TIMESTAMP WITH TIME ZONE,
    
    -- Response info
    response_status     INTEGER,                          -- HTTP status code
    response_body       TEXT,
    error_message       TEXT,
    
    -- Audit fields
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhook_deliveries_tenant ON webhook_deliveries(tenant_id);
CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(status);
CREATE INDEX idx_webhook_deliveries_next_attempt ON webhook_deliveries(next_attempt_at) 
    WHERE status IN ('pending', 'retrying');
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | VARCHAR(36) | No | Primary key with 'whd_' prefix |
| tenant_id | VARCHAR(36) | No | Foreign key to tenants |
| event_type | VARCHAR(50) | No | Event type (summary.ready, etc.) |
| payload | JSONB | No | Webhook payload |
| webhook_url | TEXT | No | Target URL |
| status | delivery_status | No | Delivery status |
| attempt_count | INTEGER | No | Number of delivery attempts |
| response_status | INTEGER | Yes | HTTP response code |

---

## Views

### active_sessions

View for querying non-deleted sessions with participant info.

```sql
CREATE VIEW active_sessions AS
SELECT 
    s.id,
    s.tenant_id,
    s.status,
    s.created_at,
    s.started_at,
    s.ended_at,
    h.name AS host_name,
    h.external_user_id AS host_external_id,
    c.name AS client_name,
    c.external_user_id AS client_external_id
FROM sessions s
LEFT JOIN participants h ON s.id = h.session_id AND h.role = 'host'
LEFT JOIN participants c ON s.id = c.session_id AND c.role = 'client'
WHERE s.deleted_at IS NULL;
```

### summary_with_signature

View for querying summaries with signature metadata.

```sql
CREATE VIEW summary_with_signature AS
SELECT 
    su.id,
    su.session_id,
    su.tenant_id,
    su.json_data,
    su.pdf_path,
    su.status,
    su.signed,
    su.generated_at,
    si.id AS signature_id,
    si.document_hash,
    si.algorithm,
    si.created_at AS signed_at,
    sk.id AS public_key_id,
    sk.public_key_pem
FROM summaries su
LEFT JOIN signatures si ON su.id = si.summary_id
LEFT JOIN signing_keys sk ON si.public_key_id = sk.id
WHERE su.deleted_at IS NULL;
```

---

## Functions and Triggers

### Update timestamp trigger

Automatically update `updated_at` on row modification.

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply to all tables with updated_at
CREATE TRIGGER update_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sessions_updated_at
    BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_recordings_updated_at
    BEFORE UPDATE ON recordings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_summaries_updated_at
    BEFORE UPDATE ON summaries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

### ID generation function

Generate prefixed IDs.

```sql
CREATE OR REPLACE FUNCTION generate_prefixed_id(prefix TEXT)
RETURNS TEXT AS $$
DECLARE
    random_part TEXT;
BEGIN
    -- Generate 20 character alphanumeric string
    SELECT string_agg(substr('abcdefghijklmnopqrstuvwxyz0123456789', 
           floor(random() * 36 + 1)::int, 1), '')
    INTO random_part
    FROM generate_series(1, 20);
    
    RETURN prefix || '_' || random_part;
END;
$$ LANGUAGE plpgsql;
```

---

## Indexes Summary

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| tenants | idx_tenants_is_active | is_active | Filter active tenants |
| sessions | idx_sessions_tenant_id | tenant_id | Tenant filtering |
| sessions | idx_sessions_status | status | Status filtering |
| sessions | idx_sessions_tenant_status | tenant_id, status | Multi-tenant queries |
| participants | idx_participants_session_id | session_id | Session lookup |
| recordings | idx_recordings_session_id | session_id | Session lookup |
| summaries | idx_summaries_session_id | session_id | Session lookup |
| summaries | idx_summaries_json_data | json_data (GIN) | JSONB queries |
| signatures | idx_signatures_document_hash | document_hash | Hash lookup |

---

## Migrations

### Migration Naming Convention

```
YYYYMMDD_HHMMSS_description.sql

Examples:
20251207_100000_create_tenants_table.sql
20251207_100100_create_sessions_table.sql
20251207_100200_create_participants_table.sql
```

### Alembic Migration Example

```python
# migrations/versions/20251207_100000_create_tenants_table.py

"""Create tenants table

Revision ID: 20251207100000
Revises: 
Create Date: 2025-12-07

"""
from alembic import op
import sqlalchemy as sa

revision = '20251207100000'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'tenants',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('api_key_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('webhook_url', sa.Text),
        sa.Column('webhook_secret', sa.String(64)),
        sa.Column('is_active', sa.Boolean, nullable=False, default=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('deleted_at', sa.DateTime(timezone=True)),
        sa.Column('created_by', sa.String(36)),
        sa.Column('updated_by', sa.String(36)),
        sa.Column('deleted_by', sa.String(36)),
    )
    
    op.create_index('idx_tenants_is_active', 'tenants', ['is_active'])

def downgrade():
    op.drop_index('idx_tenants_is_active')
    op.drop_table('tenants')
```

---

## Data Retention

### Soft Delete Policy

All tables with `deleted_at` column support soft delete:

```sql
-- Soft delete a session
UPDATE sessions 
SET deleted_at = NOW(), 
    deleted_by = 'user_id' 
WHERE id = 'sess_xxx';

-- Query excludes deleted records by default
SELECT * FROM sessions WHERE deleted_at IS NULL;
```

### Retention Periods

| Data Type | Retention | Rationale |
|-----------|-----------|-----------|
| Sessions | 7 years | Legal compliance |
| Recordings | 1 year | Storage cost |
| Summaries | 7 years | Legal documentation |
| Signatures | Indefinite | Verification support |
| Webhook logs | 90 days | Debugging |

### Cleanup Job

```sql
-- Archive old webhook deliveries
DELETE FROM webhook_deliveries 
WHERE created_at < NOW() - INTERVAL '90 days' 
  AND status IN ('success', 'failed');

-- Mark old recordings for deletion
UPDATE recordings
SET status = 'archived'
WHERE created_at < NOW() - INTERVAL '1 year'
  AND status = 'processed';
```

---

## Performance Considerations

### Connection Pooling

Use PgBouncer or similar for connection pooling:

```
# pgbouncer.ini
[databases]
accubrief = host=localhost dbname=accubrief

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
```

### Query Optimization

**Always include tenant_id in WHERE clause:**

```sql
-- ✅ Good: Uses index
SELECT * FROM sessions 
WHERE tenant_id = 'ten_xxx' AND status = 'active';

-- ❌ Bad: Full table scan
SELECT * FROM sessions WHERE status = 'active';
```

**Use JSONB operators efficiently:**

```sql
-- ✅ Good: Uses GIN index
SELECT * FROM summaries 
WHERE json_data @> '{"participants": [{"role": "host"}]}';

-- ❌ Bad: No index usage
SELECT * FROM summaries 
WHERE json_data::text LIKE '%host%';
```

---

## Backup Strategy

### Daily Backups

```bash
#!/bin/bash
# Backup script
DATE=$(date +%Y%m%d)
pg_dump -Fc accubrief > /backups/accubrief_${DATE}.dump

# Upload to S3
aws s3 cp /backups/accubrief_${DATE}.dump s3://backups/db/
```

### Point-in-Time Recovery

```bash
# Enable WAL archiving in postgresql.conf
archive_mode = on
archive_command = 'aws s3 cp %p s3://wal-archive/%f'
```
