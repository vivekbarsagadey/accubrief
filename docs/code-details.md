Below is a **complete documentation file** that explains the **purpose and responsibilities of every folder and every file** in the AccuBrief project structure.

This document is ready to be exported into a **PDF / DOC** if you want later.

---

# 📄 **AccuBrief – File & Folder Level Documentation**

*Explaining the purpose, usage, and responsibilities of every file.*

Reference: AccuBrief Project Summary 

---

# 1. **Project Root**

```
accubrief/
├── backend/
├── frontend-widget/
├── workers/
├── shared/
├── infrastructure/
├── docs/
├── LICENSE
├── .gitignore
└── README.md
```

### **README.md**

High-level project introduction, installation steps, structure overview.

### **.gitignore**

Specifies files/folders Git should ignore (logs, env files, node_modules, etc.).

### **LICENSE**

Defines licensing terms for usage and distribution of AccuBrief.

---

# 2. **Backend (FastAPI Application)**

```
backend/
└── app/
```

This is the main backend service handling APIs, authentication, AI pipeline, storage, digital signatures, and business logic.

---

## 2.1 **app/main.py**

Main entry point of the FastAPI application.
Responsibilities:

* Initialize FastAPI app
* Register routes
* Include middleware (logging, CORS)
* Health-check endpoint

---

## 2.2 **core/**

```
core/
├── config.py
├── security.py
├── logging.py
└── __init__.py
```

### **config.py**

Central configuration file containing:

* Environment variables
* DB URLs
* S3 credentials
* TURN server details
* LLM/STT API keys

### **security.py**

Handles:

* API key authentication
* JWT token decoding for widget join links
* Tenant validation

### **logging.py**

Defines:

* Structured JSON logs
* Log formatting
* Error logging middleware

### ****init**.py**

Marks folder as Python package.

---

## 2.3 **api/v1/** – Public REST API

```
api/v1/
├── sessions.py
├── recordings.py
├── summaries.py
├── signatures.py
├── webhooks.py
└── __init__.py
```

### **sessions.py**

Endpoints:

* Create session
* Get session info
* End session
* Generate widget URLs
* Start/stop recording commands

### **recordings.py**

Endpoints:

* List all recordings for a session
* Download recording from storage

### **summaries.py**

Endpoints:

* Get summary metadata
* Fetch JSON summary
* Fetch PDF summary
* Manually trigger summary generation

### **signatures.py**

Endpoints:

* Verify signature by summaryId
* Verify document + signature integrity

### **webhooks.py**

Receives:

* summary.ready
* summary.failed
* session.started
* session.ended

### ****init**.py**

Package initializer.

---

## 2.4 **services/** – Business Logic Layer

```
services/
├── session_service.py
├── recording_service.py
├── summary_pipeline_service.py
├── transcription_service.py
├── diarization_service.py
├── llm_summary_service.py
├── webhook_dispatcher.py
└── __init__.py
```

### **session_service.py**

Session lifecycle logic:

* Create session in DB
* Generate join tokens
* Manage host/client roles

### **recording_service.py**

Handles:

* Starting recording
* Receiving uploaded recording file
* Linking recording to session

### **summary_pipeline_service.py**

Main orchestrator for AI workflow:

1. Download recording
2. Convert audio
3. Transcribe (STT)
4. Speaker diarization
5. Summarize using LLM
6. Store JSON summary
7. Generate PDF
8. Call digital signature service
9. Emit webhook events

### **transcription_service.py**

Interfaces with STT engine (Whisper or external).

### **diarization_service.py**

Identifies speakers in the audio file.

### **llm_summary_service.py**

Responsible for:

* Prompt creation
* Calling the LLM
* Returning structured summary components

### **webhook_dispatcher.py**

Sends webhook events to external systems with retries and signatures.

---

## 2.5 **crypto/** – Digital Signature System

```
crypto/
├── kms_service.py
├── signing_service.py
├── verification_service.py
├── utils.py
└── __init__.py
```

### **kms_service.py**

Manages signing keys:

* Loads RSA private/public keys
* Generates new keys (dev mode)
* Returns active signing key

### **signing_service.py**

Creates signatures:

* Canonicalizes JSON
* Hash (SHA-256)
* RSA signing (RS256)
* Returns signature metadata

### **verification_service.py**

Verifies:

* Document hash
* RSA signature validity
* Public key lookup

### **utils.py**

Utility helpers for:

* JSON canonicalization
* Hashing
* Key conversions

---

## 2.6 **models/** – Database ORM Models

```
models/
├── db.py
├── session_model.py
├── participant_model.py
├── recording_model.py
├── summary_model.py
├── signing_key_model.py
├── signature_model.py
└── __init__.py
```

### **db.py**

Database engine & session setup.

### **session_model.py**

Represents a video session.

Fields include:

* sessionId
* tenantId
* status
* tokens

### **participant_model.py**

Represents each participant (host/client).

### **recording_model.py**

Represents uploaded audio/video files.

### **summary_model.py**

Stores:

* summary JSON
* PDF location
* status

### **signing_key_model.py**

Stores public keys and metadata.

### **signature_model.py**

Stores digital signatures:

