# Software Requirements Specification (SRS) - AccuBrief v1.0

## 1. Introduction

### 1.1 Purpose

This Software Requirements Specification (SRS) describes all functional and non-functional requirements for **AccuBrief**, a pluggable communication + AI summarization + digital signature system.

This document is intended for:

- Backend Developers
- Frontend Developers
- DevOps & Infrastructure Teams
- QA Team
- Product Managers
- External Integrators

The document ensures a **uniform technical understanding** of the system before and during implementation.

### 1.2 Scope

AccuBrief enables:

- Web-based **video communication** using WebRTC
- **Recording** of sessions
- **Automatic AI-generated summaries** with speaker identification
- **Digital signature creation** on summaries for non-repudiation
- **API-based integration** with any external system
- **Widget embedding** for host/client communication

AccuBrief is **NOT**:
- A CRM or case management tool
- A workflow automation system
- A user authentication provider for host applications
- A group video conferencing solution (1:1 only in v1.0)

It is a standalone *plug-and-play component* that integrates with any application.

### 1.3 Definitions, Acronyms, and Abbreviations

| Term | Definition |
|------|------------|
| **Widget** | Embeddable React UI for video calls |
| **STT** | Speech-to-Text |
| **LLM** | Large Language Model |
| **Diarization** | Automatic detection and attribution of speakers |
| **SignatureMeta** | Metadata of digital signature (signatureId, hash, publicKeyId) |
| **Session** | A communication event between host and client participants |
| **Recording** | Captured audio/video file of a session |
| **Summary** | AI-generated structured document from session recording |
| **Tenant** | An organization or application using AccuBrief |
| **Host** | The professional conducting the session |
| **Client** | The customer/patient/client joining the session |
| **WebRTC** | Web Real-Time Communication protocol |
| **SDP** | Session Description Protocol |
| **ICE** | Interactive Connectivity Establishment |
| **TURN** | Traversal Using Relays around NAT |
| **STUN** | Session Traversal Utilities for NAT |

### 1.4 References

| Document | Description |
|----------|-------------|
| PRD: AccuBrief | Product Requirements Document |
| API Contract | Full API specification |
| HLD/LLD | High-Level and Low-Level Design documents |
| Signature Design | Digital signature module architecture |

### 1.5 Document Overview

- **Section 2**: Overall system description
- **Section 3**: Detailed functional requirements
- **Section 4**: External interface requirements
- **Section 5**: Non-functional requirements
- **Section 6**: System models and diagrams
- **Section 7**: Appendices

## 2. Overall Description

### 2.1 Product Perspective

AccuBrief is designed as an **add-on service** for applications requiring:

- Legal consultations
- Medical appointments
- Financial advisory sessions
- Professional meetings
- Customer service interactions

The system integrates into existing applications via:

- **REST APIs** for session management
- **Webhooks** for event notifications
- **Embeddable widget** (iframe/webview) for video calls

AccuBrief operates as a **loosely coupled service**, requiring no internal database access from the host application.

### 2.2 Product Features (High-Level)

#### Communication Layer
- WebRTC audio/video calls
- WebSocket signaling for SDP/ICE exchange
- TURN/STUN server support for NAT traversal

#### Recording
- Client-side recording using MediaRecorder API
- Automatic upload to secure object storage (S3/MinIO)
- Support for WebM and MP4 formats

#### AI Summary Engine
- Speech-to-Text transcription (Whisper/Deepgram)
- Speaker diarization (Pyannote)
- LLM-based structured summarization (OpenAI/Ollama)
- PDF document generation

#### Digital Signature System
- In-house RSA-based signing
- SHA-256 document hashing
- JSON canonicalization for tamper-proof verification
- Key rotation support
- Public verification API

#### APIs and Integration
- RESTful APIs with versioning (`/v1/...`)
- API key authentication for server-to-server
- JWT tokens for widget authentication
- HMAC-signed webhook notifications

### 2.3 User Classes and Characteristics

