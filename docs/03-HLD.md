# High-Level Design (HLD) - AccuBrief

## 1. Introduction

### 1.1 Purpose

This High-Level Design document describes the overall architecture, components, and interactions of the AccuBrief system. It provides architects, developers, and stakeholders with a comprehensive understanding of how the system is structured and how its components work together.

### 1.2 Scope

This document covers:
- System architecture and component overview
- Technology stack decisions
- Data flow and integration patterns
- Deployment architecture
- High-level data model

### 1.3 Document Conventions

- **SHALL**: Mandatory requirement
- **SHOULD**: Recommended but not mandatory
- **MAY**: Optional feature

## 2. System Goals

AccuBrief is a **pluggable service** that provides any platform with:

| Capability | Description |
|------------|-------------|
| Secure Video Calls | WebRTC-based communication via embeddable widget |
| Session Recording | Automatic audio/video capture and storage |
| AI-Powered Summaries | Transcription, diarization, and LLM summarization |
| Digital Signatures | In-house RSA signing for non-repudiation |
| Simple Integration | REST APIs, webhooks, and embeddable widget |

### 2.1 Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Modularity** | Separate services for API, workers, widget |
| **Loose Coupling** | Event-driven communication via queues and webhooks |
| **Multi-Tenancy** | Tenant isolation at data layer |
| **Scalability** | Stateless services, horizontal scaling |
| **Security First** | End-to-end encryption, signed documents |

## 3. System Context

### 3.1 Actors

| Actor | Description |
|-------|-------------|
| **Host Application** | CRM/case management/portal integrating AccuBrief |
| **Host User** | Professional conducting sessions (lawyer, doctor, advisor) |
| **Client User** | End customer/patient participating in sessions |
| **AccuBrief Backend** | FastAPI APIs + signaling + pipeline orchestration |
| **AccuBrief Widget** | React/WebRTC embeddable UI |
| **AI Services** | STT, diarization, LLM providers |
| **Storage Services** | PostgreSQL + S3/MinIO |

### 3.2 Context Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM (CRM / App)                         │
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │  REST API   │    │  Webhooks   │    │     Embedded Widget        │ │
│  │  Consumer   │    │  Receiver   │    │      (iframe/webview)      │ │
│  └──────┬──────┘    └──────▲──────┘    └─────────────┬───────────────┘ │
└─────────┼──────────────────┼────────────────────────┼───────────────────┘
          │                  │                        │
          ▼                  │                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         ACCUBRIEF PLATFORM                              │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │                      API Gateway (FastAPI)                         ││
│  │   /v1/sessions  •  /v1/summaries  •  /v1/signatures  •  /v1/ws    ││
│  └────────────────────────────────────────────────────────────────────┘│
│          │                  ▲                        │                  │
│          ▼                  │                        ▼                  │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────────────┐ │
│  │   Session    │   │   Webhook    │   │     WebSocket Signaling   │ │
│  │   Service    │   │  Dispatcher  │   │     (SDP/ICE Exchange)    │ │
│  └──────┬───────┘   └──────────────┘   └────────────────────────────┘ │
│         │                  ▲                                           │
│         ▼                  │                                           │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │                      Redis Job Queue                              │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│         │                                                              │
│         ▼                                                              │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │                      AI Pipeline Workers                          │ │
│  │  ┌─────────┐  ┌─────────────┐  ┌─────────┐  ┌────────────────┐  │ │
│  │  │   STT   │─▶│ Diarization │─▶│   LLM   │─▶│ PDF + Signing  │  │ │
│  │  │ Worker  │  │   Worker    │  │ Worker  │  │    Worker      │  │ │
│  │  └─────────┘  └─────────────┘  └─────────┘  └────────────────┘  │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│         │                                                              │
│         ▼                                                              │
│  ┌─────────────────────┐  ┌────────────────────────────────────────┐ │
│  │     PostgreSQL      │  │          S3 / MinIO Storage            │ │
│  │  (Metadata Store)   │  │    (Recordings, PDFs, Summaries)       │ │
│  └─────────────────────┘  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTERNAL SERVICES                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐ │
│  │ TURN/STUN   │  │   OpenAI/   │  │   Whisper/  │  │   Pyannote    │ │
│  │   Server    │  │   Ollama    │  │   Deepgram  │  │ Diarization   │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └───────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

