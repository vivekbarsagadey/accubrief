# Implementation Guide

**Document Version:** 1.0  
**Last Updated:** December 7, 2025  
**Status:** Active

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Development Environment Setup](#2-development-environment-setup)
3. [Backend Implementation](#3-backend-implementation)
4. [Frontend Widget Implementation](#4-frontend-widget-implementation)
5. [AI Workers Implementation](#5-ai-workers-implementation)
6. [Digital Signature Implementation](#6-digital-signature-implementation)
7. [Database Setup](#7-database-setup)
8. [Testing Strategy](#8-testing-strategy)
9. [Deployment Guide](#9-deployment-guide)
10. [Code Patterns & Best Practices](#10-code-patterns--best-practices)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Introduction

### 1.1 Purpose

This guide provides step-by-step implementation instructions for developers building or extending the AccuBrief platform. It covers:

- Environment setup and dependencies
- Module-by-module implementation patterns
- Code examples and best practices
- Testing and deployment procedures

### 1.2 Prerequisites

**Required Skills:**
- Python 3.11+ (FastAPI, SQLAlchemy, async/await)
- JavaScript/TypeScript (React, WebRTC APIs)
- PostgreSQL database design
- Docker and containerization
- REST API design
- WebSocket protocols

**System Requirements:**
- macOS, Linux, or Windows with WSL2
- 8GB+ RAM (16GB recommended)
- 20GB+ free disk space
- Internet connection for package downloads

---

## 2. Development Environment Setup

### 2.1 Install Prerequisites

#### Python 3.11+

```bash
# macOS (using Homebrew)
brew install python@3.11

# Ubuntu/Debian
sudo apt update
sudo apt install python3.11 python3.11-venv python3.11-dev

# Verify installation
python3.11 --version
```

#### Node.js 18+

```bash
# Using nvm (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
nvm use 18

# Verify installation
node --version
npm --version
```

#### Docker & Docker Compose

```bash
# macOS
brew install --cask docker

# Ubuntu
sudo apt install docker.io docker-compose

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
```

#### PostgreSQL 15+

```bash
# macOS
brew install postgresql@15
brew services start postgresql@15

# Ubuntu
sudo apt install postgresql-15 postgresql-contrib-15
sudo systemctl start postgresql
```

#### Redis

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu
sudo apt install redis-server
sudo systemctl start redis
```

### 2.2 Clone Repository

```bash
git clone https://github.com/vivekbarsagadey/accubrief.git
cd accubrief
```

### 2.3 Environment Configuration

#### Create `.env` File

```bash
cp .env.example .env
```

#### Edit `.env` with Your Configuration

```bash
# Database
DATABASE_URL=postgresql://accubrief:password@localhost:5432/accubrief

# Redis
REDIS_URL=redis://localhost:6379/0

# Storage (MinIO for local, S3 for production)
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=accubrief-recordings
S3_USE_SSL=false

# Security
JWT_SECRET=your-super-secret-jwt-key-change-in-production
API_KEY_SALT=your-api-key-salt-change-in-production

# Digital Signature (generate with: openssl genrsa 2048 | base64)
SIGNING_PRIVATE_KEY=base64-encoded-private-key

# AI Services
OPENAI_API_KEY=sk-your-openai-api-key
WHISPER_MODEL=base  # Options: tiny, base, small, medium, large
PYANNOTE_AUTH_TOKEN=your-huggingface-token

# TURN Server
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=turnuser
TURN_PASSWORD=turnpass
STUN_URL=stun:stun.l.google.com:19302

# Application
APP_ENV=development
LOG_LEVEL=DEBUG
WIDGET_URL=http://localhost:3000
API_BASE_URL=http://localhost:8000
```

### 2.4 Initialize Database

```bash
# Create database
createdb accubrief

# Or using psql
psql -U postgres
CREATE DATABASE accubrief;
\q
```

### 2.5 Start Infrastructure Services

```bash
# Start PostgreSQL, Redis, MinIO
docker-compose up -d postgres redis minio

# Verify services
docker-compose ps
```

---

## 3. Backend Implementation

### 3.1 Setup Backend Environment

```bash
cd backend

# Create virtual environment
python3.11 -m venv venv

# Activate virtual environment
source venv/bin/activate  # macOS/Linux
# or
.\venv\Scripts\activate   # Windows

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

### 3.2 Database Migrations

```bash
# Initialize Alembic (if not already done)
alembic init migrations

# Create initial migration
alembic revision --autogenerate -m "Initial schema"

# Apply migrations
alembic upgrade head

# Check current version
alembic current
```

### 3.3 Implement Core Models

#### Session Model (`models/session_model.py`)

```python
from sqlalchemy import Column, String, DateTime, Boolean, JSON, Enum
from sqlalchemy.orm import relationship
from datetime import datetime
import enum

from app.models.db import Base

class SessionStatus(enum.Enum):
    SCHEDULED = "scheduled"
    ACTIVE = "active"
    ENDED = "ended"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class SessionModel(Base):
    __tablename__ = "sessions"
    
    # Primary Key
    id = Column(String, primary_key=True)  # sess_xxx
    
    # Multi-tenancy
    tenant_id = Column(String, nullable=False, index=True)
    
    # Status
    status = Column(Enum(SessionStatus), default=SessionStatus.SCHEDULED)
    
    # Participants (JSON for flexibility)
    host = Column(JSON, nullable=False)  # {"name": "...", "externalUserId": "..."}
    client = Column(JSON, nullable=False)
    
    # Configuration
    auto_start_recording = Column(Boolean, default=True)
    webhook_url = Column(String, nullable=True)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    started_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Audit fields
    created_by = Column(String, nullable=True)
    updated_by = Column(String, nullable=True)
    deleted_at = Column(DateTime, nullable=True)
    deleted_by = Column(String, nullable=True)
    
    # Relationships
    recordings = relationship("RecordingModel", back_populates="session")
    summaries = relationship("SummaryModel", back_populates="session")
```

#### Recording Model (`models/recording_model.py`)

```python
from sqlalchemy import Column, String, DateTime, Integer, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime

from app.models.db import Base

class RecordingModel(Base):
    __tablename__ = "recordings"
    
    id = Column(String, primary_key=True)  # rec_xxx
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    tenant_id = Column(String, nullable=False, index=True)
    
    # Storage
    file_path = Column(String, nullable=False)  # S3/MinIO path
    file_size = Column(Integer, nullable=True)  # bytes
    duration = Column(Integer, nullable=True)  # seconds
    format = Column(String, default="webm")  # webm, mp4, etc.
    
    # Status
    status = Column(String, default="uploading")  # uploading, ready, failed
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    uploaded_at = Column(DateTime, nullable=True)
    
    # Relationships
    session = relationship("SessionModel", back_populates="recordings")
```

#### Summary Model (`models/summary_model.py`)

```python
from sqlalchemy import Column, String, DateTime, JSON, Boolean, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime

from app.models.db import Base

class SummaryModel(Base):
    __tablename__ = "summaries"
    
    id = Column(String, primary_key=True)  # sum_xxx
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    tenant_id = Column(String, nullable=False, index=True)
    
    # Content
    json_data = Column(JSON, nullable=True)  # Structured summary
    pdf_path = Column(String, nullable=True)  # S3/MinIO path
    transcript = Column(Text, nullable=True)  # Full transcript
    
    # Status
    status = Column(String, default="pending")  # pending, processing, ready, failed
    error_message = Column(String, nullable=True)
    
    # Signature
    signed = Column(Boolean, default=False)
    signature_id = Column(String, ForeignKey("signatures.id"), nullable=True)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    generated_at = Column(DateTime, nullable=True)
    
    # Relationships
    session = relationship("SessionModel", back_populates="summaries")
    signature = relationship("SignatureModel", back_populates="summary")
```

#### Signature Model (`models/signature_model.py`)

```python
from sqlalchemy import Column, String, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime

from app.models.db import Base

class SignatureModel(Base):
    __tablename__ = "signatures"
    
    id = Column(String, primary_key=True)  # sig_xxx
    summary_id = Column(String, ForeignKey("summaries.id"), nullable=False)
    public_key_id = Column(String, ForeignKey("signing_keys.id"), nullable=False)
    
    # Signature data
    document_hash = Column(String, nullable=False)  # SHA256:...
    signature_value = Column(Text, nullable=False)  # Base64 encoded
    algorithm = Column(String, default="RS256")
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    summary = relationship("SummaryModel", back_populates="signature")
    signing_key = relationship("SigningKeyModel")
```

### 3.4 Implement Services

#### Session Service (`services/session_service.py`)

```python
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime
import secrets

from app.models.session_model import SessionModel, SessionStatus
from app.schemas.session import CreateSessionRequest
from app.core.logging import get_logger

logger = get_logger(__name__)

def create_session_service(db: Session):
    """Factory function returning session operations."""
    
    def generate_session_id() -> str:
        """Generate unique session ID."""
        return f"sess_{secrets.token_urlsafe(16)}"
    
    def create_session(request: CreateSessionRequest, tenant_id: str, user_id: str) -> SessionModel:
        """Create a new session."""
        session = SessionModel(
            id=generate_session_id(),
            tenant_id=tenant_id,
            status=SessionStatus.SCHEDULED,
            host=request.host.dict(),
            client=request.client.dict(),
            auto_start_recording=request.auto_start_recording,
            webhook_url=request.webhook_url,
            created_by=user_id
        )
        
        db.add(session)
        db.commit()
        db.refresh(session)
        
        logger.info(f"Created session {session.id} for tenant {tenant_id}")
        return session
    
    def get_session(session_id: str, tenant_id: str) -> Optional[SessionModel]:
        """Get session by ID with tenant isolation."""
        return db.query(SessionModel).filter(
            SessionModel.id == session_id,
            SessionModel.tenant_id == tenant_id,
            SessionModel.deleted_at.is_(None)
        ).first()
    
    def start_session(session_id: str, tenant_id: str, user_id: str) -> SessionModel:
        """Mark session as active."""
        session = get_session(session_id, tenant_id)
        if not session:
            raise ValueError("Session not found")
        
        session.status = SessionStatus.ACTIVE
        session.started_at = datetime.utcnow()
        session.updated_by = user_id
        
        db.commit()
        db.refresh(session)
        
        logger.info(f"Started session {session_id}")
        return session
    
    def end_session(session_id: str, tenant_id: str, user_id: str) -> SessionModel:
        """End session and trigger summary pipeline."""
        session = get_session(session_id, tenant_id)
        if not session:
            raise ValueError("Session not found")
        
        session.status = SessionStatus.ENDED
        session.ended_at = datetime.utcnow()
        session.updated_by = user_id
        
        db.commit()
        db.refresh(session)
        
        # Trigger summary generation (async)
        from app.workers.queue_setup import enqueue_summary_job
        enqueue_summary_job(session_id)
        
        logger.info(f"Ended session {session_id}, queued summary generation")
        return session
    
    return {
        "create_session": create_session,
        "get_session": get_session,
        "start_session": start_session,
        "end_session": end_session,
    }
```

### 3.5 Implement API Routes

#### Session Routes (`api/v1/sessions.py`)

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import get_current_tenant, get_current_user
from app.core.config import get_settings
from app.models.db import get_db
from app.schemas.session import (
    CreateSessionRequest,
    CreateSessionResponse,
    SessionResponse
)
from app.services.session_service import create_session_service
from app.utils.token_utils import create_join_token

router = APIRouter(prefix="/v1/sessions", tags=["sessions"])
settings = get_settings()

@router.post("/", response_model=CreateSessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    request: CreateSessionRequest,
    tenant = Depends(get_current_tenant),
    user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new video session.
    
    Returns widget URLs for host and client with JWT tokens.
    """
    service = create_session_service(db)
    session = service["create_session"](request, tenant.id, user.id)
    
    # Generate JWT tokens for widget access
    host_token = create_join_token(session.id, "host", tenant.id)
    client_token = create_join_token(session.id, "client", tenant.id)
    
    return CreateSessionResponse(
        session_id=session.id,
        widget_urls={
            "host": f"{settings.widget_url}/{session.id}?role=host&token={host_token}",
            "client": f"{settings.widget_url}/{session.id}?role=client&token={client_token}"
        },
        created_at=session.created_at
    )

@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(
    session_id: str,
    tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """Get session details."""
    service = create_session_service(db)
    session = service["get_session"](session_id, tenant.id)
    
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found"
        )
    
    return SessionResponse.from_orm(session)

@router.post("/{session_id}/end", response_model=SessionResponse)
async def end_session(
    session_id: str,
    tenant = Depends(get_current_tenant),
    user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """End a session and trigger summary generation."""
    service = create_session_service(db)
    
    try:
        session = service["end_session"](session_id, tenant.id, user.id)
        return SessionResponse.from_orm(session)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
```

### 3.6 Run Backend Server

```bash
# Development mode (with hot reload)
uvicorn app.main:app --reload --port 8000 --log-level debug

# Production mode
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

**Access API Documentation:**
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

---

## 4. Frontend Widget Implementation

### 4.1 Setup Frontend Environment

```bash
cd frontend-widget

# Install dependencies
npm install

# Start development server
npm run dev
```

### 4.2 Implement WebRTC Hook (`hooks/useWebRTC.ts`)

```typescript
import { useEffect, useRef, useState } from 'react';

interface WebRTCConfig {
  iceServers: RTCIceServer[];
}

export const useWebRTC = (sessionId: string, config: WebRTCConfig) => {
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const peerConnection = useRef<RTCPeerConnection | null>(null);

  useEffect(() => {
    initializeWebRTC();
    
    return () => {
      cleanup();
    };
  }, [sessionId]);

  const initializeWebRTC = async () => {
    try {
      // Get local media stream
      const stream = await navigator.mediaDevices.getUserMedia({
        video: true,
        audio: true
      });
      
      setLocalStream(stream);

      // Create peer connection
      peerConnection.current = new RTCPeerConnection({
        iceServers: config.iceServers
      });

      // Add local tracks to peer connection
      stream.getTracks().forEach(track => {
        peerConnection.current?.addTrack(track, stream);
      });

      // Handle remote stream
      peerConnection.current.ontrack = (event) => {
        setRemoteStream(event.streams[0]);
      };

      // Handle connection state changes
      peerConnection.current.onconnectionstatechange = () => {
        const state = peerConnection.current?.connectionState;
        setIsConnected(state === 'connected');
        
        if (state === 'failed' || state === 'disconnected') {
          setError('Connection failed');
        }
      };

    } catch (err) {
      setError(`Failed to initialize WebRTC: ${err}`);
    }
  };

  const createOffer = async (): Promise<RTCSessionDescriptionInit | null> => {
    if (!peerConnection.current) return null;

    try {
      const offer = await peerConnection.current.createOffer();
      await peerConnection.current.setLocalDescription(offer);
      return offer;
    } catch (err) {
      setError(`Failed to create offer: ${err}`);
      return null;
    }
  };

  const createAnswer = async (offer: RTCSessionDescriptionInit): Promise<RTCSessionDescriptionInit | null> => {
    if (!peerConnection.current) return null;

    try {
      await peerConnection.current.setRemoteDescription(offer);
      const answer = await peerConnection.current.createAnswer();
      await peerConnection.current.setLocalDescription(answer);
      return answer;
    } catch (err) {
      setError(`Failed to create answer: ${err}`);
      return null;
    }
  };

  const handleAnswer = async (answer: RTCSessionDescriptionInit) => {
    if (!peerConnection.current) return;

    try {
      await peerConnection.current.setRemoteDescription(answer);
    } catch (err) {
      setError(`Failed to set remote description: ${err}`);
    }
  };

  const handleIceCandidate = async (candidate: RTCIceCandidateInit) => {
    if (!peerConnection.current) return;

    try {
      await peerConnection.current.addIceCandidate(candidate);
    } catch (err) {
      setError(`Failed to add ICE candidate: ${err}`);
    }
  };

  const toggleAudio = () => {
    if (localStream) {
      localStream.getAudioTracks().forEach(track => {
        track.enabled = !track.enabled;
      });
    }
  };

  const toggleVideo = () => {
    if (localStream) {
      localStream.getVideoTracks().forEach(track => {
        track.enabled = !track.enabled;
      });
    }
  };

  const cleanup = () => {
    localStream?.getTracks().forEach(track => track.stop());
    peerConnection.current?.close();
    setLocalStream(null);
    setRemoteStream(null);
    setIsConnected(false);
  };

  return {
    localStream,
    remoteStream,
    isConnected,
    error,
    createOffer,
    createAnswer,
    handleAnswer,
    handleIceCandidate,
    toggleAudio,
    toggleVideo,
    cleanup
  };
};
```

### 4.3 Implement Signaling Hook (`hooks/useSignaling.ts`)

```typescript
import { useEffect, useRef, useState } from 'react';

interface SignalingMessage {
  type: 'offer' | 'answer' | 'ice-candidate' | 'join' | 'leave';
  data: any;
}

export const useSignaling = (sessionId: string, token: string) => {
  const [isConnected, setIsConnected] = useState(false);
  const [messages, setMessages] = useState<SignalingMessage[]>([]);
  const ws = useRef<WebSocket | null>(null);

  useEffect(() => {
    connect();
    
    return () => {
      disconnect();
    };
  }, [sessionId, token]);

  const connect = () => {
    const wsUrl = `${import.meta.env.VITE_WS_URL}/ws/${sessionId}?token=${token}`;
    ws.current = new WebSocket(wsUrl);

    ws.current.onopen = () => {
      setIsConnected(true);
      send({ type: 'join', data: {} });
    };

    ws.current.onmessage = (event) => {
      const message: SignalingMessage = JSON.parse(event.data);
      setMessages(prev => [...prev, message]);
    };

    ws.current.onclose = () => {
      setIsConnected(false);
    };

    ws.current.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
  };

  const disconnect = () => {
    if (ws.current) {
      ws.current.close();
      ws.current = null;
    }
  };

  const send = (message: SignalingMessage) => {
    if (ws.current?.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify(message));
    }
  };

  return {
    isConnected,
    messages,
    send,
    disconnect
  };
};
```

### 4.4 Run Frontend Widget

```bash
# Development
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

**Access Widget:**
- Development: http://localhost:3000

---

## 5. AI Workers Implementation

### 5.1 Speech-to-Text Worker (`workers/stt_worker/main.py`)

```python
import whisper
from pathlib import Path
from app.core.logging import get_logger
from app.utils.storage import download_file, upload_file

logger = get_logger(__name__)

def transcribe_audio(audio_path: str, model_name: str = "base") -> dict:
    """
    Transcribe audio file using Whisper.
    
    Returns:
        {
            "text": "full transcript",
            "segments": [{"start": 0.0, "end": 5.0, "text": "..."}],
            "language": "en"
        }
    """
    try:
        # Load Whisper model
        model = whisper.load_model(model_name)
        
        # Transcribe
        result = model.transcribe(
            audio_path,
            verbose=False,
            language="en"
        )
        
        return {
            "text": result["text"],
            "segments": result["segments"],
            "language": result["language"]
        }
        
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise

def process_recording(recording_id: str, s3_path: str) -> str:
    """Download recording, transcribe, and upload transcript."""
    
    # Download from S3
    local_path = f"/tmp/{recording_id}.webm"
    download_file(s3_path, local_path)
    
    # Transcribe
    transcript = transcribe_audio(local_path, model_name="base")
    
    # Upload transcript to S3
    transcript_path = f"transcripts/{recording_id}.json"
    upload_file(transcript, transcript_path)
    
    # Cleanup
    Path(local_path).unlink()
    
    return transcript_path
```

### 5.2 Diarization Worker (`services/diarization_service.py`)

```python
from pyannote.audio import Pipeline
from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)
settings = get_settings()

def diarize_audio(audio_path: str) -> list:
    """
    Perform speaker diarization.
    
    Returns:
        [
            {"speaker": "SPEAKER_00", "start": 0.0, "end": 5.0},
            {"speaker": "SPEAKER_01", "start": 5.0, "end": 10.0}
        ]
    """
    try:
        # Load pretrained pipeline
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization",
            use_auth_token=settings.pyannote_auth_token
        )
        
        # Apply diarization
        diarization = pipeline(audio_path)
        
        # Convert to list of segments
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                "speaker": speaker,
                "start": turn.start,
                "end": turn.end
            })
        
        return segments
        
    except Exception as e:
        logger.error(f"Diarization failed: {e}")
        raise
```

### 5.3 LLM Summary Worker (`services/llm_summary_service.py`)

```python
import openai
from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)
settings = get_settings()

openai.api_key = settings.openai_api_key

SUMMARY_PROMPT = """
You are an AI assistant that creates structured summaries of professional conversations.

Given the following transcript with speaker labels, create a comprehensive summary with these sections:

1. Conversation Overview (2-3 paragraphs)
2. Participants (name and role if mentioned)
3. Key Questions & Answers
4. Decisions Made
5. Action Items
6. Next Steps

Format the output as JSON.

Transcript:
{transcript}

Output JSON:
"""

def generate_summary(transcript: str, diarization: list) -> dict:
    """
    Generate structured summary using LLM.
    
    Returns:
        {
            "conversation_overview": "...",
            "participants": [...],
            "questions_and_answers": [...],
            "decisions": [...],
            "action_items": [...],
            "next_steps": [...]
        }
    """
    try:
        # Merge transcript with speaker labels
        labeled_transcript = merge_transcript_with_speakers(transcript, diarization)
        
        # Generate summary with OpenAI
        response = openai.ChatCompletion.create(
            model="gpt-4",
            messages=[
                {"role": "system", "content": "You are a professional meeting summarizer."},
                {"role": "user", "content": SUMMARY_PROMPT.format(transcript=labeled_transcript)}
            ],
            temperature=0.3,
            response_format={"type": "json_object"}
        )
        
        summary = response.choices[0].message.content
        return json.loads(summary)
        
    except Exception as e:
        logger.error(f"Summary generation failed: {e}")
        raise

def merge_transcript_with_speakers(transcript: str, diarization: list) -> str:
    """Merge transcript segments with speaker labels."""
    # Implementation depends on transcript format
    # Match time-stamped segments with speaker labels
    pass
```

---

## 6. Digital Signature Implementation

### 6.1 Key Management (`crypto/kms_service.py`)

```python
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import base64

def generate_key_pair() -> tuple:
    """
    Generate RSA key pair for signing.
    
    Returns:
        (private_key_pem, public_key_pem)
    """
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )
    
    # Serialize private key
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    # Get public key
    public_key = private_key.public_key()
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    
    return (
        base64.b64encode(private_pem).decode(),
        base64.b64encode(public_pem).decode()
    )

def load_private_key(private_key_b64: str):
    """Load private key from base64-encoded PEM."""
    pem = base64.b64decode(private_key_b64)
    return serialization.load_pem_private_key(pem, password=None)

def load_public_key(public_key_b64: str):
    """Load public key from base64-encoded PEM."""
    pem = base64.b64decode(public_key_b64)
    return serialization.load_pem_public_key(pem)
```

### 6.2 Signing Service (`crypto/signing_service.py`)

```python
import json
import hashlib
from base64 import b64encode
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

from app.crypto.kms_service import load_private_key
from app.core.logging import get_logger

logger = get_logger(__name__)

def sign_summary(summary_data: dict, private_key_b64: str, public_key_id: str) -> dict:
    """
    Sign summary JSON with RSA private key.
    
    Returns signature metadata:
        {
            "signature_id": "sig_xxx",
            "public_key_id": "key_001",
            "signature_value": "base64...",
            "document_hash": "SHA256:...",
            "algorithm": "RS256",
            "created_at": "2025-12-07T..."
        }
    """
    try:
        # 1. Canonicalize JSON (sorted keys, no whitespace)
        canonical = json.dumps(summary_data, sort_keys=True, separators=(",", ":"))
        
        # 2. Compute SHA-256 hash
        digest = hashlib.sha256(canonical.encode()).hexdigest()
        document_hash = f"SHA256:{digest}"
        
        # 3. Load private key
        private_key = load_private_key(private_key_b64)
        
        # 4. Sign with RSA
        signature_bytes = private_key.sign(
            canonical.encode(),
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        # 5. Encode signature
        signature_value = b64encode(signature_bytes).decode()
        
        return {
            "signature_id": f"sig_{generate_id()}",
            "public_key_id": public_key_id,
            "signature_value": signature_value,
            "document_hash": document_hash,
            "algorithm": "RS256",
            "created_at": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Signing failed: {e}")
        raise
```

### 6.3 Verification Service (`crypto/verification_service.py`)

```python
from base64 import b64decode
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature

from app.crypto.kms_service import load_public_key
from app.core.logging import get_logger

logger = get_logger(__name__)

def verify_signature(
    document: dict,
    signature_value: str,
    public_key_b64: str
) -> tuple[bool, str]:
    """
    Verify RSA signature.
    
    Returns:
        (is_valid, reason)
    """
    try:
        # 1. Canonicalize document
        canonical = json.dumps(document, sort_keys=True, separators=(",", ":"))
        
        # 2. Load public key
        public_key = load_public_key(public_key_b64)
        
        # 3. Decode signature
        signature_bytes = b64decode(signature_value)
        
        # 4. Verify
        public_key.verify(
            signature_bytes,
            canonical.encode(),
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        return (True, "Signature is valid")
        
    except InvalidSignature:
        return (False, "Invalid signature")
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return (False, f"Verification error: {str(e)}")
```

---

## 7. Database Setup

### 7.1 Database Configuration (`models/db.py`)

```python
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import get_settings

settings = get_settings()

# Create engine
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=20,
    max_overflow=40
)

# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class for models
Base = declarative_base()

def get_db():
    """Dependency for FastAPI routes."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### 7.2 Alembic Configuration (`alembic.ini`)

```ini
[alembic]
script_location = migrations
sqlalchemy.url = postgresql://accubrief:password@localhost:5432/accubrief

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
```

### 7.3 Migration Commands

```bash
# Create migration
alembic revision --autogenerate -m "description"

# Upgrade to latest
alembic upgrade head

# Downgrade one version
alembic downgrade -1

# Show current version
alembic current

# Show history
alembic history --verbose
```

---

## 8. Testing Strategy

### 8.1 Unit Tests (`tests/test_sessions.py`)

```python
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.models.db import Base, get_db

# Test database
SQLALCHEMY_TEST_URL = "postgresql://test:test@localhost:5432/accubrief_test"

engine = create_engine(SQLALCHEMY_TEST_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture
def db():
    """Create test database."""
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
    Base.metadata.drop_all(bind=engine)

@pytest.fixture
def client(db):
    """Create test client."""
    def override_get_db():
        yield db
    
    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)

def test_create_session(client):
    """Test session creation."""
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": "John Doe", "externalUserId": "user_123"},
            "client": {"name": "Jane Smith", "externalUserId": "client_456"},
            "autoStartRecording": True
        },
        headers={"X-API-Key": "test-api-key"}
    )
    
    assert response.status_code == 201
    data = response.json()
    assert "session_id" in data
    assert "widget_urls" in data
```

### 8.2 Integration Tests

```python
def test_end_to_end_session_flow(client):
    """Test complete session flow."""
    # 1. Create session
    create_response = client.post("/v1/sessions", json={...})
    session_id = create_response.json()["session_id"]
    
    # 2. Start session
    start_response = client.post(f"/v1/sessions/{session_id}/start")
    assert start_response.status_code == 200
    
    # 3. End session
    end_response = client.post(f"/v1/sessions/{session_id}/end")
    assert end_response.status_code == 200
    
    # 4. Verify summary generation queued
    # ... check queue ...
```

### 8.3 Run Tests

```bash
# All tests
pytest tests/ -v

# Specific test file
pytest tests/test_sessions.py -v

# With coverage
pytest tests/ --cov=app --cov-report=html

# Open coverage report
open htmlcov/index.html
```

---

## 9. Deployment Guide

### 9.1 Docker Deployment

#### Build Images

```bash
# Backend
docker build -t accubrief-backend:latest ./backend

# Frontend Widget
docker build -t accubrief-widget:latest ./frontend-widget

# Workers
docker build -t accubrief-stt-worker:latest ./workers/stt_worker
docker build -t accubrief-llm-worker:latest ./workers/llm_worker
```

#### Run with Docker Compose

```bash
# Start all services
docker-compose -f infrastructure/docker-compose.yml up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f backend

# Stop services
docker-compose down
```

### 9.2 Kubernetes Deployment

#### Apply Configurations

```bash
# Create namespace
kubectl create namespace accubrief

# Apply secrets
kubectl apply -f infrastructure/k8s/secrets.yaml

# Deploy services
kubectl apply -f infrastructure/k8s/backend-deployment.yaml
kubectl apply -f infrastructure/k8s/backend-service.yaml
kubectl apply -f infrastructure/k8s/widget-deployment.yaml
kubectl apply -f infrastructure/k8s/widget-service.yaml
kubectl apply -f infrastructure/k8s/worker-deployment.yaml

# Apply ingress
kubectl apply -f infrastructure/k8s/ingress.yaml

# Check deployments
kubectl get pods -n accubrief
kubectl get services -n accubrief
```

#### Scaling

```bash
# Scale backend
kubectl scale deployment accubrief-backend --replicas=3 -n accubrief

# Scale workers
kubectl scale deployment accubrief-stt-worker --replicas=2 -n accubrief
```

### 9.3 Environment Variables (Production)

```bash
# Use Kubernetes secrets or AWS Secrets Manager
kubectl create secret generic accubrief-secrets \
  --from-literal=database-url='postgresql://...' \
  --from-literal=jwt-secret='...' \
  --from-literal=signing-private-key='...' \
  --from-literal=openai-api-key='...' \
  -n accubrief
```

---

## 10. Code Patterns & Best Practices

### 10.1 Multi-Tenancy Pattern

**ALWAYS filter by `tenant_id`:**

```python
# ❌ FORBIDDEN - Security vulnerability
sessions = db.query(SessionModel).all()

# ✅ REQUIRED
sessions = db.query(SessionModel).filter(
    SessionModel.tenant_id == tenant.id
).all()
```

### 10.2 Soft Delete Pattern

**NEVER hard delete:**

```python
# ❌ FORBIDDEN
db.delete(session)

# ✅ REQUIRED
session.status = "DELETED"
session.deleted_at = datetime.utcnow()
session.deleted_by = user_id
db.commit()
```

### 10.3 Error Handling Pattern

```python
from fastapi import HTTPException, status

@router.get("/{session_id}")
async def get_session(session_id: str, tenant=Depends(get_current_tenant)):
    try:
        service = create_session_service(db)
        session = service["get_session"](session_id, tenant.id)
        
        if not session:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Session {session_id} not found"
            )
        
        return SessionResponse.from_orm(session)
        
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )
```

### 10.4 Logging Pattern

```python
from app.core.logging import get_logger

logger = get_logger(__name__)

def process_session(session_id: str):
    logger.info(f"Processing session {session_id}")
    
    try:
        # ... process ...
        logger.info(f"Session {session_id} processed successfully")
        
    except Exception as e:
        logger.error(f"Failed to process session {session_id}: {e}", exc_info=True)
        raise
```

### 10.5 Functional Service Pattern

```python
def create_session_service(db: Session):
    """Factory returning session operations."""
    
    def create_session(request, tenant_id, user_id):
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
session = service["create_session"](request, tenant.id, user.id)
```

---

## 11. Troubleshooting

### 11.1 Common Issues

#### Database Connection Errors

**Problem:** `sqlalchemy.exc.OperationalError: could not connect to server`

**Solution:**
```bash
# Check PostgreSQL is running
pg_isready

# Restart PostgreSQL
brew services restart postgresql@15  # macOS
sudo systemctl restart postgresql    # Linux

# Check connection
psql -U accubrief -d accubrief
```

#### Redis Connection Errors

**Problem:** `redis.exceptions.ConnectionError`

**Solution:**
```bash
# Check Redis is running
redis-cli ping

# Start Redis
brew services start redis           # macOS
sudo systemctl start redis          # Linux
```

#### WebRTC Connection Failures

**Problem:** Peers cannot connect

**Solution:**
1. Check TURN/STUN server configuration
2. Verify firewall rules allow UDP traffic
3. Test with public STUN server:
   ```javascript
   iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
   ```

#### Recording Upload Failures

**Problem:** `MinIO connection refused`

**Solution:**
```bash
# Check MinIO is running
docker-compose ps minio

# Access MinIO console
open http://localhost:9001

# Verify bucket exists
mc ls local/accubrief-recordings
```

### 11.2 Debug Mode

**Enable debug logging:**

```bash
# Backend
export LOG_LEVEL=DEBUG
uvicorn app.main:app --reload --log-level debug

# Frontend
export VITE_LOG_LEVEL=debug
npm run dev
```

**Check logs:**

```bash
# Docker logs
docker-compose logs -f backend

# Kubernetes logs
kubectl logs -f deployment/accubrief-backend -n accubrief

# Application logs
tail -f /var/log/accubrief/app.log
```

### 11.3 Performance Issues

**Database query optimization:**

```python
# Add indexes
from sqlalchemy import Index

Index('idx_sessions_tenant_status', SessionModel.tenant_id, SessionModel.status)

# Use query profiling
from sqlalchemy import event
from sqlalchemy.engine import Engine
import time

@event.listens_for(Engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    conn.info.setdefault('query_start_time', []).append(time.time())

@event.listens_for(Engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    total = time.time() - conn.info['query_start_time'].pop(-1)
    logger.info(f"Query took {total:.4f}s: {statement}")
```

---

## Appendix

### A. Useful Commands

```bash
# Backend
cd backend && source venv/bin/activate
uvicorn app.main:app --reload
alembic upgrade head
pytest tests/ -v

# Frontend
cd frontend-widget
npm run dev
npm run build
npm run lint

# Docker
docker-compose up -d
docker-compose logs -f
docker-compose down -v

# Kubernetes
kubectl get pods -n accubrief
kubectl logs -f pod/accubrief-backend-xxx -n accubrief
kubectl exec -it pod/accubrief-backend-xxx -n accubrief -- bash

# Database
psql -U accubrief -d accubrief
\dt  # List tables
\d sessions  # Describe table
```

### B. IDE Setup

**VS Code Extensions:**
- Python
- Pylance
- ESLint
- Prettier
- Docker
- Kubernetes

**VS Code Settings (`.vscode/settings.json`):**

```json
{
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": false,
  "python.linting.ruffEnabled": true,
  "python.formatting.provider": "black",
  "editor.formatOnSave": true,
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter"
  }
}
```

### C. Git Workflow

```bash
# Create feature branch
git checkout -b feature/session-recording

# Commit changes
git add .
git commit -m "feat: implement session recording"

# Push to remote
git push origin feature/session-recording

# Create pull request on GitHub
```

---

**Document End**

For questions or support, contact: engineering@accubrief.com
