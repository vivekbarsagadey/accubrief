## Overview

**AccuBrief** is a pluggable service that provides any platform with:

- 🎥 **Secure Video Calls** via embeddable widget
- 🎙️ **Automatic Recording** with cloud storage
- 🤖 **AI-Powered Summaries** with transcription & speaker diarization
- ✍️ **Digitally Signed Documents** for legal non-repudiation
- 🔗 **Simple Integration** via REST APIs + Webhooks + Widget

Perfect for **legal consultations**, **medical appointments**, **professional meetings**, and any scenario requiring documented conversations with verifiable authenticity.

---

## Features

### 🎥 Communication Layer
- WebRTC audio/video calls with P2P connectivity
- WebSocket-based signaling server
- TURN/STUN server support for NAT traversal
- Embeddable React widget (iframe/webview)

### 📹 Recording
- Client-side recording using MediaRecorder API
- Automatic upload to secure object storage (S3/MinIO)
- Support for multiple recording formats

### 🤖 AI Summary Engine
- **Speech-to-Text**: Whisper / Deepgram integration
- **Speaker Diarization**: Automatic speaker identification (Pyannote)
- **LLM Summarization**: Structured summaries via OpenAI/Ollama
- **PDF Generation**: Professional document output

### 🔐 Digital Signature System
- In-house RSA-based signing (no third-party dependencies)
- SHA-256 document hashing
- JSON canonicalization for tamper-proof verification
- Key rotation support
- Verification API for external systems

### 🔌 Integration & APIs
- RESTful APIs with versioning (`/v1/...`)
- Webhook notifications for async events
- API key authentication for server-to-server
- JWT tokens for widget authentication

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Host System (CRM/App)                      │
│                    REST APIs  +  Webhooks                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AccuBrief API (FastAPI)                     │
│         Sessions • Summaries • Signatures • Recordings          │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  WebRTC Widget   │ │   AI Pipeline    │ │ Digital Signature│
│  (React/TS)      │ │ (STT+Diarize+LLM)│ │     Engine       │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

### Technology Stack

| Component | Technology |
|-----------|------------|
| Backend API | Python 3.11+ / FastAPI |
| Database | PostgreSQL |
| Object Storage | MinIO / AWS S3 |
| Queue | Redis (RQ/Celery) |
| Frontend Widget | React + TypeScript + WebRTC |
| Speech-to-Text | Whisper / Deepgram |
| Diarization | Pyannote |
| LLM | OpenAI / Ollama / Self-hosted |
| Digital Signature | In-house RSA (cryptography) |

---

## Project Structure

```
accubrief/
├── backend/                    # FastAPI Backend
│   └── app/
│       ├── main.py             # Application entry point
│       ├── api/v1/             # REST API endpoints
│       ├── core/               # Config, security, logging
│       ├── crypto/             # Digital signature module
│       ├── models/             # SQLAlchemy ORM models
│       ├── schemas/            # Pydantic schemas
│       ├── services/           # Business logic layer
│       ├── utils/              # Utility functions
│       └── workers/            # Background job handlers
├── frontend-widget/            # React WebRTC Widget
│   └── src/
│       ├── components/         # UI components
│       ├── hooks/              # React hooks (WebRTC, signaling)
│       ├── pages/              # Page components
│       └── utils/              # Helper functions
├── workers/                    # Standalone AI Workers
│   ├── stt_worker/             # Speech-to-text worker
│   └── llm_worker/             # LLM summarization worker
├── shared/                     # Shared utilities
├── infrastructure/             # Docker, K8s, monitoring
│   ├── docker-compose.yml
│   ├── k8s/
│   └── scripts/
└── docs/                       # Documentation
```

---

## Quick Start

### Prerequisites

- Python 3.11+
- Node.js 18+
- Docker & Docker Compose
- PostgreSQL 15+
- Redis

### 1. Clone the Repository

```bash
git clone https://github.com/vivekbarsagadey/accubrief.git
cd accubrief
```

### 2. Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Edit with your configuration
vim .env
```

**Required Environment Variables:**

```bash
# Database
DATABASE_URL="postgresql://user:pass@localhost:5432/accubrief"