* signatureId
* summaryId
* publicKeyId
* signatureValue
* hash

---

## 2.7 **schemas/** – Pydantic Validation Models

```
schemas/
├── session.py
├── recording.py
├── summary.py
├── signature.py
├── base.py
└── __init__.py
```

### **session.py**

Request/response shapes for session endpoints.

### **recording.py**

Defines recording metadata and responses.

### **summary.py**

Defines summary structure:

* Overview
* Participants
* Q&A
* Decisions
* Actions

### **signature.py**

Signature request/response schemas.

### **base.py**

Shared schema utilities.

---

## 2.8 **workers/** – Asynchronous Job Workers

```
workers/
├── queue_setup.py
├── summary_worker.py
├── recording_worker.py
└── __init__.py
```

### **queue_setup.py**

Initializes task queues (e.g., RQ/Celery).

### **summary_worker.py**

Executes summary pipeline asynchronously.

### **recording_worker.py**

Handles heavy recording processing tasks.

---

## 2.9 **utils/** – Helper Utilities

```
utils/
├── storage.py
├── token_utils.py
├── time_utils.py
├── pdf_utils.py
├── audio_utils.py
└── __init__.py
```

### **storage.py**

Integrates with S3/GCS/MinIO.

### **token_utils.py**

Generates:

* short-lived join tokens
* Session auth tokens

### **time_utils.py**

Handles formatting, timezone operations.

### **pdf_utils.py**

Converts summary HTML → PDF.

### **audio_utils.py**

Extracts audio, normalizes files.

---

# 3. **Frontend Widget (React)**

The frontend widget is a self-contained UI that can be embedded via iframe.

```
frontend-widget/
└── src/
```

## 3.1 **src/index.tsx**

App entrypoint.

## 3.2 **src/App.tsx**

High-level router/controller for widget render.

---

## 3.3 **components/**

```
components/
├── VideoTile.tsx
├── ControlsBar.tsx
├── RecordingIndicator.tsx
├── ErrorScreen.tsx
└── __init__.txt
```

### **VideoTile.tsx**

Renders local/remote participant video stream.

### **ControlsBar.tsx**

Buttons:

* Mute
* Camera toggle
* End call
* Start/Stop recording

### **RecordingIndicator.tsx**

Red blinking dot or banner during recording.

### **ErrorScreen.tsx**

Shown when token/session invalid.

---

## 3.4 **hooks/**

```
hooks/
├── useWebRTC.ts
├── useSignaling.ts
├── useSession.ts
└── __init__.txt
```

### **useWebRTC.ts**

Manages:

* PeerConnection
* Media streams
* ICE candidates

### **useSignaling.ts**

Handles WebSocket communication for:

* offer/answer
* ICE exchange
* participant events

### **useSession.ts**

Fetches and stores session metadata.

---

## 3.5 **pages/Widget.tsx**

Main widget UI:

* Displays call interface
* Reads sessionId, role, token from URL
* Loads backend data

---

## 3.6 **utils/**

### **api.ts**

Makes API calls to backend:

* Fetch session info
* Trigger recording start
* Fetch configuration

### **config.ts**

Frontend environment configuration.

---

## 3.7 **styles/index.css**

Widget styling.

---

# 4. **Workers**

Separate microservices for heavy tasks.

```
workers/
├── stt_worker/
├── llm_worker/
└── README.md
```

## 4.1 **stt_worker/main.py**

Consumes tasks:

* Speech-to-text
* Upload transcript

## 4.2 **llm_worker/main.py**

Consumes tasks:

* Generate summary
* Format output

---

# 5. **Shared**

```
shared/
├── utils/
└── proto/
```

### **logger.py**

Central logging config usable by all services.

### **types.py**

Common types/models.

### **constants.py**

Shared constants (roles, event types, etc.).

---

# 6. **Infrastructure**

```
infrastructure/
├── docker-compose.yml
├── k8s/
├── scripts/
└── monitoring/
```

### **docker-compose.yml**

Local development environment:

* Backend
* Workers
* MinIO
* Postgres
* TURN server

### **k8s/**/*.yaml**

Production-ready manifests:

* Deployments
* Services
* Ingress
* Secrets

### **scripts/**

Utility scripts for:

* DB setup
* Running tests
* Rotating signing keys

### **monitoring/**

Grafana dashboards & Prometheus configs.

---

# 7. **Docs**

Contains all documentation in Markdown.

```
docs/
├── architecture/
├── integration-guide.md
├── dev-checklists.md
├── roadmap.md
└── README.md
```

### **architecture/high-level-diagram.png**

Visual architecture.

### **api-contract.md**

All API definitions.

### **signature-design.md**

Cryptographic design for signing + verification.

### **integration-guide.md**

How external apps plug AccuBrief into their systems.

### **dev-checklists.md**

Backend / Frontend / DevOps tasks.

---

# ✅ Your Document is Complete

If you want, I can generate:

### ✔ A **downloadable PDF** of this full document

### ✔ A **DOCX formatted version**

### ✔ A **diagram showing how these files interact**

### ✔ A **developer onboarding manual**

Just tell me **PDF**, **DOCX**, or **diagram**.