## 4. Logical Architecture

### 4.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PRESENTATION LAYER                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    React WebRTC Widget                           │   │
│  │  • Video tiles (local/remote)                                    │   │
│  │  • Control bar (mute, camera, end)                              │   │
│  │  • Recording indicator                                           │   │
│  │  • Error screens                                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              API LAYER                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │
│  │  REST Endpoints │  │ WebSocket Server│  │   Webhook Dispatcher    │ │
│  │  (FastAPI)      │  │ (Signaling)     │  │   (Event Push)          │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            SERVICE LAYER                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │   Session    │  │  Recording   │  │   Summary    │  │  Webhook   │ │
│  │   Service    │  │   Service    │  │   Service    │  │  Service   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘ │
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │Transcription │  │ Diarization  │  │ LLM Summary  │  │   PDF      │ │
│  │   Service    │  │   Service    │  │   Service    │  │  Service   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          CRYPTOGRAPHIC LAYER                            │
│  ┌─────────────────────┐  ┌─────────────────┐  ┌─────────────────────┐ │
│  │    KMS Service      │  │ Signing Service │  │Verification Service │ │
│  │  (Key Management)   │  │ (RSA + SHA256)  │  │ (Signature Verify)  │ │
│  └─────────────────────┘  └─────────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             DATA LAYER                                  │
│  ┌─────────────────────────┐    ┌───────────────────────────────────┐ │
│  │      PostgreSQL         │    │         Object Storage            │ │
│  │  • Sessions             │    │  • Recordings (WebM/MP4)          │ │
│  │  • Participants         │    │  • Summary PDFs                   │ │
│  │  • Recordings (meta)    │    │  • Temp audio files               │ │
│  │  • Summaries            │    │                                   │ │
│  │  • Signatures           │    │                                   │ │
│  │  • Signing Keys         │    │                                   │ │
│  └─────────────────────────┘    └───────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Main Components

#### 4.2.1 API Gateway (FastAPI)

**Responsibilities:**
- Expose REST APIs for session/summary management
- Handle authentication (API keys, JWT tokens)
- Route requests to appropriate services
- Tenant resolution and access control

**Key Endpoints:**
- `POST /v1/sessions` - Create session
- `GET /v1/sessions/{id}` - Get session details
- `POST /v1/sessions/{id}/end` - End session
- `GET /v1/summaries/{id}` - Get summary
- `GET /v1/summaries/{id}/pdf` - Download PDF
- `POST /v1/signatures/verify` - Verify signature

#### 4.2.2 Signaling Service (WebSocket)

**Responsibilities:**
- Manage WebSocket connections per session
- Exchange SDP offers/answers between peers
- Relay ICE candidates
- Handle participant join/leave events

**Message Types:**
- `offer` - SDP offer from initiator
- `answer` - SDP answer from responder
- `ice-candidate` - ICE candidate exchange
- `peer-joined` - Participant joined
- `peer-left` - Participant disconnected

#### 4.2.3 Widget Frontend (React)

**Responsibilities:**
- Render video call UI
- Handle WebRTC peer connections
- Manage media streams (camera, microphone)
- Perform client-side recording
- Upload recordings to backend

**Key Components:**
- `VideoTile` - Render video streams
- `ControlsBar` - Call controls
- `RecordingIndicator` - Recording status
- `useWebRTC` - WebRTC connection hook
- `useSignaling` - WebSocket hook

#### 4.2.4 Recording Management

**Responsibilities:**
- Accept recording uploads from widget
- Store recordings in object storage
- Maintain recording metadata
- Link recordings to sessions

**Storage Pattern:**
```
recordings/{tenant_id}/{session_id}/{recording_id}.webm
```

#### 4.2.5 AI Pipeline Service

**Responsibilities:**
- Orchestrate the summary generation workflow
- Coordinate STT, diarization, and LLM services
- Generate structured summary JSON
- Create PDF documents
- Trigger digital signing