# Storage
S3_ENDPOINT="http://localhost:9000"
S3_ACCESS_KEY="minioadmin"
S3_SECRET_KEY="minioadmin"
S3_BUCKET="accubrief-recordings"

# Security
JWT_SECRET="your-jwt-secret-key"
SIGNING_PRIVATE_KEY="base64-encoded-private-key"

# AI Services
OPENAI_API_KEY="sk-..."
WHISPER_MODEL="base"

# Redis
REDIS_URL="redis://localhost:6379"

# TURN Server
TURN_URL="turn:your-turn-server.com:3478"
TURN_USERNAME="turnuser"
TURN_PASSWORD="turnpass"
```

### 3. Start with Docker Compose

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f backend
```

### 4. Run Database Migrations

```bash
docker-compose exec backend alembic upgrade head
```

### 5. Access the Services

| Service | URL |
|---------|-----|
| Backend API | http://localhost:8000 |
| API Docs | http://localhost:8000/docs |
| Widget | http://localhost:3000 |
| MinIO Console | http://localhost:9001 |

---

## API Reference

### Authentication

All API requests require an API key:

```bash
curl -X GET "https://api.accubrief.com/v1/sessions" \
  -H "X-API-Key: your-api-key"
```

### Core Endpoints

#### Sessions

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/sessions` | Create a new session |
| `GET` | `/v1/sessions/{sessionId}` | Get session details |
| `POST` | `/v1/sessions/{sessionId}/end` | End a session |

**Create Session Request:**

```json
{
  "host": {
    "name": "John Doe",
    "externalUserId": "user_123"
  },
  "client": {
    "name": "Jane Smith",
    "externalUserId": "client_456"
  },
  "autoStartRecording": true,
  "webhookUrl": "https://your-app.com/webhooks/accubrief"
}
```

**Create Session Response:**

```json
{
  "sessionId": "sess_abc123",
  "widgetUrls": {
    "host": "https://widget.accubrief.com/sess_abc123?role=host&token=...",
    "client": "https://widget.accubrief.com/sess_abc123?role=client&token=..."
  },
  "createdAt": "2025-12-06T10:30:00Z"
}
```

#### Summaries

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/summaries/{summaryId}` | Get summary JSON |
| `GET` | `/v1/summaries/{summaryId}/pdf` | Download summary PDF |

**Summary Response:**

```json
{
  "summaryId": "sum_xyz789",
  "sessionId": "sess_abc123",
  "generatedAt": "2025-12-06T11:00:00Z",
  "signed": true,
  "sections": {
    "conversationOverview": "Discussion about project requirements...",
    "participants": [
      { "name": "John Doe", "role": "host" },
      { "name": "Jane Smith", "role": "client" }
    ],
    "questionsAndAnswers": [...],
    "decisions": [...],
    "actionItems": [...]
  },
  "signatureMeta": {
    "signatureId": "sig_def456",
    "documentHash": "SHA256:abc123...",
    "publicKeyId": "key_001",
    "signatureAlgorithm": "RS256"
  }
}
```

#### Signature Verification

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/signatures/verify` | Verify a signature |

**Verify by Summary ID:**

```json
{
  "summaryId": "sum_xyz789"
}
```

**Verify by Document:**

```json
{
  "document": "base64-encoded-json",
  "signatureValue": "base64-encoded-signature",
  "publicKeyId": "key_001"
}
```

**Verification Response:**

```json
{
  "isValid": true,
  "reason": null,
  "summaryId": "sum_xyz789",
  "documentHash": "SHA256:abc123...",
  "verifiedAt": "2025-12-06T12:00:00Z"
}
```

### Webhooks

AccuBrief sends webhook notifications for key events:

| Event | Description |
|-------|-------------|
| `session.started` | Session has begun |
| `session.ended` | Session has ended |
| `summary.ready` | Summary is generated and signed |
| `summary.failed` | Summary generation failed |

**Webhook Payload:**

```json
{
  "event": "summary.ready",
  "timestamp": "2025-12-06T11:00:00Z",
  "data": {
    "sessionId": "sess_abc123",
    "summaryId": "sum_xyz789"
  }
}
```

**Webhook Signature:**

All webhooks include HMAC signature for verification:

```
X-AccuBrief-Signature: sha256=abc123...
```

---

## Integration

### Embedding the Widget

```html
<!-- Host View -->
<iframe 
  src="https://widget.accubrief.com/sess_abc123?role=host&token=..."
  allow="camera; microphone"
  width="800"
  height="600">
