# Low-Level Design (LLD) - AccuBrief

## 1. Introduction

This Low-Level Design document provides detailed technical specifications for implementing AccuBrief. It covers module-level design, class structures, method signatures, database schemas, and implementation algorithms.

## 2. Backend Architecture (FastAPI)

### 2.1 Package Structure

```
backend/
└── app/
    ├── main.py                    # Application entry point
    ├── __init__.py
    │
    ├── core/                      # Core utilities
    │   ├── __init__.py
    │   ├── config.py              # Settings & environment
    │   ├── security.py            # Auth & JWT handling
    │   └── logging.py             # Structured logging
    │
    ├── api/                       # API layer
    │   └── v1/
    │       ├── __init__.py
    │       ├── sessions.py        # Session endpoints
    │       ├── recordings.py      # Recording endpoints
    │       ├── summaries.py       # Summary endpoints
    │       ├── signatures.py      # Verification endpoints
    │       └── webhooks.py        # Webhook endpoints
    │
    ├── services/                  # Business logic
    │   ├── __init__.py
    │   ├── session_service.py
    │   ├── recording_service.py
    │   ├── summary_pipeline_service.py
    │   ├── transcription_service.py
    │   ├── diarization_service.py
    │   ├── llm_summary_service.py
    │   └── webhook_dispatcher.py
    │
    ├── crypto/                    # Digital signature
    │   ├── __init__.py
    │   ├── kms_service.py
    │   ├── signing_service.py
    │   ├── verification_service.py
    │   └── utils.py
    │
    ├── models/                    # ORM models
    │   ├── __init__.py
    │   ├── db.py
    │   ├── session_model.py
    │   ├── participant_model.py
    │   ├── recording_model.py
    │   ├── summary_model.py
    │   ├── signing_key_model.py
    │   └── signature_model.py
    │
    ├── schemas/                   # Pydantic schemas
    │   ├── __init__.py
    │   ├── base.py
    │   ├── session.py
    │   ├── recording.py
    │   ├── summary.py
    │   └── signature.py
    │
    ├── workers/                   # Background workers
    │   ├── __init__.py
    │   ├── queue_setup.py
    │   ├── summary_worker.py
    │   └── recording_worker.py
    │
    └── utils/                     # Utilities
        ├── __init__.py
        ├── storage.py
        ├── token_utils.py
        ├── time_utils.py
        ├── pdf_utils.py
        └── audio_utils.py
```

### 2.2 Core Module

#### 2.2.1 config.py

```python
from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    """Application configuration from environment variables."""
    
    # Environment
    ENV: str = "development"
    DEBUG: bool = False
    
    # Database
    DATABASE_URL: str
    DATABASE_POOL_SIZE: int = 10
    
    # Object Storage
    S3_ENDPOINT: str
    S3_ACCESS_KEY: str
    S3_SECRET_KEY: str
    S3_BUCKET_RECORDINGS: str = "accubrief-recordings"
    S3_BUCKET_SUMMARIES: str = "accubrief-summaries"
    
    # Security
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRY_MINUTES: int = 15
    
    # Signing
    SIGNING_PRIVATE_KEY: str  # Base64 encoded PEM
    ACCUBRIEF_MAIN_KEY_ID: str = "accubrief-main-key-1"
    
    # TURN/STUN
    TURN_URL: str
    TURN_USERNAME: str
    TURN_PASSWORD: str
    STUN_URL: str = "stun:stun.l.google.com:19302"
    
    # AI Services
    OPENAI_API_KEY: str = ""
    LLM_ENDPOINT: str = ""
    STT_ENDPOINT: str = ""
    WHISPER_MODEL: str = "base"
    
    # Redis
    REDIS_URL: str
    
    # Widget
    WIDGET_BASE_URL: str
    API_BASE_URL: str
    
    class Config:
        env_file = ".env"
        case_sensitive = True

@lru_cache()
def get_settings() -> Settings:
    """Returns singleton settings instance."""
    return Settings()
```

#### 2.2.2 security.py