| User Class | Description | Technical Expertise |
|------------|-------------|---------------------|
| **Host User** | Professional conducting the session | Low to Medium |
| **Client User** | Customer/patient joining session | Low |
| **Integrator Developer** | Engineer embedding widget and using APIs | High |
| **System Administrator** | DevOps managing deployment | High |
| **Automation Worker** | Background process running AI pipeline | N/A (System) |

### 2.4 Operating Environment

| Component | Environment |
|-----------|-------------|
| **Frontend Widget** | Modern browsers (Chrome 90+, Firefox 88+, Safari 14+, Edge 90+) |
| **Backend API** | Linux containers (Ubuntu 22.04+) |
| **Database** | PostgreSQL 15+ |
| **Object Storage** | S3-compatible (AWS S3, MinIO) |
| **Queue** | Redis 7+ |
| **AI Pipeline** | Python 3.11+ with GPU support (optional) |

### 2.5 Design and Implementation Constraints

| Constraint | Rationale |
|------------|-----------|
| Digital signature must be in-house | No dependency on external signature providers |
| Backend must be Python-only | FastAPI ecosystem, AI library compatibility |
| WebRTC integration via React widget | Browser compatibility, embedding flexibility |
| Sessions must be tenant-aware | Multi-tenancy support from day one |
| Summary must be tamper-proof | Legal non-repudiation requirement |
| API versioning required | Backward compatibility for integrators |

### 2.6 Assumptions and Dependencies

#### Assumptions
- Clients have sufficient bandwidth for video calls (2+ Mbps)
- Integrators properly store and secure their API keys
- Recording upload works reliably (with retry)
- Browsers support WebRTC and MediaRecorder APIs
- LLM providers maintain API availability

#### Dependencies
| Dependency | Purpose | Alternatives |
|------------|---------|--------------|
| TURN/STUN Server | NAT traversal | Coturn, Twilio TURN |
| LLM Provider | Summarization | OpenAI, Ollama, Claude |
| STT Engine | Transcription | Whisper, Deepgram, AssemblyAI |
| Object Storage | Recordings/PDFs | AWS S3, MinIO, GCS |

## 3. System Features (Functional Requirements)

### 3.1 Session Management

#### 3.1.1 Description
Creates and manages one-to-one video communication sessions between host and client participants.

#### 3.1.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-001 | System SHALL allow creation of a session via `POST /v1/sessions` | High |
| FR-002 | System SHALL accept host participant information (name, external_user_id) | High |
| FR-003 | System SHALL accept client participant information (name, external_user_id) | High |
| FR-004 | System SHALL generate unique session ID with `sess_` prefix | High |
| FR-005 | System SHALL generate secure join URLs for host and client roles | High |
| FR-006 | System SHALL create short-lived JWT tokens for widget authentication | High |
| FR-007 | System SHALL allow session termination via `POST /v1/sessions/{id}/end` | High |
| FR-008 | System SHALL update session status through lifecycle states | High |
| FR-009 | System SHALL support session retrieval via `GET /v1/sessions/{id}` | High |
| FR-010 | System SHALL auto-trigger summary pipeline when session ends | High |

### 3.2 WebRTC Communication

#### 3.2.1 Description
Enables real-time audio/video communication between participants using WebRTC protocol.

#### 3.2.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-011 | System SHALL handle WebRTC signaling via WebSocket connections | High |
| FR-012 | System SHALL exchange SDP offers between participants | High |
| FR-013 | System SHALL exchange SDP answers between participants | High |
| FR-014 | System SHALL relay ICE candidates for connection establishment | High |
| FR-015 | System SHALL support TURN server configuration for NAT traversal | High |
| FR-016 | Widget SHALL allow camera enable/disable toggle | High |
| FR-017 | Widget SHALL allow microphone mute/unmute toggle | High |
| FR-018 | Widget SHALL display local video stream | High |
| FR-019 | Widget SHALL display remote participant video stream | High |
| FR-020 | Widget SHALL indicate connection status | Medium |

### 3.3 Recording

#### 3.3.1 Description
Captures audio/video content during sessions for later processing.