**Pipeline Steps:**
1. Download recording from storage
2. Extract audio from video
3. Transcribe audio → text with timestamps
4. Diarize → identify speakers
5. Summarize → LLM generates structured output
6. Generate PDF → HTML to PDF conversion
7. Sign → digital signature on JSON
8. Notify → webhook to host application

#### 4.2.6 Digital Signature Module

**Responsibilities:**
- Manage RSA key pairs
- Canonicalize JSON documents
- Compute SHA-256 hashes
- Create RSA signatures
- Verify signatures on request

**Algorithm:**
- Key: RSA 2048-bit
- Hash: SHA-256
- Signature: PKCS1v15
- Encoding: Base64

#### 4.2.7 Webhook Dispatcher

**Responsibilities:**
- Send event notifications to host applications
- Sign webhook payloads with HMAC
- Implement retry with exponential backoff
- Log delivery status

**Events:**
- `session.started` - Session became active
- `session.ended` - Session terminated
- `summary.ready` - Summary available
- `summary.failed` - Pipeline failed

## 5. Technology Stack

### 5.1 Backend

| Component | Technology | Rationale |
|-----------|------------|-----------|
| API Framework | FastAPI (Python 3.11+) | Async support, OpenAPI, Python AI ecosystem |
| Database | PostgreSQL 15+ | ACID, JSONB support, reliability |
| ORM | SQLAlchemy | Mature, well-documented |
| Queue | Redis + RQ/Celery | Simple, reliable job queue |
| Object Storage | MinIO / AWS S3 | S3-compatible, self-hosted option |

### 5.2 Frontend

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Framework | React 18+ | Component-based, wide adoption |
| Language | TypeScript | Type safety, developer experience |
| Build | Vite | Fast builds, modern tooling |
| Styling | CSS Modules / Tailwind | Scoped styles, rapid development |
| Video | WebRTC APIs | Browser-native, P2P communication |

### 5.3 AI Pipeline

| Component | Technology | Rationale |
|-----------|------------|-----------|
| STT | Whisper / Deepgram | High accuracy, Python integration |
| Diarization | Pyannote | Open source, speaker identification |
| LLM | OpenAI / Ollama | Flexible, self-hosted option |
| PDF | WeasyPrint / Puppeteer | HTML to PDF conversion |

### 5.4 Infrastructure

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Containerization | Docker | Portable, reproducible |
| Orchestration | Kubernetes | Scalable, self-healing |
| TURN/STUN | Coturn | Open source, WebRTC NAT traversal |
| Monitoring | Prometheus + Grafana | Metrics, alerting, dashboards |
| Logging | Structured JSON + ELK | Searchable, analyzable logs |

## 6. Data Model Overview

### 6.1 Entity Relationships

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌──────────┐       ┌──────────────┐       ┌────────────┐            │
│  │  Tenant  │───┬──▶│   Session    │───┬──▶│ Participant│            │
│  └──────────┘   │   └──────────────┘   │   └────────────┘            │
│                 │          │           │                              │
│                 │          │           └──▶┌────────────┐            │
│                 │          │               │ Recording  │            │
│                 │          │               └────────────┘            │
│                 │          │                                          │
│                 │          ▼                                          │
│                 │   ┌──────────────┐                                  │
│                 │   │   Summary    │──────────┐                       │
│                 │   └──────────────┘          │                       │
│                 │          │                  ▼                       │
│                 │          │          ┌─────────────┐                 │
│                 │          └─────────▶│  Signature  │                 │
│                 │                     └─────────────┘                 │
│                 │                            │                        │
│                 │                            ▼                        │
│                 │                     ┌─────────────┐                 │
│                 └────────────────────▶│ SigningKey  │                 │
│                                       └─────────────┘                 │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### 6.2 Core Entities

| Entity | Description | Key Fields |
|--------|-------------|------------|
| **Tenant** | Organization using AccuBrief | id, name, api_key_hash, webhook_url |
| **Session** | Video session instance | id, tenant_id, status, host, client |
| **Participant** | Person in a session | id, session_id, name, role (host/client) |
| **Recording** | Captured media file | id, session_id, file_path, duration |
| **Summary** | AI-generated document | id, session_id, json_data, pdf_path |
| **Signature** | Digital signature | id, summary_id, signature_value, hash |
| **SigningKey** | RSA key pair (public stored) | id, public_key_pem, algorithm |

