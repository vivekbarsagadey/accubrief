# 📘 **Software Requirements Specification (SRS) – AccuBrief v1.0**

---

# **1. Introduction**

## **1.1 Purpose**

This SRS describes all functional and non-functional requirements for **AccuBrief**, a pluggable communication + AI summarization + digital signature system.
It will be used by:

* Backend Developers
* Frontend Developers
* DevOps & Infrastructure Teams
* QA Team
* Product Managers

The document ensures a **uniform technical understanding** of the system before implementation.

---

## **1.2 Scope**

AccuBrief enables:

* Web-based **video communication** using WebRTC
* **Recording** of sessions
* **Automatic AI-generated summaries**
* **Digital signature creation** on summaries
* **API-based integration** with any external system
* **Widget embedding** for host/client communication

AccuBrief is **not** a CRM, case management tool, or workflow system.
It is a standalone *plug-and-play component* that can integrate with any app.

Primary features include:

* Start/end call sessions
* WebRTC video calls
* Audio/video recording
* Speech-to-text transcription
* Speaker diarization
* LLM-based summarization
* JSON + PDF document creation
* Digital signing (in-house, RSA)
* Signature verification API
* Webhooks for event notifications

---

## **1.3 Definitions**

| Term              | Meaning                                    |
| ----------------- | ------------------------------------------ |
| **Widget**        | Embeddable React UI for video calls        |
| **STT**           | Speech-to-Text                             |
| **LLM**           | Large Language Model                       |
| **Diarization**   | Automatic detection of speakers            |
| **SignatureMeta** | Metadata of digital signature              |
| **Session**       | A communication event between participants |
| **Recording**     | Captured audio/video of session            |

---

## **1.4 References**

* AccuBrief Project Summary
* API Contract Specification
* Architecture Diagram
* Digital Signature Module Design

(All provided earlier.)

---

# **2. Overall Description**

## **2.1 Product Perspective**

AccuBrief is designed as **an add-on service** for applications that require:

* Consultations
* Legal advisory
* Doctor–patient conversations
* Customer service discussions
* Professional meetings

The system integrates into existing apps by:

* REST APIs
* Webhooks
* Embeddable widget (iframe)

It operates as a **loosely coupled service**, not requiring internal database access of the host application.

---

## **2.2 Product Features (High-Level)**

### Communication Layer

* WebRTC audio/video call
* WebSocket signaling
* TURN/STUN server support

### Recording

* Client-side recording (MVP)
* Automatic upload to backend storage

### AI Summary Engine

* Transcription (STT)
* Speaker diarization
* Intelligent summarization
* Structured JSON output
* PDF generation

### Digital Signature System

* RSA-based in-house signing
* SHA256 hashing
* Signature verification API

### APIs

* Session management
* Recording handling
* Summary generation & retrieval
* Signature verification

### Integrations

* Webhooks for:

  * session.started
  * session.ended
  * summary.ready
  * summary.failed

---

## **2.3 User Classes**

| User Type                | Description                                  |
| ------------------------ | -------------------------------------------- |
| **Host User**            | Professional conducting the session          |
| **Client User**          | Customer joining session                     |
| **Integrator Developer** | Developer embedding widget and using APIs    |
| **Admin/Support**        | Manages monitoring, logs, and debugging      |
| **Automation Worker**    | Background process that performs AI pipeline |

---

## **2.4 Operating Environment**

* **Frontend:** Browser-based (Chrome, Edge, Firefox, Safari)
* **Backend:** Ubuntu / Linux container
* **Database:** PostgreSQL
* **Storage:** MinIO / AWS S3
* **Networking:** WebRTC-compatible environments
* **AI:** Python-based pipeline, GPU optional

---

## **2.5 Design & Implementation Constraints**

* Digital signature must be in-house, no external providers
* Backend must be **Python-based only**
* WebRTC integration must use **React widget**
* Sessions must be tenant-aware
* Summary must be tamper-proof
* API versioning required (v1/...)

---

## **2.6 Assumptions & Dependencies**

Assumptions:

* Clients have sufficient bandwidth for video calls
* Integrators provide proper API keys
* Recording upload works reliably

Dependencies:

* TURN/STUN server
* LLM provider (OpenAI/Ollama/self-hosted)
* STT engine (Whisper/Deepgram/etc.)

---

# **3. System Features (Functional Requirements)**

---

# **3.1 Feature: Session Management**

### **Description**

Creates and manages one-to-one communication sessions.

### **Functional Requirements**

| ID   | Requirement                                                                 |
| ---- | --------------------------------------------------------------------------- |
| FR-1 | System shall allow creation of a session using POST /v1/sessions            |
| FR-2 | System shall generate secure join URLs (host & client)                      |
| FR-3 | System shall validate join tokens                                           |
| FR-4 | System shall allow session termination                                      |
| FR-5 | System shall update session status (scheduled → active → ended → processed) |

---

# **3.2 Feature: WebRTC Communication**

### **Functional Requirements**

| ID    | Requirement                                                |
| ----- | ---------------------------------------------------------- |
| FR-6  | System shall handle WebRTC signaling via WebSockets        |
| FR-7  | System shall exchange SDP offers/answers                   |
| FR-8  | System shall relay ICE candidates                          |
| FR-9  | System shall support TURN server configuration             |
| FR-10 | Widget must allow video, audio, mute/unmute, camera toggle |