#### 3.3.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-021 | Widget SHALL record audio/video using MediaRecorder API | High |
| FR-022 | System SHALL support auto-start recording based on session config | High |
| FR-023 | Widget SHALL display recording indicator when active | High |
| FR-024 | Widget SHALL upload recording blob to backend on stop | High |
| FR-025 | Backend SHALL store recordings in object storage | High |
| FR-026 | Backend SHALL maintain recording metadata in database | High |
| FR-027 | System SHALL support WebM format with VP8 codec | High |
| FR-028 | System SHALL support MP4 format with H.264 codec | Medium |
| FR-029 | System SHALL link recordings to parent session | High |
| FR-030 | System SHALL update recording status (uploaded/processed/failed) | High |

### 3.4 AI Summary Pipeline

#### 3.4.1 Description
Processes recordings to generate transcriptions, speaker-attributed text, and structured summaries.

#### 3.4.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-031 | System SHALL extract audio from video recordings | High |
| FR-032 | System SHALL transcribe audio using STT engine | High |
| FR-033 | System SHALL preserve timestamps in transcription | High |
| FR-034 | System SHALL perform speaker diarization | High |
| FR-035 | System SHALL assign consistent speaker IDs | High |
| FR-036 | System SHALL generate structured summary using LLM | High |
| FR-037 | Summary SHALL include conversation overview | High |
| FR-038 | Summary SHALL include participant list | High |
| FR-039 | Summary SHALL include questions and answers | High |
| FR-040 | Summary SHALL include decisions made | High |
| FR-041 | Summary SHALL include action items | High |
| FR-042 | System SHALL save summary JSON to database | High |
| FR-043 | System SHALL generate PDF from summary | High |
| FR-044 | System SHALL store PDF in object storage | High |
| FR-045 | System SHALL update summary status (pending/processing/ready/failed) | High |

### 3.5 Digital Signature

#### 3.5.1 Description
Provides tamper-proof digital signing of summary documents for non-repudiation.

#### 3.5.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-046 | System SHALL canonicalize summary JSON before signing | High |
| FR-047 | System SHALL compute SHA-256 hash of canonicalized JSON | High |
| FR-048 | System SHALL sign hash using RSA private key (PKCS1v15) | High |
| FR-049 | System SHALL store signature as base64-encoded string | High |
| FR-050 | System SHALL attach signature metadata to summary | High |
| FR-051 | System SHALL support multiple signing keys for rotation | High |
| FR-052 | System SHALL provide verification API for signatures | High |
| FR-053 | Verification SHALL support lookup by summary ID | High |
| FR-054 | Verification SHALL support direct document + signature input | High |
| FR-055 | System SHALL return detailed verification results | High |
| FR-056 | Signature metadata SHALL include publicKeyId | High |
| FR-057 | Signature metadata SHALL include documentHash | High |
| FR-058 | Signature metadata SHALL include algorithm (RS256) | High |

### 3.6 APIs and Integration

#### 3.6.1 Description
Exposes RESTful APIs for external system integration and event notifications.

#### 3.6.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-059 | REST APIs SHALL follow `/v1` versioning pattern | High |
| FR-060 | System SHALL require API key authentication via `X-API-Key` header | High |
| FR-061 | System SHALL validate API key and resolve tenant | High |
| FR-062 | System SHALL provide summary JSON retrieval endpoint | High |
| FR-063 | System SHALL provide PDF download endpoint | High |
| FR-064 | System SHALL provide session information endpoint | High |
| FR-065 | System SHALL send `session.started` webhook | Medium |
| FR-066 | System SHALL send `session.ended` webhook | Medium |
| FR-067 | System SHALL send `summary.ready` webhook | High |
| FR-068 | System SHALL send `summary.failed` webhook | High |
| FR-069 | Webhooks SHALL be HMAC-signed with SHA-256 | High |
| FR-070 | System SHALL retry failed webhooks with backoff | Medium |

### 3.7 Multi-Tenancy