## 7. Deployment Architecture

### 7.1 Services Overview

| Service | Instances | Scaling | Description |
|---------|-----------|---------|-------------|
| `accubrief-api` | 2+ | Horizontal | FastAPI application |
| `accubrief-worker` | 2+ | Horizontal | Pipeline workers |
| `accubrief-widget` | CDN | Static | React SPA |
| `postgres` | 1 (Primary) | Vertical | Database |
| `redis` | 1 | Vertical | Job queue |
| `minio` | 1+ | Cluster | Object storage |
| `coturn` | 1+ | Horizontal | TURN/STUN server |

### 7.2 Environment Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION ENVIRONMENT                          │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                        Kubernetes Cluster                          │ │
│  │                                                                     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │ Ingress     │  │ API Pods    │  │ Worker Pods │               │ │
│  │  │ Controller  │─▶│ (2 replicas)│  │ (2 replicas)│               │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │ │
│  │                                                                     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │ PostgreSQL  │  │   Redis     │  │   MinIO     │               │ │
│  │  │ (Stateful)  │  │ (Stateful)  │  │  (Cluster)  │               │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │ │
│  │                                                                     │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌────────────────┐                    ┌────────────────────────────┐ │
│  │  CDN (Widget)  │                    │   TURN Server (Coturn)     │ │
│  └────────────────┘                    └────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Environment Types

| Environment | Purpose | Configuration |
|-------------|---------|---------------|
| **Development** | Local development | docker-compose, single instances |
| **Staging** | Integration testing | K8s, staging database, test TURN |
| **Production** | Live traffic | K8s, HA database, production TURN |

## 8. High-Level Flows

### 8.1 Session Creation Flow

```
1. Host App ──POST /v1/sessions──▶ AccuBrief API
                                        │
2.                                      ├── Validate API Key
3.                                      ├── Create Session in DB
4.                                      ├── Create Participants
5.                                      ├── Generate JWT tokens
6.                                      └── Build Widget URLs
                                        │
7. Host App ◀── SessionResponse ────────┘
   {sessionId, widgetUrls: {host, client}}
```

### 8.2 Call and Recording Flow

```
1. User opens Widget URL
        │
2.      ├── Widget validates JWT token
3.      ├── Widget requests camera/mic permissions
4.      ├── Widget connects to signaling WebSocket
        │
5. Both participants connected
        │
6.      ├── SDP offer/answer exchange
7.      ├── ICE candidate exchange
8.      └── WebRTC P2P connection established
        │
9. Recording starts (auto or manual)
        │
10.     ├── MediaRecorder captures stream
11.     └── Chunks accumulated in memory
        │
12. Host clicks "End Call"
        │
13.     ├── Recording stopped
14.     ├── Blob uploaded to backend
15.     ├── Recording stored in S3
16.     ├── Session status → "ended"
17.     └── Pipeline job enqueued
```

### 8.3 AI Summary Pipeline Flow

```
1. Worker picks up job from queue
        │
2.      ├── Download recording from S3
3.      ├── Extract audio (ffmpeg)
4.      ├── STT transcription
5.      │       └── Text + timestamps
6.      ├── Speaker diarization
7.      │       └── Speaker-labeled segments
8.      ├── LLM summarization
9.      │       └── Structured JSON
10.     ├── PDF generation
11.     ├── Digital signature
12.     │       ├── Canonicalize JSON
13.     │       ├── SHA-256 hash
14.     │       └── RSA sign
15.     ├── Save to database
16.     └── Send webhook: summary.ready
```

### 8.4 Signature Verification Flow

```
1. External System ──POST /v1/signatures/verify──▶ API
                                                     │
2.                     [Option A: By Summary ID]     │
3.                        ├── Load Summary           │
4.                        ├── Load Signature         │
5.                        └── Load Public Key        │
                                                     │
6.                     [Option B: By Document]       │
7.                        ├── Parse document         │
8.                        ├── Parse signature        │
9.                        └── Load Public Key        │
                                                     │
10.                       ├── Canonicalize JSON
11.                       ├── Compute SHA-256
12.                       ├── Compare hash
13.                       ├── RSA verify signature
14.                       └── Return result
                                                     │
15. External System ◀── VerificationResponse ────────┘
    {isValid, reason, documentHash, verifiedAt}
```

