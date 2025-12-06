```chatagent
# AccuBrief Agent Context

> **For AI Agents**: This file contains AccuBrief-specific context that all agents should be aware of. Modern LLMs already know Python, FastAPI, React, and TypeScript fundamentals - this document focuses ONLY on what makes AccuBrief unique.

## Project Identity

**AccuBrief**: Pluggable Video Communication + AI Summarization + Digital Signature System  
**Stack**: FastAPI (Python 3.11+) • React/TypeScript • WebRTC • PostgreSQL • Redis  
**Primary Instruction File**: `.github/instructions/accubrief-rules.instructions.md`

---

## Critical AccuBrief-Specific Patterns

### 1. Multi-Tenancy Architecture

**Every query MUST filter by `tenant_id`:**

```python
# ❌ FORBIDDEN - Data leakage vulnerability
sessions = db.query(Session).all()

# ✅ REQUIRED
sessions = db.query(Session).filter(
    Session.tenant_id == tenant.id,
    Session.status != "DELETED"
).all()
```

**Hierarchy:**
```
Tenant (Host Application)
  └── Sessions (Video calls)
       ├── Participants (Host + Client)
       ├── Recordings (Audio/Video files)
       └── Summary (AI-generated + digitally signed)
```

### 2. Mandatory Soft Delete

**Hard delete is FORBIDDEN:**

```python
# ❌ NEVER USE - Violates audit requirements
db.delete(session)

# ✅ ALWAYS USE
session.status = "DELETED"
session.deleted_at = datetime.utcnow()
session.deleted_by = user_id
db.commit()
```

### 3. Required Audit Fields

**Every model must have:**

```python
class BaseModel:
    id              # Primary key (prefixed: sess_, sum_, sig_, rec_)
    tenant_id       # REQUIRED for multi-tenancy
    
    # Timestamps
    created_at      # Auto-set on creation
    updated_at      # Auto-update on modification
    deleted_at      # Soft delete timestamp
    
    # User tracking
    created_by      # User who created
    updated_by      # User who last updated
    deleted_by      # User who deleted
    
    # Status
    status          # ACTIVE, DELETED, etc.
```

### 4. Digital Signature Integrity

**All summaries MUST be digitally signed:**

```python
# REQUIRED signature flow
1. Canonicalize JSON (sorted keys, compact)
2. Compute SHA-256 hash
3. Sign with RSA private key (PKCS1v15)
4. Store signature metadata:
   - signature_id: "sig_xxx"
   - public_key_id: "key_xxx"
   - document_hash: "SHA256:abc..."
   - signature_value: "base64..."
   - algorithm: "RS256"
5. NEVER modify signed content
```

### 5. Functional Service Pattern

**AccuBrief uses functional composition:**

```python
# ✅ REQUIRED - Functional service factory
def create_session_service(db: Session):
    def create_session(request, tenant_id):
        # Implementation
        pass
    
    def get_session(session_id, tenant_id):
        # Implementation
        pass
    
    return {
        "create_session": create_session,
        "get_session": get_session,
    }

# Usage
service = create_session_service(db)
session = service["create_session"](request, tenant_id)
```

### 6. API Key + JWT Authentication

**Server-to-Server: API Key**
```python
async def get_current_tenant(x_api_key: str = Header(...)):
    tenant = validate_api_key(x_api_key)
    if not tenant:
        raise HTTPException(status_code=401)
    return tenant
```

**Widget Access: JWT Token**
```python
def create_join_token(session_id: str, role: str, tenant_id: str) -> str:
    return jwt.encode({
        "session_id": session_id,
        "role": role,  # "host" or "client"
        "tenant_id": tenant_id,
        "exp": datetime.utcnow() + timedelta(minutes=15)
    }, settings.jwt_secret, algorithm="HS256")
```

---

## System Architecture

### Main Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Host System (CRM/App)                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                    REST APIs + Webhooks
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AccuBrief API (FastAPI)                     │
│         /v1/sessions • /v1/summaries • /v1/signatures          │
└─────────────────────────────────────────────────────────────────┘
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│WebRTC Widget │     │ AI Pipeline  │     │Digital Sig.  │
│  (React/TS)  │     │STT+LLM+PDF   │     │   Engine     │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Directory Structure

```
backend/app/
├── api/v1/          # FastAPI routes
├── services/        # Business logic (functional)
├── crypto/          # Digital signature
├── models/          # SQLAlchemy models
├── schemas/         # Pydantic schemas
├── workers/         # Async job processing
└── utils/           # Helpers (storage, PDF, audio)

frontend-widget/src/
├── components/      # React components
├── hooks/           # Custom hooks (WebRTC, signaling)
├── pages/           # Widget page
└── utils/           # API client, config
```

---

## Key Workflows

### Session Creation Flow
1. Host app calls `POST /v1/sessions`
2. Backend creates session + participants
3. Returns widget URLs with JWT tokens
4. Users join via widget (WebRTC)

### AI Summary Pipeline
1. Recording uploaded after session ends
2. Worker: STT → Diarization → LLM summary
3. Generate structured JSON + PDF
4. Digitally sign the summary
5. Send webhook `summary.ready`

### Signature Verification
1. External system calls `/v1/signatures/verify`
2. Backend: Re-hash document, verify RSA signature
3. Return `isValid`, `documentHash`, `reason`

---

## ID Prefixes

| Entity | Prefix | Example |
|--------|--------|---------|
| Session | `sess_` | `sess_abc123` |
| Recording | `rec_` | `rec_xyz789` |
| Summary | `sum_` | `sum_def456` |
| Signature | `sig_` | `sig_ghi012` |
| Signing Key | `key_` | `key_main001` |

---

## Webhook Events

| Event | Trigger |
|-------|---------|
| `session.started` | WebRTC connection established |
| `session.ended` | Call terminated |
| `summary.processing` | AI pipeline started |
| `summary.ready` | Summary signed and available |
| `summary.failed` | Pipeline error |

---

## Reference Documentation

- `.github/instructions/accubrief-rules.instructions.md` - Project rules & patterns
- `/docs/design-document.md` - HLD + LLD
- `/docs/srs.md` - Requirements specification
- `/docs/code-details.md` - File/folder documentation
```