---

# **3.3 Feature: Recording**

### **Functional Requirements**

| ID    | Requirement                                             |
| ----- | ------------------------------------------------------- |
| FR-11 | Widget shall record audio/video using MediaRecorder API |
| FR-12 | System shall upload recording to backend                |
| FR-13 | Backend shall store recording in object storage         |
| FR-14 | Backend shall maintain recording metadata               |

---

# **3.4 Feature: AI Summary Processing**

### **Functional Requirements**

| ID    | Requirement                                           |
| ----- | ----------------------------------------------------- |
| FR-15 | System shall transcribe audio into text               |
| FR-16 | System shall perform speaker diarization              |
| FR-17 | System shall use LLM to generate structured summary   |
| FR-18 | System shall store summary JSON in database           |
| FR-19 | System shall generate summary PDF document            |
| FR-20 | System shall trigger webhooks upon summary completion |

---

# **3.5 Feature: Digital Signature**

### **Functional Requirements**

| ID    | Requirement                                            |
| ----- | ------------------------------------------------------ |
| FR-21 | System shall canonicalize summary JSON                 |
| FR-22 | System shall compute SHA256 hash                       |
| FR-23 | System shall sign summary using RSA private key        |
| FR-24 | System shall attach signature metadata to summary      |
| FR-25 | System shall provide API for verifying signatures      |
| FR-26 | System shall allow multiple public keys (key rotation) |

---

# **3.6 Feature: APIs & Integration**

### **Functional Requirements**

| ID    | Requirement                                 |
| ----- | ------------------------------------------- |
| FR-27 | REST APIs shall follow versioning `/v1`     |
| FR-28 | System shall require API key authentication |
| FR-29 | System shall expose events via Webhooks     |
| FR-30 | System shall provide summary JSON retrieval |
| FR-31 | System shall provide PDF download endpoint  |
| FR-32 | System shall provide session info endpoint  |

---

# **4. External Interface Requirements**

## **4.1 User Interfaces**

* Web Widget UI for host & client
* Clean minimal UI: video tiles, controls, recording indicator
* Error screens (no camera, invalid token, network issue)

---

## **4.2 Hardware Interfaces**

* Camera
* Microphone
* Browser audio/video APIs

---

## **4.3 Software Interfaces**

### Internal

* Python FastAPI
* Redis (queue)
* PostgreSQL
* MinIO/S3
* TURN/STUN

### External

* LLM APIs
* STT APIs

---

## **4.4 Communication Interfaces**

| Interface  | Details                       |
| ---------- | ----------------------------- |
| WebSocket  | Used for signaling (SDP, ICE) |
| HTTPS REST | All API endpoints             |
| Webhooks   | Event push to external apps   |
| S3 API     | Recording + PDF storage       |

---

# **5. Non-Functional Requirements (NFR)**

## **5.1 Performance**

| ID    | Requirement                                                               |
| ----- | ------------------------------------------------------------------------- |
| NFR-1 | Summary generation must complete within 60 seconds for average recordings |
| NFR-2 | Session creation < 200ms                                                  |
| NFR-3 | Widget must connect WebRTC within 2 seconds                               |

---

## **5.2 Scalability**

* Must handle parallel sessions (> 1000/day)
* Pipeline workers horizontally scalable
* Stateless FastAPI nodes

---

## **5.3 Security**

| ID    | Requirement                                          |
| ----- | ---------------------------------------------------- |
| NFR-4 | All communication must be HTTPS                      |
| NFR-5 | Join tokens must expire within 15 minutes            |
| NFR-6 | Private signing keys must never leave secure storage |
| NFR-7 | Webhooks must be HMAC-signed                         |

---

## **5.4 Reliability**

* At least 99% uptime
* Queue-based pipeline ensures retryability
* Failures must generate `summary.failed` webhook

---

## **5.5 Maintainability**

* Code modularized: `api`, `services`, `crypto`, `workers`
* Full unit + integration tests
* API versioning

---

## **5.6 Portability**

* Containerized (Docker)
* Deployable on Kubernetes

---

# **6. System Models**

### **6.1 Session Creation Flow**

1. Client app calls `/v1/sessions`
2. Backend stores session
3. Backend generates host/client URLs
4. Client loads widget

---

### **6.2 Call Flow**

1. Widget initializes WebRTC
2. Connects to signaling WebSocket
3. Negotiates SDP
4. Streams audio/video

---

### **6.3 Recording & Upload Flow**

1. Recording started in widget
2. MediaRecorder produces blob
3. Uploads to backend
4. Stored in S3

---

### **6.4 Summary Pipeline Flow**

1. Worker extracts audio
2. STT → generate transcript
3. Diarization assigns speakers
4. LLM generates summary
5. JSON saved
6. PDF generated
7. Summary signed
8. Webhook triggered

---

### **6.5 Digital Signature Flow**

1. Canonicalize JSON
2. Compute SHA256
3. Sign with RSA private key
4. Save signature
5. Verification endpoint compares hashes & signature

---

# **7. Appendices**

## **7.1 API Reference**

(Separate API Contract Document)

## **7.2 Architectural Diagram**

(Provided in architecture docs)

## **7.3 Digital Signature Design**

(Referenced but separate document)