## 9. Security Architecture

### 9.1 Authentication

| Context | Method | Details |
|---------|--------|---------|
| API (server-to-server) | API Key | `X-API-Key` header, hashed in DB |
| Widget | JWT Token | Short-lived (15 min), contains sessionId, role |
| Webhooks | HMAC-SHA256 | Signature in `X-AccuBrief-Signature` header |

### 9.2 Authorization

| Resource | Access Control |
|----------|----------------|
| Sessions | Tenant-scoped via API key |
| Summaries | Tenant-scoped, linked to session |
| Recordings | Tenant-scoped, linked to session |
| Widget Join | Token must match session and role |

### 9.3 Data Protection

| Data | Protection |
|------|------------|
| In Transit | TLS 1.2+ for all HTTPS/WSS |
| At Rest | Encryption for S3 objects |
| Signing Keys | Environment variables or KMS |
| API Keys | Hashed before storage |

### 9.4 Digital Signature Integrity

```
Document Integrity Chain:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Summary JSON ──▶ Canonicalize ──▶ SHA-256 ──▶ RSA Sign ──▶ Store  │
│       │                                                      │      │
│       │              Cannot be modified                      │      │
│       └──────────────────────────────────────────────────────┘      │
│                                                                     │
│  Verification: Recompute hash + Verify signature = Tamper-proof    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 10. Integration Patterns

### 10.1 Widget Embedding

```html
<!-- Host View -->
<iframe 
  src="https://widget.accubrief.com/{sessionId}?role=host&token={jwt}"
  allow="camera; microphone"
  width="800"
  height="600"
></iframe>
```

### 10.2 REST API Pattern

```
┌─────────────┐     HTTPS/REST      ┌─────────────────┐
│  Host App   │◀───────────────────▶│  AccuBrief API  │
│  (Server)   │   X-API-Key Auth    │   /v1/...       │
└─────────────┘                     └─────────────────┘
```

### 10.3 Webhook Pattern

```
┌─────────────────┐     HTTPS POST       ┌─────────────┐
│  AccuBrief API  │────────────────────▶│  Host App   │
│  (on event)     │  HMAC-Signed Body    │  Webhook    │
└─────────────────┘                      └─────────────┘
```

## 11. Scalability Considerations

### 11.1 Horizontal Scaling

| Component | Scaling Strategy |
|-----------|------------------|
| API Servers | Stateless, load-balanced |
| Workers | Queue-based, independent |
| Widget | CDN-hosted static assets |

### 11.2 Bottlenecks and Mitigations

| Bottleneck | Mitigation |
|------------|------------|
| Database connections | Connection pooling (pgBouncer) |
| Recording uploads | Direct-to-S3 presigned URLs |
| LLM API rate limits | Queue with rate limiting |
| WebRTC TURN | Multiple TURN servers |

### 11.3 Capacity Estimates

| Metric | Target | Design |
|--------|--------|--------|
| Concurrent sessions | 1000+ | Stateless API, P2P WebRTC |
| Daily sessions | 10,000+ | Async pipeline, worker scaling |
| Storage growth | 1TB/month | S3 lifecycle policies |
| API requests | 100k/day | Caching, read replicas |

## 12. Monitoring and Observability

### 12.1 Metrics

| Category | Metrics |
|----------|---------|
| **API** | Request rate, latency (p50, p95, p99), error rate |
| **Pipeline** | Job queue length, processing time, success rate |
| **WebRTC** | Connection success rate, call duration |
| **Storage** | Upload success rate, object count, size |

### 12.2 Logging

| Log Type | Contents |
|----------|----------|
| **Access Logs** | Request path, method, status, duration |
| **Application Logs** | Errors, warnings, info (structured JSON) |
| **Audit Logs** | Session creation, summary access, verification |

### 12.3 Alerting

| Alert | Condition | Severity |
|-------|-----------|----------|
| API Error Rate | > 1% | Critical |
| Pipeline Queue Backlog | > 100 jobs | Warning |
| Database Connection | < 5 available | Critical |
| TURN Server Down | Health check fail | Critical |