#### 3.7.1 Description
Ensures data isolation between different tenant organizations.

#### 3.7.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-071 | Every database record SHALL have tenant_id field | High |
| FR-072 | All queries SHALL filter by tenant_id | High |
| FR-073 | Sessions SHALL only be accessible to owning tenant | High |
| FR-074 | Summaries SHALL only be accessible to owning tenant | High |
| FR-075 | Recordings SHALL only be accessible to owning tenant | High |
| FR-076 | Cross-tenant access SHALL return 404 Not Found | High |

## 4. External Interface Requirements

### 4.1 User Interfaces

#### 4.1.1 Widget Interface
- Clean, minimal design with video tiles
- Control bar with mute, camera toggle, end call buttons
- Recording indicator (red dot when active)
- Loading states during connection establishment
- Error screens for invalid tokens or permission failures
- Responsive design for various embed sizes

### 4.2 Hardware Interfaces

| Hardware | Usage |
|----------|-------|
| Camera | Video capture via `getUserMedia()` |
| Microphone | Audio capture via `getUserMedia()` |
| Speaker | Audio playback |
| GPU (optional) | Accelerated AI processing |

### 4.3 Software Interfaces

#### 4.3.1 Internal Components

| Component | Interface Type |
|-----------|---------------|
| FastAPI Backend | HTTP/REST |
| PostgreSQL | SQLAlchemy ORM |
| Redis | Queue (RQ/Celery) |
| MinIO/S3 | S3 API |
| TURN/STUN | WebRTC protocols |

#### 4.3.2 External Services

| Service | Interface |
|---------|-----------|
| LLM Provider (OpenAI/Ollama) | REST API |
| STT Engine (Whisper/Deepgram) | REST API / Python library |
| Diarization (Pyannote) | Python library |

### 4.4 Communication Interfaces

| Interface | Protocol | Purpose |
|-----------|----------|---------|
| REST API | HTTPS | Session/Summary management |
| WebSocket | WSS | WebRTC signaling |
| Webhooks | HTTPS POST | Event notifications |
| S3 API | HTTPS | Object storage |
| WebRTC | UDP/TCP | Media streaming |

## 5. Non-Functional Requirements

### 5.1 Performance Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-001 | Session creation response time | < 200ms |
| NFR-002 | WebRTC connection establishment | < 2 seconds |
| NFR-003 | Summary generation (average recording) | < 60 seconds |
| NFR-004 | Widget initial load time | < 1 second |
| NFR-005 | API response time (p95) | < 200ms |
| NFR-006 | Recording upload throughput | > 1 MB/s |
| NFR-007 | Signature verification time | < 100ms |

### 5.2 Scalability Requirements

| ID | Requirement |
|----|-------------|
| NFR-008 | System SHALL support > 1000 concurrent sessions |
| NFR-009 | System SHALL handle > 10,000 API requests/minute |
| NFR-010 | Pipeline workers SHALL scale horizontally |
| NFR-011 | FastAPI backend SHALL be stateless for horizontal scaling |
| NFR-012 | System SHALL support > 100 tenants |

### 5.3 Security Requirements

| ID | Requirement |
|----|-------------|
| NFR-013 | All HTTP communication SHALL use HTTPS/TLS 1.2+ |
| NFR-014 | WebSocket connections SHALL use WSS |
| NFR-015 | Join tokens SHALL expire within 15 minutes |
| NFR-016 | API keys SHALL be hashed before storage |
| NFR-017 | Private signing keys SHALL never be exposed via API |
| NFR-018 | Webhooks SHALL be HMAC-signed |
| NFR-019 | Recordings SHALL be encrypted at rest |
| NFR-020 | Database credentials SHALL be stored in environment variables |

### 5.4 Reliability Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-021 | System uptime | > 99.9% |
| NFR-022 | Recording upload success rate | > 99% |
| NFR-023 | Pipeline job completion rate | > 95% |
| NFR-024 | Failed jobs SHALL trigger failure webhooks | 100% |
| NFR-025 | System SHALL implement retry logic for transient failures | Required |