```python
from datetime import datetime, timedelta
from typing import Optional
from fastapi import Header, HTTPException, Depends
from jose import jwt, JWTError
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.core.config import get_settings
from app.models.db import get_db

class JoinTokenPayload(BaseModel):
    """JWT payload for widget join tokens."""
    session_id: str
    role: str  # "host" or "client"
    tenant_id: str
    exp: datetime

class Tenant(BaseModel):
    """Tenant context from API key."""
    id: str
    name: str
    webhook_url: Optional[str] = None
    webhook_secret: Optional[str] = None

def authenticate_api_key(
    x_api_key: str = Header(..., alias="X-API-Key"),
    db: Session = Depends(get_db)
) -> Tenant:
    """
    Validate API key and return tenant context.
    
    Raises:
        HTTPException: 401 if API key is invalid
    """
    # Query tenant by API key hash
    from app.models.tenant_model import TenantModel
    import hashlib
    
    key_hash = hashlib.sha256(x_api_key.encode()).hexdigest()
    tenant = db.query(TenantModel).filter(
        TenantModel.api_key_hash == key_hash,
        TenantModel.is_active == True
    ).first()
    
    if not tenant:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return Tenant(
        id=tenant.id,
        name=tenant.name,
        webhook_url=tenant.webhook_url,
        webhook_secret=tenant.webhook_secret
    )

def create_join_token(
    session_id: str,
    role: str,
    tenant_id: str
) -> str:
    """
    Create short-lived JWT for widget authentication.
    
    Args:
        session_id: Session to join
        role: "host" or "client"
        tenant_id: Owning tenant
        
    Returns:
        JWT token string
    """
    settings = get_settings()
    payload = {
        "session_id": session_id,
        "role": role,
        "tenant_id": tenant_id,
        "exp": datetime.utcnow() + timedelta(minutes=settings.JWT_EXPIRY_MINUTES)
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def decode_join_token(token: str) -> JoinTokenPayload:
    """
    Decode and validate join token.
    
    Args:
        token: JWT token string
        
    Returns:
        Decoded token payload
        
    Raises:
        HTTPException: 401 if token is invalid or expired
    """
    settings = get_settings()
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return JoinTokenPayload(**payload)
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")

# Dependency alias
get_current_tenant = authenticate_api_key
```

### 2.3 API Layer

#### 2.3.1 sessions.py

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime

from app.core.security import get_current_tenant, Tenant
from app.models.db import get_db
from app.schemas.session import (
    CreateSessionRequest,
    CreateSessionResponse,
    SessionDetailsResponse,
    EndSessionResponse
)
from app.services.session_service import create_session_service

router = APIRouter(prefix="/v1/sessions", tags=["Sessions"])