</iframe>

<!-- Client View -->
<iframe 
  src="https://widget.accubrief.com/sess_abc123?role=client&token=..."
  allow="camera; microphone"
  width="800"
  height="600">
</iframe>
```

### Webhook Handler Example (Python)

```python
import hmac
import hashlib
from fastapi import FastAPI, Request, HTTPException

app = FastAPI()
WEBHOOK_SECRET = "your-webhook-secret"

@app.post("/webhooks/accubrief")
async def handle_webhook(request: Request):
    # Verify signature
    body = await request.body()
    signature = request.headers.get("X-AccuBrief-Signature", "")
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(),
        body,
        hashlib.sha256
    ).hexdigest()
    
    if not hmac.compare_digest(signature, expected):
        raise HTTPException(status_code=401, detail="Invalid signature")
    
    # Process event
    payload = await request.json()
    event = payload["event"]
    
    if event == "summary.ready":
        summary_id = payload["data"]["summaryId"]
        # Fetch and process summary...
    
    return {"status": "received"}
```

---

## Development

### Running Locally

**Backend:**

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run with hot reload
uvicorn app.main:app --reload --port 8000
```

**Frontend Widget:**

```bash
cd frontend-widget
npm install
npm run dev
```

**Workers:**

```bash
cd workers/stt_worker
pip install -r requirements.txt
python main.py
```

### Running Tests

```bash
# Backend tests
cd backend
pytest tests/ -v

# Frontend tests
cd frontend-widget
npm test

# All tests with coverage
./infrastructure/scripts/run_tests.sh --coverage
```

### Code Quality

```bash
# Spell check
./infrastructure/scripts/spellcheck.sh

# Linting (backend)
cd backend && ruff check .

# Linting (frontend)
cd frontend-widget && npm run lint
```

---

## Deployment

### Docker

```bash
# Build images
docker build -t accubrief-backend ./backend
docker build -t accubrief-widget ./frontend-widget
docker build -t accubrief-stt-worker ./workers/stt_worker
docker build -t accubrief-llm-worker ./workers/llm_worker

# Run with compose
docker-compose -f infrastructure/docker-compose.yml up -d
```

### Kubernetes

```bash
# Apply configurations
kubectl apply -f infrastructure/k8s/

# Check deployments
kubectl get pods -n accubrief
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Design Document](docs/design-document.md) | High & Low Level Design |
| [SRS](docs/srs.md) | Software Requirements Specification |
| [Code Details](docs/code-details.md) | File & Folder Documentation |
| [Integration Guide](docs/integration-guide.md) | Integration Instructions |
| [API Contract](docs/architecture/api-contract.md) | Full API Specification |
| [Signature Design](docs/architecture/signature-design.md) | Digital Signature Module |

---

## Security

- 🔒 All communication over HTTPS
- 🔑 API key authentication for server-to-server
- ⏱️ JWT tokens expire within 15 minutes
- 🔐 Private signing keys stored securely (never exposed)
- ✅ HMAC-signed webhooks for authenticity
- 🏢 Multi-tenant isolation via `tenant_id`

### Reporting Vulnerabilities

Please report security vulnerabilities to: security@accubrief.com

---

## Performance

| Metric | Target |
|--------|--------|
| Session creation | < 200ms |
| WebRTC connection | < 2 seconds |
| Summary generation | < 60 seconds (avg) |
| Concurrent sessions | > 1000/day |

---

## Roadmap

- [x] Core video calling with WebRTC
- [x] Recording & storage
- [x] AI transcription & summarization
- [x] Digital signature system
- [ ] Multi-language support
- [ ] Real-time transcription
- [ ] Mobile SDK (iOS/Android)
- [ ] Advanced analytics dashboard

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and development process.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Support

- 📧 Email: support@accubrief.com
- 📖 Documentation: [docs.accubrief.com](https://docs.accubrief.com)
- 🐛 Issues: [GitHub Issues](https://github.com/vivekbarsagadey/accubrief/issues)

---

<p align="center">
  Built with ❤️ by the AccuBrief Team
</p>
