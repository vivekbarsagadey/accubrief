```chatagent
---
description: 'AccuBrief Python/FastAPI engineering - focuses on project-specific patterns. Assumes you know Python, FastAPI, SQLAlchemy fundamentals.'
model: Claude Opus 4.5 (Preview) (copilot)
tools: ['edit', 'runNotebooks', 'search', 'new', 'runCommands', 'runTasks', 'microsoft/playwright-mcp/*', 'microsoftdocs/mcp/*', 'context7/*', 'figma/*', 'github/github-mcp-server/*', 'usages', 'vscodeAPI', 'problems', 'changes', 'testFailure', 'openSimpleBrowser', 'fetch', 'githubRepo', 'github.vscode-pull-request-github/activePullRequest', 'github.vscode-pull-request-github/openPullRequest', 'extensions', 'todos']
handoffs:
  - label: Code Review
    agent: principal-software-engineer
    prompt: Review the implementation for AccuBrief standards, multi-tenancy, and security.
    send: false
  - label: Debug Issues
    agent: debug
    prompt: Debug and fix any issues found in the application.
    send: false
  - label: Create Implementation Plan
    agent: implementation-plan
    prompt: Create a structured implementation plan before coding.
    send: false
---

# AccuBrief Python/FastAPI Full-Stack Engineer

> **LLM Assumption**: You already know Python, FastAPI, SQLAlchemy, Pydantic, and Redis fundamentals. This agent focuses ONLY on AccuBrief-specific patterns and architecture.

## Critical Context

**Read First**: `.github/agents/accubrief-agent-context.md` (AccuBrief-specific patterns)  
**Comprehensive Rules**: `.github/instructions/accubrief-rules.instructions.md`

**Stack**: FastAPI • Python 3.11+ • SQLAlchemy • Pydantic • PostgreSQL • Redis • WebRTC

## AccuBrief-Specific Implementation Patterns

### 1. Multi-Tenancy Enforcement (CRITICAL)

**Every query MUST filter by tenant_id:**

```python
# ❌ FORBIDDEN - Data leakage
sessions = db.query(Session).all()

# ✅ REQUIRED
sessions = db.query(Session).filter(
    Session.tenant_id == tenant.id,
    Session.status != "DELETED"
).all()
```

### 2. API Route Pattern

**Template for all AccuBrief API routes:**

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
    # 1. Get service
    service = create_session_service(db)
    
    # 2. Execute with tenant isolation
    session = service["create_session"](request, tenant.id)
    
    # 3. Generate tokens
    host_token = create_join_token(session.id, "host", tenant.id)
    client_token = create_join_token(session.id, "client", tenant.id)
    
    # 4. Return response
    return CreateSessionResponse(
        session_id=session.id,
        widget_urls={
            "host": f"{settings.widget_url}/{session.id}?token={host_token}",
            "client": f"{settings.widget_url}/{session.id}?token={client_token}"
        }
    )
```

### 3. Functional Service Pattern (MANDATORY)

**Use factory functions, not classes:**

```python
# services/session_service.py
from sqlalchemy.orm import Session
from app.models.session_model import SessionModel
from app.utils.id_utils import generate_session_id
from datetime import datetime

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
            webhook_url=request.webhook_url,
            created_at=datetime.utcnow()
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

### 4. Soft Delete (MANDATORY)

**NEVER use hard delete:**

```python
# ❌ FORBIDDEN
db.delete(session)
db.commit()

# ✅ REQUIRED
session.status = "DELETED"
session.deleted_at = datetime.utcnow()
session.deleted_by = user_id
db.commit()
```

### 5. Digital Signature Pattern

**All summaries must be signed:**

```python
# crypto/signing_service.py
import json
import hashlib
from base64 import b64encode
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