### 5.5 Maintainability Requirements

| ID | Requirement |
|----|-------------|
| NFR-026 | Code SHALL be modular: api, services, crypto, workers |
| NFR-027 | System SHALL have > 80% unit test coverage |
| NFR-028 | API SHALL support versioning |
| NFR-029 | Configuration SHALL be environment-based |
| NFR-030 | Logging SHALL be structured (JSON) |

### 5.6 Portability Requirements

| ID | Requirement |
|----|-------------|
| NFR-031 | Application SHALL be containerized (Docker) |
| NFR-032 | Application SHALL be deployable on Kubernetes |
| NFR-033 | Widget SHALL work across major browsers |
| NFR-034 | System SHALL support multiple object storage backends |

### 5.7 Compliance Requirements

| ID | Requirement |
|----|-------------|
| NFR-035 | System SHALL support GDPR data handling |
| NFR-036 | System SHALL implement soft delete for audit trails |
| NFR-037 | System SHALL maintain audit fields on all records |
| NFR-038 | Digital signatures SHALL meet legal non-repudiation requirements |

## 6. System Models

### 6.1 Session Lifecycle

```
┌───────────┐    Create    ┌───────────┐   Both Join   ┌───────────┐
│ SCHEDULED │─────────────▶│  ACTIVE   │◀─────────────▶│ RECORDING │
└───────────┘              └───────────┘               └───────────┘
                                 │
                            End Session
                                 │
                                 ▼
                           ┌───────────┐   Pipeline   ┌───────────┐
                           │   ENDED   │────────────▶│ PROCESSING│
                           └───────────┘              └───────────┘
                                                           │
                                              ┌────────────┼────────────┐
                                              ▼            │            ▼
                                        ┌───────────┐      │      ┌───────────┐
                                        │ COMPLETED │      │      │  FAILED   │
                                        └───────────┘      │      └───────────┘
```

### 6.2 Recording and Summary Flow

```
┌─────────────────┐
│  Session Ends   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Recording Saved │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Extract Audio   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ STT Transcribe  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Diarization     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ LLM Summarize   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Generate PDF    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Sign Summary    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Send Webhook    │
└─────────────────┘
```

### 6.3 Digital Signature Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         SIGNING PROCESS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Summary JSON ──▶ Canonicalize ──▶ SHA-256 Hash ──▶ RSA Sign   │
│                   (sort keys,       (compute       (PKCS1v15,   │
│                    no whitespace)    digest)        private key)│
│                                                                 │
│                           Result: Base64 Signature + Metadata   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       VERIFICATION PROCESS                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Document ──▶ Canonicalize ──▶ SHA-256 ──▶ Compare Hash         │
│                               │                                 │
│                               ▼                                 │
│  Signature ──▶ Decode B64 ──▶ RSA Verify ──▶ Valid/Invalid     │
│                               (public key)                      │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 WebRTC Connection Flow

```
Host Widget                  Signaling Server              Client Widget
     │                              │                            │
     │──── Connect WebSocket ──────▶│                            │
     │                              │◀─── Connect WebSocket ─────│
     │                              │                            │
     │──── Create Offer ───────────▶│                            │
     │                              │───── Forward Offer ───────▶│
     │                              │                            │
     │                              │◀──── Create Answer ────────│
     │◀────── Forward Answer ───────│                            │
     │                              │                            │
     │──── ICE Candidates ─────────▶│                            │
     │                              │───── ICE Candidates ──────▶│
     │                              │                            │
     │◀──────────────────── P2P Media Stream ───────────────────▶│
     │                              │                            │
```

## 7. Appendices

### 7.1 Glossary

| Term | Definition |
|------|------------|
| Canonicalization | Converting JSON to a standardized format for consistent hashing |
| Non-repudiation | Inability to deny having signed a document |
| Tenant | An organization using AccuBrief as a service |
| Pipeline | Sequence of processing steps for recordings |
| Widget | Embeddable UI component for video calls |

### 7.2 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-07 | AccuBrief Team | Initial release |
