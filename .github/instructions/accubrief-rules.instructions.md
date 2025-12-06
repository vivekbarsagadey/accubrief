---
applyTo: '**'
---

# AccuBrief Project-Specific Rules

> **LLM Knowledge Assumption**: This guide assumes you already know Python, FastAPI, React, WebRTC, and common design patterns. It contains **ONLY AccuBrief-specific rules, conventions, and implementations** that differ from standard practices.

**Last Updated**: December 6, 2025  
**Stack**: FastAPI • Python 3.11+ • React/TypeScript • WebRTC • PostgreSQL • Redis

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Critical Policies](#critical-policies)
3. [Project Structure](#project-structure)
4. [Code Patterns](#code-patterns)
5. [Data Models](#data-models)
6. [Security & Compliance](#security--compliance)
7. [Quick Reference](#quick-reference)

---

## 1. Architecture Overview

### System Purpose

AccuBrief is a **pluggable service** that provides:

* **Secure video calls** (via embeddable widget)
* **Recording → AI-powered summaries**
* **Digitally signed summary documents** (non-repudiation)
* **Simple integration via REST + Webhooks + Widget**

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Host System (CRM/App)                      │
│                    REST APIs + Webhooks                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AccuBrief API (FastAPI)                     │
│         Sessions • Summaries • Signatures • Recordings         │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  WebRTC Widget   │ │   AI Pipeline    │ │ Digital Signature│
│  (React/TS)      │ │ (STT+Diarize+LLM)│ │     Engine       │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

### Key Actors

* **Host Application** – CRM/case management/portal integrating AccuBrief
* **Host User** – Lawyer/consultant/doctor conducting sessions
* **Client User** – End customer joining sessions
* **AccuBrief Backend** – FastAPI APIs + signaling + pipeline
* **AccuBrief Widget** – React/WebRTC embeddable UI
* **AI Services** – STT, diarization, LLM summarization

### Technology Stack

| Component | Technology |
|-----------|------------|
| Backend API | FastAPI (Python 3.11+) |
| Database | PostgreSQL |
| Object Storage | MinIO / S3 |
| Queue | Redis (RQ/Celery) |
| Frontend Widget | React + TypeScript + WebRTC |
| STT | Whisper / Deepgram |
| Diarization | Pyannote |
| LLM | OpenAI / Ollama / Self-hosted |
| Digital Signature | In-house RSA (cryptography library) |

---

## 2. Critical Policies

### ⚠️ Policy 1: Multi-Tenancy - Always Filter by tenant_id

**Every database query MUST filter by `tenant_id` for data isolation.**

```python
# ❌ FORBIDDEN - Security vulnerability (data leakage)
sessions = db.query(Session).all()

# ✅ REQUIRED - Tenant isolation
sessions = db.query(Session).filter(
    Session.tenant_id == current_tenant.id
).all()
```

### ⚠️ Policy 2: Soft Delete - NEVER Use Hard Delete

**Recordings and summaries must be recoverable for audit trails.**

```python
# ❌ FORBIDDEN - Will break audit trails
db.delete(session)

# ✅ REQUIRED - Soft delete
session.status = 'DELETED'
session.deleted_at = datetime.utcnow()
session.deleted_by = user_id
db.commit()
```

### ⚠️ Policy 3: Digital Signature Integrity

**Signed summaries MUST be tamper-proof.**

```python
# ✅ REQUIRED - Signature flow
1. Canonicalize JSON (sorted keys, no whitespace)
2. Compute SHA-256 hash
3. Sign with RSA private key (PKCS1v15)
4. Store signature + publicKeyId + documentHash
5. Never modify signed content
```

### ⚠️ Policy 4: Audit Fields on All Models

**Every model MUST have these fields:**

```python
class BaseModel:
    id: str                    # Primary key (e.g., sess_xxx, sum_xxx)
    created_at: datetime       # Auto-set on creation
    updated_at: datetime       # Auto-update on modification
    deleted_at: datetime       # Soft delete timestamp
    created_by: str           # User who created
    updated_by: str           # User who last updated
    deleted_by: str           # User who deleted
    status: str               # ACTIVE, DELETED, etc.
    tenant_id: str            # Multi-tenancy (REQUIRED)
```

### ⚠️ Policy 5: Use Functional Services Over Classes

**AccuBrief Philosophy**: Functional composition by default.

```python
# ✅ PREFERRED - Functional service
def create_session_service(db: Session, settings: Settings):
    def create_session(request: CreateSessionRequest, tenant_id: str) -> Session:
        session = SessionModel(
            tenant_id=tenant_id,
            status="scheduled",
            **request.dict()
        )
        db.add(session)
        db.commit()
        return session
    
    return {
        "create_session": create_session,
        "get_session": get_session,
        "end_session": end_session,
    }

# Usage
session_service = create_session_service(db, settings)
session = session_service["create_session"](request, tenant_id)
```

### ⚠️ Policy 6: Schema Changes Require Synchronization

**When modifying SQLAlchemy models, update all layers:**

1. **SQLAlchemy Model** (`models/*.py`)
2. **Pydantic Schema** (`schemas/*.py`)
3. **Alembic Migration** (`migrations/versions/`)
4. **Service Layer** (`services/*.py`)
5. **API Routes** (`api/v1/*.py`)

```bash
# After model changes:
alembic revision --autogenerate -m "add_new_field"
alembic upgrade head
```

### ⚠️ Policy 7: Never Store Private Keys in Code

```python
# ❌ FORBIDDEN
PRIVATE_KEY = """-----BEGIN RSA PRIVATE KEY-----..."""

# ✅ REQUIRED - Load from environment/KMS
private_key = load_private_key_from_env("SIGNING_PRIVATE_KEY")
```

---

## 3. Project Structure

### Directory Layout

```
accubrief/
├── backend/
│   └── app/
│       ├── main.py              # FastAPI entry point
│       ├── core/
│       │   ├── config.py        # Settings (env vars)
│       │   ├── security.py      # Auth, API keys, JWT
│       │   └── logging.py       # Structured logging
│       ├── api/v1/
│       │   ├── sessions.py      # Session endpoints
│       │   ├── recordings.py    # Recording endpoints
│       │   ├── summaries.py     # Summary endpoints
│       │   └── signatures.py    # Verification endpoints
│       ├── services/
│       │   ├── session_service.py
│       │   ├── recording_service.py
│       │   ├── summary_pipeline_service.py
│       │   ├── transcription_service.py
│       │   ├── diarization_service.py
│       │   ├── llm_summary_service.py
│       │   └── webhook_dispatcher.py
│       ├── crypto/
│       │   ├── kms_service.py          # Key management
│       │   ├── signing_service.py      # Sign summaries
│       │   └── verification_service.py # Verify signatures
│       ├── models/
│       │   ├── db.py                   # Database setup
│       │   ├── session_model.py
│       │   ├── participant_model.py
│       │   ├── recording_model.py
│       │   ├── summary_model.py
│       │   ├── signing_key_model.py
│       │   └── signature_model.py
│       ├── schemas/
│       │   ├── session.py
│       │   ├── recording.py
│       │   ├── summary.py
│       │   └── signature.py
│       ├── workers/
│       │   ├── queue_setup.py
│       │   ├── summary_worker.py
│       │   └── recording_worker.py
│       └── utils/
│           ├── storage.py        # S3/MinIO
│           ├── token_utils.py    # JWT tokens
│           ├── pdf_utils.py      # PDF generation
│           └── audio_utils.py    # Audio processing
├── frontend-widget/
│   └── src/
│       ├── App.tsx
│       ├── components/
│       │   ├── VideoTile.tsx
│       │   ├── ControlsBar.tsx
│       │   ├── RecordingIndicator.tsx
│       │   └── ErrorScreen.tsx
│       ├── hooks/
│       │   ├── useWebRTC.ts
│       │   ├── useSignaling.ts
│       │   └── useSession.ts
│       ├── pages/
│       │   └── Widget.tsx
│       └── utils/
│           ├── api.ts
│           └── config.ts
├── workers/
│   ├── stt_worker/
│   │   └── main.py
│   └── llm_worker/
│       └── main.py
├── shared/
│   └── utils/
│       ├── constants.py
│       ├── logger.py
│       └── types.py
├── infrastructure/
│   ├── docker-compose.yml
│   ├── k8s/
│   └── monitoring/
└── docs/
    ├── design-document.md
    ├── srs.md
    └── integration-guide.md
```

### File Naming Conventions

```
backend/app/api/v1/sessions.py      # API routes (plural)
backend/app/services/session_service.py  # Services (_service suffix)
backend/app/models/session_model.py      # Models (_model suffix)
backend/app/schemas/session.py           # Pydantic schemas
frontend-widget/src/components/VideoTile.tsx  # PascalCase components
frontend-widget/src/hooks/useWebRTC.ts        # camelCase hooks
```

---

## 4. Code Patterns

### API Route Pattern

```python
# api/v1/sessions.py
from fastapi import APIRouter, Depends, HTTPException
from app.core.security import get_current_tenant
from app.schemas.session import CreateSessionRequest, CreateSessionResponse
from app.services.session_service import create_session_service
from app.models.db import get_db

router = APIRouter(prefix="/v1/sessions", tags=["sessions"])

@router.post("/", response_model=CreateSessionResponse)
async def create_session(
    request: CreateSessionRequest,
    tenant = Depends(get_current_tenant),
    db = Depends(get_db)
):
    """Create a new video session."""
    service = create_session_service(db)
    session = service["create_session"](request, tenant.id)
    
    return CreateSessionResponse(
        session_id=session.id,
        widget_urls={
            "host": f"{settings.widget_url}/{session.id}?role=host&token={host_token}",
            "client": f"{settings.widget_url}/{session.id}?role=client&token={client_token}"
        }
    )
```

### Service Pattern

```python
# services/session_service.py
from sqlalchemy.orm import Session
from app.models.session_model import SessionModel
from app.schemas.session import CreateSessionRequest

def create_session_service(db: Session):
    """Factory function returning session operations."""
    
    def create_session(request: CreateSessionRequest, tenant_id: str) -> SessionModel:
        session = SessionModel(
            id=generate_session_id(),
            tenant_id=tenant_id,
            status="scheduled",
            host=request.host.dict(),
            client=request.client.dict(),
            auto_start_recording=request.auto_start_recording,
            webhook_url=request.webhook_url
        )
        db.add(session)
        db.commit()
        db.refresh(session)
        return session
    
    def get_session(session_id: str, tenant_id: str) -> SessionModel:
        return db.query(SessionModel).filter(
            SessionModel.id == session_id,
            SessionModel.tenant_id == tenant_id,
            SessionModel.status != "DELETED"
        ).first()
    
    def end_session(session_id: str, tenant_id: str, user_id: str) -> SessionModel:
        session = get_session(session_id, tenant_id)
        if not session:
            raise ValueError("Session not found")
        
        session.status = "ended"
        session.ended_at = datetime.utcnow()
        session.updated_by = user_id
        db.commit()
        
        # Trigger summary pipeline
        enqueue_summary_job(session_id)
        
        return session
    
    return {
        "create_session": create_session,
        "get_session": get_session,
        "end_session": end_session,
    }
```

### Pydantic Schema Pattern

```python
# schemas/session.py
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class ParticipantSchema(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    external_user_id: Optional[str] = None

class CreateSessionRequest(BaseModel):
    host: ParticipantSchema
    client: ParticipantSchema
    auto_start_recording: bool = True
    webhook_url: Optional[str] = None

class CreateSessionResponse(BaseModel):
    session_id: str
    widget_urls: dict  # {"host": "...", "client": "..."}
    created_at: datetime
```

### Digital Signature Pattern

```python
# crypto/signing_service.py
import json
import hashlib
from base64 import b64encode
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

def sign_summary(summary_data: dict, private_key, public_key_id: str) -> dict:
    """Sign summary JSON and return signature metadata."""
    
    # 1. Canonicalize JSON
    canonical = json.dumps(summary_data, sort_keys=True, separators=(",", ":"))
    
    # 2. Compute SHA-256 hash
    digest = hashlib.sha256(canonical.encode()).hexdigest()
    document_hash = f"SHA256:{digest}"
    
    # 3. Sign with RSA
    signature_bytes = private_key.sign(
        canonical.encode(),
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    
    # 4. Return signature metadata
    return {
        "signature_id": f"sig_{generate_id()}",
        "public_key_id": public_key_id,
        "signature_value": b64encode(signature_bytes).decode(),
        "document_hash": document_hash,
        "algorithm": "RS256",
        "created_at": datetime.utcnow().isoformat()
    }
```

---

## 5. Data Models

### Core Models

```python
# models/session_model.py
from sqlalchemy import Column, String, DateTime, Boolean, JSON, Enum
from app.models.db import Base
import enum

class SessionStatus(enum.Enum):
    SCHEDULED = "scheduled"
    ACTIVE = "active"
    ENDED = "ended"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class SessionModel(Base):
    __tablename__ = "sessions"
    
    id = Column(String, primary_key=True)  # sess_xxx
    tenant_id = Column(String, nullable=False, index=True)
    status = Column(Enum(SessionStatus), default=SessionStatus.SCHEDULED)
    
    # Participants (JSON)
    host = Column(JSON)
    client = Column(JSON)
    
    # Configuration
    auto_start_recording = Column(Boolean, default=True)
    webhook_url = Column(String, nullable=True)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    started_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    
    # Audit fields
    created_by = Column(String, nullable=True)
    updated_by = Column(String, nullable=True)
    deleted_at = Column(DateTime, nullable=True)
    deleted_by = Column(String, nullable=True)
```

```python
# models/summary_model.py
class SummaryModel(Base):
    __tablename__ = "summaries"
    
    id = Column(String, primary_key=True)  # sum_xxx
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    tenant_id = Column(String, nullable=False, index=True)
    
    # Summary content
    json_data = Column(JSON)  # Structured summary
    pdf_path = Column(String, nullable=True)  # S3 path
    
    # Status
    status = Column(String, default="pending")  # pending, processing, ready, failed
    signed = Column(Boolean, default=False)
    signature_id = Column(String, ForeignKey("signatures.id"), nullable=True)
    
    # Timestamps
    generated_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
```

```python
# models/signature_model.py
class SignatureModel(Base):
    __tablename__ = "signatures"
    
    id = Column(String, primary_key=True)  # sig_xxx
    summary_id = Column(String, ForeignKey("summaries.id"), nullable=False)
    public_key_id = Column(String, ForeignKey("signing_keys.id"), nullable=False)
    
    document_hash = Column(String, nullable=False)  # SHA256:...
    signature_value = Column(Text, nullable=False)  # Base64 encoded
    algorithm = Column(String, default="RS256")
    
    created_at = Column(DateTime, default=datetime.utcnow)
```

---

## 6. Security & Compliance

### Authentication

**API Key Authentication (Server-to-Server):**

```python
# core/security.py
from fastapi import Header, HTTPException

async def get_current_tenant(x_api_key: str = Header(...)):
    """Validate API key and return tenant."""
    tenant = validate_api_key(x_api_key)
    if not tenant:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return tenant
```

**JWT Tokens (Widget Authentication):**

```python
def create_join_token(session_id: str, role: str, tenant_id: str) -> str:
    """Create short-lived JWT for widget access."""
    payload = {
        "session_id": session_id,
        "role": role,  # "host" or "client"
        "tenant_id": tenant_id,
        "exp": datetime.utcnow() + timedelta(minutes=15)
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")
```

### Webhook Security

```python
# services/webhook_dispatcher.py
import hmac
import hashlib

def send_webhook(url: str, payload: dict, secret: str):
    """Send HMAC-signed webhook."""
    body = json.dumps(payload)
    signature = hmac.new(
        secret.encode(),
        body.encode(),
        hashlib.sha256
    ).hexdigest()
    
    response = requests.post(
        url,
        json=payload,
        headers={
            "Content-Type": "application/json",
            "X-AccuBrief-Signature": f"sha256={signature}"
        },
        timeout=10
    )
    return response
```

### Error Handling

```python
# Common HTTP error responses
401 Unauthorized  # Invalid API key / token
403 Forbidden     # Tenant mismatch
404 Not Found     # Session/summary/recording not found
422 Unprocessable # Invalid payload
500 Internal      # Unexpected errors
```

---

## 7. Quick Reference

### Most Common Operations

| Task | Code |
|------|------|
| **Get tenant** | `tenant = Depends(get_current_tenant)` |
| **Query with tenant** | `db.query(Model).filter(Model.tenant_id == tenant.id)` |
| **Soft delete** | `model.status = "DELETED"; model.deleted_at = datetime.utcnow()` |
| **Sign summary** | `signature = sign_summary(summary_data, private_key, key_id)` |
| **Send webhook** | `webhook_dispatcher.send_event(tenant, "summary.ready", payload)` |
| **Enqueue job** | `queue.enqueue(summary_worker.run_pipeline, session_id)` |

### ID Prefixes

| Entity | Prefix | Example |
|--------|--------|---------|
| Session | `sess_` | `sess_abc123` |
| Recording | `rec_` | `rec_xyz789` |
| Summary | `sum_` | `sum_def456` |
| Signature | `sig_` | `sig_ghi012` |
| Participant | `part_` | `part_jkl345` |

### Environment Variables

```bash
# Database
DATABASE_URL="postgresql://user:pass@localhost:5432/accubrief"

# Storage
S3_ENDPOINT="http://localhost:9000"
S3_ACCESS_KEY="minioadmin"
S3_SECRET_KEY="minioadmin"
S3_BUCKET="accubrief-recordings"

# Security
JWT_SECRET="your-jwt-secret"
SIGNING_PRIVATE_KEY="base64-encoded-pem"

# AI Services
OPENAI_API_KEY="sk-..."
WHISPER_MODEL="base"

# Redis
REDIS_URL="redis://localhost:6379"
```

### Docker Commands

```bash
# Start development environment
docker-compose up -d

# Run migrations
docker-compose exec backend alembic upgrade head

# View logs
docker-compose logs -f backend

# Run tests
docker-compose exec backend pytest

# Access database
docker-compose exec postgres psql -U accubrief
```

---

## Summary

**Key Takeaways**:
1. ⚠️ ALWAYS filter by `tenant_id` for multi-tenancy
2. ⚠️ NEVER hard delete (use soft delete)
3. ⚠️ Sign all summaries with RSA digital signatures
4. ⚠️ Include audit fields in all models
5. ✅ Use functional services over classes
6. ✅ Validate all inputs with Pydantic
7. ✅ Send HMAC-signed webhooks

**Questions?** See existing code in `/backend/app/services`, `/backend/app/api`, or `/docs` for real examples.

---

**Last Updated**: December 6, 2025  
**Maintained by**: AccuBrief Engineering Team