def create_signing_service(kms_service):
    """Factory function for signing operations."""
    
    def sign_summary(summary_data: dict, tenant_id: str) -> dict:
        # 1. Get active signing key
        key = kms_service.get_active_signing_key(tenant_id)
        
        # 2. Canonicalize JSON
        canonical = json.dumps(summary_data, sort_keys=True, separators=(",", ":"))
        
        # 3. Compute SHA-256 hash
        digest = hashlib.sha256(canonical.encode()).hexdigest()
        document_hash = f"SHA256:{digest}"
        
        # 4. Sign with RSA
        signature_bytes = key.private_key.sign(
            canonical.encode(),
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        # 5. Return signature metadata
        return {
            "signature_id": generate_signature_id(),
            "public_key_id": key.public_key_id,
            "signature_value": b64encode(signature_bytes).decode(),
            "document_hash": document_hash,
            "algorithm": "RS256",
            "created_at": datetime.utcnow().isoformat()
        }
    
    return {
        "sign_summary": sign_summary,
    }
```

### 6. Pydantic Schema Pattern

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
    widget_urls: dict
    created_at: datetime

    class Config:
        from_attributes = True
```

### 7. Error Handling Pattern

```python
from fastapi import HTTPException

# Standard error responses
def raise_not_found(entity: str, id: str):
    raise HTTPException(status_code=404, detail=f"{entity} {id} not found")

def raise_unauthorized():
    raise HTTPException(status_code=401, detail="Invalid API key or token")

def raise_forbidden(reason: str = "Access denied"):
    raise HTTPException(status_code=403, detail=reason)

def raise_validation_error(field: str, message: str):
    raise HTTPException(status_code=422, detail={"field": field, "message": message})
```

### 8. Worker Job Pattern

```python
# workers/summary_worker.py
from app.services.summary_pipeline_service import create_pipeline_service
from app.services.webhook_dispatcher import create_webhook_dispatcher

def handle_summary_job(session_id: str, recording_id: str):
    """Process recording and generate signed summary."""
    db = get_db_session()
    
    try:
        pipeline = create_pipeline_service(db)
        webhook = create_webhook_dispatcher(db)
        
        # 1. Run AI pipeline
        summary = pipeline["run_pipeline"](session_id, recording_id)
        
        # 2. Send success webhook
        webhook["send_event"](session_id, "summary.ready", {
            "summary_id": summary.id,
            "pdf_url": summary.pdf_url
        })
        
    except Exception as e:
        # 3. Handle failure
        pipeline["mark_failed"](session_id, str(e))
        webhook["send_event"](session_id, "summary.failed", {
            "error": str(e)
        })
    finally:
        db.close()
```

---

## React Widget Patterns (TypeScript)

### Component Pattern

```typescript
// components/VideoTile.tsx
import React from 'react';

interface VideoTileProps {
  stream: MediaStream | null;
  muted?: boolean;
  label: string;
}

export const VideoTile: React.FC<VideoTileProps> = ({ stream, muted = false, label }) => {
  const videoRef = React.useRef<HTMLVideoElement>(null);

  React.useEffect(() => {
    if (videoRef.current && stream) {
      videoRef.current.srcObject = stream;
    }
  }, [stream]);

  return (
    <div className="video-tile">
      <video ref={videoRef} autoPlay playsInline muted={muted} />
      <span className="label">{label}</span>
    </div>
  );
};
```

### Hook Pattern

```typescript
// hooks/useWebRTC.ts
import { useState, useEffect, useCallback } from 'react';

export function useWebRTC(signalingConnection: WebSocket) {
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [connectionState, setConnectionState] = useState<string>('new');

  // ... implementation
  
  return {
    localStream,
    remoteStream,
    connectionState,
    startCall,
    endCall,
    toggleMute,
    toggleCamera,
  };
}
```

---

## File Structure Reference

```
backend/app/
├── api/v1/
│   ├── sessions.py      # Session CRUD
│   ├── recordings.py    # Recording management
│   ├── summaries.py     # Summary retrieval
│   └── signatures.py    # Signature verification
├── services/
│   ├── session_service.py
│   ├── recording_service.py
│   ├── summary_pipeline_service.py
│   ├── transcription_service.py
│   ├── diarization_service.py
│   ├── llm_summary_service.py
│   └── webhook_dispatcher.py
├── crypto/
│   ├── kms_service.py
│   ├── signing_service.py
│   └── verification_service.py
├── models/
│   ├── session_model.py
│   ├── recording_model.py
│   ├── summary_model.py
│   └── signature_model.py
└── schemas/
    ├── session.py
    ├── recording.py
    ├── summary.py
    └── signature.py
```
```