@router.post("/", response_model=CreateSessionResponse, status_code=201)
async def create_session(
    request: CreateSessionRequest,
    tenant: Tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Create a new video session.
    
    Returns session ID and widget URLs for host and client participants.
    """
    service = create_session_service(db, get_settings())
    result = service["create_session"](request, tenant.id)
    return result

@router.get("/{session_id}", response_model=SessionDetailsResponse)
async def get_session(
    session_id: str,
    tenant: Tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Get session details by ID.
    
    Returns current status, participants, and timestamps.
    """
    service = create_session_service(db, get_settings())
    session = service["get_session"](session_id, tenant.id)
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    return session

@router.post("/{session_id}/end", response_model=EndSessionResponse)
async def end_session(
    session_id: str,
    tenant: Tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    End an active session.
    
    Triggers summary pipeline processing.
    """
    service = create_session_service(db, get_settings())
    
    try:
        result = service["end_session"](session_id, tenant.id)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
```

#### 2.3.2 summaries.py

```python
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.security import get_current_tenant, Tenant
from app.models.db import get_db
from app.schemas.summary import SummaryResponse
from app.models.summary_model import SummaryModel
from app.utils.storage import get_storage_service

router = APIRouter(prefix="/v1/summaries", tags=["Summaries"])

@router.get("/{summary_id}", response_model=SummaryResponse)
async def get_summary(
    summary_id: str,
    tenant: Tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Get summary JSON by ID.
    
    Includes signature metadata if signed.
    """
    summary = db.query(SummaryModel).filter(
        SummaryModel.id == summary_id,
        SummaryModel.tenant_id == tenant.id,
        SummaryModel.status != "DELETED"
    ).first()
    
    if not summary:
        raise HTTPException(status_code=404, detail="Summary not found")
    
    return _build_summary_response(summary)

@router.get("/{summary_id}/pdf")
async def download_pdf(
    summary_id: str,
    tenant: Tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Download summary as PDF.
    
    Returns PDF file as attachment.
    """
    summary = db.query(SummaryModel).filter(
        SummaryModel.id == summary_id,
        SummaryModel.tenant_id == tenant.id
    ).first()
    
    if not summary:
        raise HTTPException(status_code=404, detail="Summary not found")
    
    if not summary.pdf_path:
        raise HTTPException(status_code=404, detail="PDF not yet generated")
    
    storage = get_storage_service()
    pdf_stream = storage.download_file(summary.pdf_path)
    
    return StreamingResponse(
        pdf_stream,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename=summary_{summary_id}.pdf"
        }
    )

def _build_summary_response(summary: SummaryModel) -> SummaryResponse:
    """Build response with signature metadata if available."""
    response = SummaryResponse(
        summary_id=summary.id,
        session_id=summary.session_id,
        generated_at=summary.generated_at,
        status=summary.status,
        signed=summary.signed,
        sections=summary.json_data
    )
    
    if summary.signature:
        response.signature_meta = {
            "signature_id": summary.signature.id,
            "document_hash": summary.signature.document_hash,
            "public_key_id": summary.signature.public_key_id,
            "algorithm": summary.signature.algorithm,
            "created_at": summary.signature.created_at
        }
    
    return response
```

#### 2.3.3 signatures.py

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import get_current_tenant, Tenant
from app.models.db import get_db
from app.schemas.signature import (
    VerifySignatureRequest,
    VerifySignatureResponse
)
from app.crypto.verification_service import create_verification_service
from app.models.summary_model import SummaryModel

router = APIRouter(prefix="/v1/signatures", tags=["Signatures"])

@router.post("/verify", response_model=VerifySignatureResponse)
async def verify_signature(
    request: VerifySignatureRequest,
    db: Session = Depends(get_db)
):
    """
    Verify a digital signature.
    
    Supports two modes:
    1. By summary_id: Looks up summary and verifies
    2. By document: Direct verification with provided document and signature
    """
    verification_service = create_verification_service(db)
    
    if request.summary_id:
        # Verify by summary ID
        summary = db.query(SummaryModel).filter(
            SummaryModel.id == request.summary_id
        ).first()
        
        if not summary:
            raise HTTPException(status_code=404, detail="Summary not found")
        
        if not summary.signature:
            return VerifySignatureResponse(
                is_valid=False,
                reason="Summary is not signed"
            )
        
        result = verification_service["verify_by_summary"](summary)
        
    elif request.document and request.signature_value and request.public_key_id:
        # Verify by document
        result = verification_service["verify_by_document"](
            document=request.document,
            signature_value=request.signature_value,
            public_key_id=request.public_key_id
        )
    else:
        raise HTTPException(
            status_code=422,
            detail="Provide either summary_id or (document + signature_value + public_key_id)"
        )
    
    return result
```

### 2.4 Services Layer

#### 2.4.1 session_service.py

```python
from datetime import datetime
from sqlalchemy.orm import Session
from typing import Dict, Any, Callable

from app.core.config import Settings
from app.core.security import create_join_token
from app.models.session_model import SessionModel, SessionStatus
from app.models.participant_model import ParticipantModel
from app.schemas.session import (
    CreateSessionRequest,
    CreateSessionResponse,
    SessionDetailsResponse
)
from app.utils.token_utils import generate_id
from app.workers.queue_setup import enqueue_summary_job

def create_session_service(db: Session, settings: Settings) -> Dict[str, Callable]:
    """
    Factory function returning session operations.
    
    Uses functional composition pattern for dependency injection.
    """
    
    def create_session(
        request: CreateSessionRequest,
        tenant_id: str
    ) -> CreateSessionResponse:
        """Create a new session with participants."""
        session_id = f"sess_{generate_id()}"
        
        # Create session
        session = SessionModel(
            id=session_id,
            tenant_id=tenant_id,
            status=SessionStatus.SCHEDULED,
            auto_start_recording=request.auto_start_recording,
            webhook_url=request.webhook_url,
            created_at=datetime.utcnow()
        )
        db.add(session)
        
        # Create host participant
        host = ParticipantModel(
            id=f"part_{generate_id()}",
            session_id=session_id,
            name=request.host.name,
            external_user_id=request.host.external_user_id,
            role="host"
        )
        db.add(host)
        
        # Create client participant
        client = ParticipantModel(
            id=f"part_{generate_id()}",
            session_id=session_id,
            name=request.client.name,
            external_user_id=request.client.external_user_id,
            role="client"
        )
        db.add(client)
        
        db.commit()
        db.refresh(session)
        
        # Generate widget URLs
        host_token = create_join_token(session_id, "host", tenant_id)
        client_token = create_join_token(session_id, "client", tenant_id)
        
        return CreateSessionResponse(
            session_id=session_id,
            widget_urls={
                "host": f"{settings.WIDGET_BASE_URL}/{session_id}?role=host&token={host_token}",
                "client": f"{settings.WIDGET_BASE_URL}/{session_id}?role=client&token={client_token}"
            },
            created_at=session.created_at
        )
    
    def get_session(
        session_id: str,
        tenant_id: str
    ) -> SessionDetailsResponse | None:
        """Get session details by ID."""
        session = db.query(SessionModel).filter(
            SessionModel.id == session_id,
            SessionModel.tenant_id == tenant_id,
            SessionModel.status != SessionStatus.DELETED
        ).first()
        
        if not session:
            return None
        
        participants = db.query(ParticipantModel).filter(
            ParticipantModel.session_id == session_id
        ).all()
        
        return SessionDetailsResponse(
            session_id=session.id,
            status=session.status.value,
            created_at=session.created_at,
            started_at=session.started_at,
            ended_at=session.ended_at,
            participants=[
                {"name": p.name, "role": p.role}
                for p in participants
            ]
        )
    
    def end_session(session_id: str, tenant_id: str) -> Dict[str, Any]:
        """End a session and trigger summary pipeline."""
        session = db.query(SessionModel).filter(
            SessionModel.id == session_id,
            SessionModel.tenant_id == tenant_id
        ).first()
        
        if not session:
            raise ValueError("Session not found")
        
        if session.status == SessionStatus.ENDED:
            raise ValueError("Session already ended")
        
        session.status = SessionStatus.ENDED
        session.ended_at = datetime.utcnow()
        db.commit()
        
        # Trigger summary pipeline
        enqueue_summary_job(session_id)
        
        return {
            "session_id": session_id,
            "status": "ended",
            "ended_at": session.ended_at
        }
    
    def update_session_status(session_id: str, status: SessionStatus) -> None:
        """Update session status."""
        session = db.query(SessionModel).filter(
            SessionModel.id == session_id
        ).first()
        
        if session:
            session.status = status
            db.commit()
    
    return {
        "create_session": create_session,
        "get_session": get_session,
        "end_session": end_session,
        "update_session_status": update_session_status
    }
```

#### 2.4.2 summary_pipeline_service.py

```python
from datetime import datetime
from sqlalchemy.orm import Session
from typing import Dict, Any

from app.models.session_model import SessionModel, SessionStatus
from app.models.recording_model import RecordingModel
from app.models.summary_model import SummaryModel, SummaryStatus
from app.services.transcription_service import create_transcription_service
from app.services.diarization_service import create_diarization_service
from app.services.llm_summary_service import create_llm_summary_service
from app.services.webhook_dispatcher import create_webhook_dispatcher
from app.crypto.signing_service import create_signing_service
from app.utils.storage import get_storage_service
from app.utils.audio_utils import extract_audio
from app.utils.pdf_utils import generate_pdf
from app.utils.token_utils import generate_id

def run_pipeline_for_session(db: Session, session_id: str) -> None:
    """
    Execute the full AI summary pipeline for a session.
    
    Steps:
    1. Download recording
    2. Extract audio
    3. Transcribe
    4. Diarize
    5. Generate summary with LLM
    6. Create PDF
    7. Sign summary
    8. Send webhook
    """
    session = db.query(SessionModel).filter(
        SessionModel.id == session_id
    ).first()
    
    if not session:
        raise ValueError(f"Session not found: {session_id}")
    
    # Update status
    session.status = SessionStatus.PROCESSING
    db.commit()
    
    try:
        # Step 1: Get best recording
        recording = _select_best_recording(db, session_id)
        if not recording:
            raise ValueError("No recording found for session")
        
        storage = get_storage_service()
        
        # Step 2: Download and extract audio
        video_path = storage.download_to_temp(recording.file_path)
        audio_path = extract_audio(video_path)
        
        # Step 3: Transcribe
        transcription_service = create_transcription_service()
        transcript = transcription_service["transcribe"](audio_path)
        
        # Step 4: Diarize
        diarization_service = create_diarization_service()
        diarized_transcript = diarization_service["diarize"](transcript, audio_path)
        
        # Step 5: Generate summary
        llm_service = create_llm_summary_service()
        summary_json = llm_service["create_summary"](diarized_transcript)
        
        # Step 6: Create summary record
        summary = SummaryModel(
            id=f"sum_{generate_id()}",
            session_id=session_id,
            tenant_id=session.tenant_id,
            json_data=summary_json,
            status=SummaryStatus.PROCESSING,
            created_at=datetime.utcnow()
        )
        db.add(summary)
        db.commit()
        
        # Step 7: Generate PDF
        pdf_content = generate_pdf(summary_json, session_id)
        pdf_path = f"summaries/{session.tenant_id}/{session_id}/{summary.id}.pdf"
        storage.upload_file(pdf_content, pdf_path, "application/pdf")
        summary.pdf_path = pdf_path
        
        # Step 8: Sign summary
        signing_service = create_signing_service(db)
        signature_meta = signing_service["sign_summary"](
            summary_id=summary.id,
            summary_data=summary_json,
            tenant_id=session.tenant_id
        )
        
        summary.signed = True
        summary.signature_id = signature_meta["signature_id"]
        summary.status = SummaryStatus.READY
        summary.generated_at = datetime.utcnow()
        
        session.status = SessionStatus.COMPLETED
        db.commit()
        
        # Step 9: Send webhook
        webhook_dispatcher = create_webhook_dispatcher()
        webhook_dispatcher["send_event"](
            tenant_id=session.tenant_id,
            webhook_url=session.webhook_url,
            event_type="summary.ready",
            payload={
                "session_id": session_id,
                "summary_id": summary.id,
                "generated_at": summary.generated_at.isoformat()
            }
        )
        
    except Exception as e:
        # Handle failure
        session.status = SessionStatus.FAILED
        db.commit()
        
        # Send failure webhook
        webhook_dispatcher = create_webhook_dispatcher()
        webhook_dispatcher["send_event"](
            tenant_id=session.tenant_id,
            webhook_url=session.webhook_url,
            event_type="summary.failed",
            payload={
                "session_id": session_id,
                "error": str(e)
            }
        )
        raise

def _select_best_recording(db: Session, session_id: str) -> RecordingModel | None:
    """Select the best available recording for processing."""
    return db.query(RecordingModel).filter(
        RecordingModel.session_id == session_id,
        RecordingModel.status == "uploaded"
    ).order_by(RecordingModel.duration_seconds.desc()).first()
```

### 2.5 Crypto Layer

#### 2.5.1 signing_service.py

```python
import json
import hashlib
import base64
from datetime import datetime
from typing import Dict, Any, Callable
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from sqlalchemy.orm import Session

from app.crypto.kms_service import create_kms_service
from app.crypto.utils import canonical_json_bytes
from app.models.signature_model import SignatureModel
from app.utils.token_utils import generate_id

def create_signing_service(db: Session) -> Dict[str, Callable]:
    """Factory function for signing operations."""
    
    kms = create_kms_service()
    
    def sign_summary(
        summary_id: str,
        summary_data: Dict[str, Any],
        tenant_id: str
    ) -> Dict[str, Any]:
        """
        Sign a summary document.
        
        Args:
            summary_id: ID of summary being signed
            summary_data: Summary JSON to sign
            tenant_id: Tenant context
            
        Returns:
            Signature metadata
        """
        # Step 1: Get active signing key
        signing_key = kms["get_active_signing_key"](tenant_id)
        
        # Step 2: Canonicalize JSON
        canonical_bytes = canonical_json_bytes(summary_data)
        
        # Step 3: Compute SHA-256 hash
        digest = hashlib.sha256(canonical_bytes).hexdigest()
        document_hash = f"SHA256:{digest}"
        
        # Step 4: Sign with RSA
        signature_bytes = signing_key.private_key.sign(
            canonical_bytes,
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        # Step 5: Base64 encode
        signature_value = base64.b64encode(signature_bytes).decode("utf-8")
        
        # Step 6: Store signature
        signature = SignatureModel(
            id=f"sig_{generate_id()}",
            summary_id=summary_id,
            public_key_id=signing_key.public_key_id,
            document_hash=document_hash,
            signature_value=signature_value,
            algorithm="RS256",
            created_at=datetime.utcnow()
        )
        db.add(signature)
        db.commit()
        
        return {
            "signature_id": signature.id,
            "public_key_id": signing_key.public_key_id,
            "document_hash": document_hash,
            "signature_value": signature_value,
            "algorithm": "RS256",
            "created_at": signature.created_at
        }
    
    return {
        "sign_summary": sign_summary
    }
```

#### 2.5.2 verification_service.py

```python
import base64
import hashlib
from datetime import datetime
from typing import Dict, Any, Callable
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature
from sqlalchemy.orm import Session

from app.crypto.kms_service import create_kms_service
from app.crypto.utils import canonical_json_bytes
from app.models.summary_model import SummaryModel
from app.schemas.signature import VerifySignatureResponse

def create_verification_service(db: Session) -> Dict[str, Callable]:
    """Factory function for verification operations."""
    
    kms = create_kms_service()
    
    def verify_by_summary(summary: SummaryModel) -> VerifySignatureResponse:
        """Verify signature by looking up summary."""
        signature = summary.signature
        
        if not signature:
            return VerifySignatureResponse(
                is_valid=False,
                reason="Summary is not signed"
            )
        
        # Recompute hash from stored JSON
        canonical_bytes = canonical_json_bytes(summary.json_data)
        digest = hashlib.sha256(canonical_bytes).hexdigest()
        computed_hash = f"SHA256:{digest}"
        
        # Compare hashes
        if computed_hash != signature.document_hash:
            return VerifySignatureResponse(
                is_valid=False,
                reason="Document hash mismatch - content may have been tampered",
                summary_id=summary.id,
                document_hash=computed_hash
            )
        
        # Verify RSA signature
        try:
            public_key = kms["get_public_key_by_id"](signature.public_key_id)
            signature_bytes = base64.b64decode(signature.signature_value)
            
            public_key.verify(
                signature_bytes,
                canonical_bytes,
                padding.PKCS1v15(),
                hashes.SHA256()
            )
            
            return VerifySignatureResponse(
                is_valid=True,
                summary_id=summary.id,
                document_hash=signature.document_hash,
                verified_at=datetime.utcnow()
            )
            
        except InvalidSignature:
            return VerifySignatureResponse(
                is_valid=False,
                reason="Signature verification failed",
                summary_id=summary.id
            )
        except Exception as e:
            return VerifySignatureResponse(
                is_valid=False,
                reason=f"Verification error: {str(e)}",
                summary_id=summary.id
            )
    
    def verify_by_document(
        document: str,
        signature_value: str,
        public_key_id: str
    ) -> VerifySignatureResponse:
        """Verify signature using provided document and signature."""
        try:
            # Decode document
            document_json = base64.b64decode(document).decode("utf-8")
            document_dict = json.loads(document_json)
            
            # Canonicalize
            canonical_bytes = canonical_json_bytes(document_dict)
            
            # Get public key
            public_key = kms["get_public_key_by_id"](public_key_id)
            
            # Decode signature
            signature_bytes = base64.b64decode(signature_value)
            
            # Verify
            public_key.verify(
                signature_bytes,
                canonical_bytes,
                padding.PKCS1v15(),
                hashes.SHA256()
            )
            
            # Compute hash for response
            digest = hashlib.sha256(canonical_bytes).hexdigest()
            
            return VerifySignatureResponse(
                is_valid=True,
                document_hash=f"SHA256:{digest}",
                verified_at=datetime.utcnow()
            )
            
        except InvalidSignature:
            return VerifySignatureResponse(
                is_valid=False,
                reason="Signature verification failed"
            )
        except Exception as e:
            return VerifySignatureResponse(
                is_valid=False,
                reason=f"Verification error: {str(e)}"
            )
    
    return {
        "verify_by_summary": verify_by_summary,
        "verify_by_document": verify_by_document
    }
```

#### 2.5.3 utils.py

```python
import json
from typing import Any, Dict

def canonical_json_bytes(data: Dict[str, Any]) -> bytes:
    """
    Convert JSON to canonical form for consistent hashing.
    
    Rules:
    - Keys sorted alphabetically
    - No whitespace
    - Consistent separators
    """
    return json.dumps(
        data,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False
    ).encode("utf-8")
```

### 2.6 Schemas (Pydantic)

#### 2.6.1 session.py

```python
from pydantic import BaseModel, Field
from typing import Optional, Dict, List
from datetime import datetime

class ParticipantInfo(BaseModel):
    """Participant details for session creation."""
    name: str = Field(..., min_length=1, max_length=100)
    external_user_id: Optional[str] = None

class CreateSessionRequest(BaseModel):
    """Request body for creating a session."""
    host: ParticipantInfo
    client: ParticipantInfo
    auto_start_recording: bool = True
    webhook_url: Optional[str] = None

class CreateSessionResponse(BaseModel):
    """Response after creating a session."""
    session_id: str
    widget_urls: Dict[str, str]  # {"host": "...", "client": "..."}
    created_at: datetime

class SessionDetailsResponse(BaseModel):
    """Full session details response."""
    session_id: str
    status: str
    created_at: datetime
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    participants: List[Dict[str, str]]

class EndSessionResponse(BaseModel):
    """Response after ending a session."""
    session_id: str
    status: str
    ended_at: datetime
```

#### 2.6.2 summary.py

```python
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
from datetime import datetime

class SummarySections(BaseModel):
    """Structured summary content."""
    conversation_overview: str
    participants: List[Dict[str, str]]
    questions_and_answers: List[Dict[str, str]]
    decisions: List[str]
    action_items: List[Dict[str, Any]]

class SignatureMeta(BaseModel):
    """Signature metadata attached to summary."""
    signature_id: str
    document_hash: str
    public_key_id: str
    algorithm: str
    created_at: datetime

class SummaryResponse(BaseModel):
    """Full summary response."""
    summary_id: str
    session_id: str
    generated_at: Optional[datetime]
    status: str
    signed: bool
    sections: Dict[str, Any]
    signature_meta: Optional[SignatureMeta] = None
```

#### 2.6.3 signature.py

```python
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class VerifySignatureRequest(BaseModel):
    """Request for signature verification."""
    # Option 1: Verify by summary ID
    summary_id: Optional[str] = None
    
    # Option 2: Verify by document
    document: Optional[str] = None  # Base64 encoded JSON
    signature_value: Optional[str] = None  # Base64 encoded signature
    public_key_id: Optional[str] = None

class VerifySignatureResponse(BaseModel):
    """Response from signature verification."""
    is_valid: bool
    reason: Optional[str] = None
    summary_id: Optional[str] = None
    document_hash: Optional[str] = None
    verified_at: Optional[datetime] = None
```

## 3. Frontend Widget Architecture (React)

### 3.1 Component Structure

```
frontend-widget/
└── src/
    ├── main.tsx                 # Entry point
    ├── App.tsx                  # Root component with routing
    │
    ├── pages/
    │   └── Widget.tsx           # Main widget page
    │
    ├── components/
    │   ├── VideoTile.tsx        # Video stream component
    │   ├── ControlsBar.tsx      # Call controls
    │   ├── RecordingIndicator.tsx
    │   └── ErrorScreen.tsx
    │
    ├── hooks/
    │   ├── useWebRTC.ts         # WebRTC connection hook
    │   ├── useSignaling.ts      # WebSocket hook
    │   ├── useSession.ts        # Session data hook
    │   └── useRecording.ts      # Recording hook
    │
    └── utils/
        ├── api.ts               # API client
        └── config.ts            # Configuration
```

### 3.2 Key Hooks

#### 3.2.1 useWebRTC.ts

```typescript
interface WebRTCState {
  localStream: MediaStream | null;
  remoteStream: MediaStream | null;
  connectionState: RTCPeerConnectionState;
  error: Error | null;
}

interface WebRTCActions {
  startCall: () => Promise<void>;
  endCall: () => void;
  toggleMute: () => void;
  toggleCamera: () => void;
}

function useWebRTC(signaling: SignalingConnection): [WebRTCState, WebRTCActions] {
  // Create RTCPeerConnection
  // Handle signaling events (offer, answer, ice-candidate)
  // Manage media tracks
  // Return state and actions
}
```

#### 3.2.2 useSignaling.ts

```typescript
interface SignalingConnection {
  connected: boolean;
  sendOffer: (sdp: RTCSessionDescriptionInit) => void;
  sendAnswer: (sdp: RTCSessionDescriptionInit) => void;
  sendIceCandidate: (candidate: RTCIceCandidate) => void;
  onOffer: (callback: (sdp: RTCSessionDescriptionInit) => void) => void;
  onAnswer: (callback: (sdp: RTCSessionDescriptionInit) => void) => void;
  onIceCandidate: (callback: (candidate: RTCIceCandidate) => void) => void;
  onPeerJoined: (callback: () => void) => void;
  onPeerLeft: (callback: () => void) => void;
}

function useSignaling(sessionId: string, token: string): SignalingConnection {
  // Connect to WebSocket
  // Handle messages
  // Return connection interface
}
```

#### 3.2.3 useRecording.ts

```typescript
interface RecordingState {
  isRecording: boolean;
  duration: number;
  error: Error | null;
}

interface RecordingActions {
  startRecording: () => void;
  stopRecording: () => Promise<Blob>;
  uploadRecording: (blob: Blob) => Promise<string>;
}

function useRecording(stream: MediaStream | null): [RecordingState, RecordingActions] {
  // Create MediaRecorder
  // Track chunks
  // Handle upload
}
```

### 3.3 Component Details

#### 3.3.1 Widget.tsx

```typescript
function Widget() {
  // Parse URL params
  const { sessionId, role, token } = useParams();
  
  // Initialize hooks
  const session = useSession(sessionId, token);
  const signaling = useSignaling(sessionId, token);
  const [rtcState, rtcActions] = useWebRTC(signaling);
  const [recordingState, recordingActions] = useRecording(rtcState.localStream);
  
  // Render video tiles and controls
  return (
    <div className="widget-container">
      <VideoTile stream={rtcState.localStream} label="You" muted />
      <VideoTile stream={rtcState.remoteStream} label={session.peerName} />
      
      {recordingState.isRecording && <RecordingIndicator />}
      
      <ControlsBar
        isMuted={/* state */}
        isCameraOn={/* state */}
        onToggleMute={rtcActions.toggleMute}
        onToggleCamera={rtcActions.toggleCamera}
        onEndCall={handleEndCall}
      />
    </div>
  );
}
```

## 4. Worker Architecture

### 4.1 Queue Setup

```python
# workers/queue_setup.py
from redis import Redis
from rq import Queue

from app.core.config import get_settings

settings = get_settings()
redis_conn = Redis.from_url(settings.REDIS_URL)

# Define queues
summary_queue = Queue("summary", connection=redis_conn)
recording_queue = Queue("recording", connection=redis_conn)

def enqueue_summary_job(session_id: str) -> str:
    """Enqueue a summary pipeline job."""
    job = summary_queue.enqueue(
        "app.workers.summary_worker.process_summary",
        session_id,
        job_timeout="10m"
    )
    return job.id

def enqueue_recording_job(recording_id: str) -> str:
    """Enqueue a recording processing job."""
    job = recording_queue.enqueue(
        "app.workers.recording_worker.process_recording",
        recording_id,
        job_timeout="5m"
    )
    return job.id
```

### 4.2 Summary Worker

```python
# workers/summary_worker.py
from app.models.db import SessionLocal
from app.services.summary_pipeline_service import run_pipeline_for_session

def process_summary(session_id: str) -> None:
    """
    Worker entry point for summary processing.
    
    Called by RQ when job is dequeued.
    """
    db = SessionLocal()
    try:
        run_pipeline_for_session(db, session_id)
    finally:
        db.close()
```

## 5. Algorithm Details

### 5.1 JSON Canonicalization Algorithm

```
Input: JSON object
Output: Canonical bytes

1. Serialize JSON with:
   - Keys sorted alphabetically (recursive)
   - No whitespace (compact)
   - Separators: "," and ":"
   - UTF-8 encoding
   
2. Return bytes

Example:
  Input:  {"b": 1, "a": {"d": 2, "c": 3}}
  Output: {"a":{"c":3,"d":2},"b":1}
```

### 5.2 Digital Signature Algorithm

```
SIGNING:
  Input: Document (JSON), Private Key (RSA)
  Output: Signature (Base64), Hash (SHA256)

  1. canonical_bytes = canonicalize(document)
  2. hash = SHA256(canonical_bytes)
  3. signature = RSA_SIGN(private_key, canonical_bytes, PKCS1v15, SHA256)
  4. signature_b64 = Base64(signature)
  5. Return (signature_b64, "SHA256:" + hex(hash))

VERIFICATION:
  Input: Document, Signature (Base64), Public Key (RSA)
  Output: Boolean (valid/invalid)

  1. canonical_bytes = canonicalize(document)
  2. signature_bytes = Base64_decode(signature)
  3. valid = RSA_VERIFY(public_key, signature_bytes, canonical_bytes, PKCS1v15, SHA256)
  4. Return valid
```

### 5.3 Webhook HMAC Signing

```
Input: Payload (JSON), Secret (string)
Output: Signature header

1. body = JSON.stringify(payload)
2. signature = HMAC_SHA256(secret, body)
3. header = "sha256=" + hex(signature)
4. Return header

Verification (receiver side):
1. Receive body and X-AccuBrief-Signature header
2. expected = HMAC_SHA256(secret, body)
3. valid = constant_time_compare(received, expected)
```

## 6. Error Handling

### 6.1 API Error Responses

| HTTP Code | Error Type | When Used |
|-----------|------------|-----------|
| 400 | Bad Request | Malformed request body |
| 401 | Unauthorized | Invalid/missing API key or token |
| 403 | Forbidden | Tenant mismatch, insufficient permissions |
| 404 | Not Found | Resource doesn't exist (or hidden by tenant filter) |
| 422 | Unprocessable Entity | Validation error |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected errors |

### 6.2 Error Response Format

```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Session not found",
    "details": {
      "session_id": "sess_abc123"
    }
  }
}
```

## 7. Testing Strategy

### 7.1 Unit Tests

| Component | Test Focus |
|-----------|------------|
| Services | Business logic, edge cases |
| Crypto | Signing, verification, canonicalization |
| Schemas | Validation rules |
| Utils | Helper function correctness |

### 7.2 Integration Tests

| Test Area | Scope |
|-----------|-------|
| API Endpoints | Request/response, auth, errors |
| Database | ORM operations, migrations |
| Queue | Job enqueue/dequeue |
| Storage | Upload/download operations |

### 7.3 E2E Tests

| Flow | Coverage |
|------|----------|
| Session Lifecycle | Create → Join → End |
| Summary Pipeline | Recording → Summary → PDF |
| Signature | Sign → Verify |
