

# 🚀 **AccuBrief – Full Technical Details (Engineering Specification)**

*Expanded from the project summary + architecture principles.*

---

# 1. **System Architecture Overview**

AccuBrief is a **modular, pluggable, Python-based micro-application** that integrates into any parent system through:

* A **WebRTC-enabled widget** (React)
* **REST APIs** (FastAPI)
* **Digital signature verification APIs**
* **Webhook callbacks**
* **Recording + AI pipeline**

High-level subsystems:

1. **WebRTC Communication Layer (frontend + signaling)**
2. **Recording + Media Handling**
3. **AI Processing Pipeline**
4. **Digital Signature System**
5. **REST API Gateway**
6. **Storage Layer (database + object storage)**

---

# 2. **Technology Stack (Detailed)**

## 2.1 Frontend (WebRTC Widget)

**Languages:** TypeScript / JavaScript
**Framework:** React
**Build:** Vite or Webpack
**Video/Audio:** WebRTC APIs
**Media Handling:** MediaRecorder API
**Signaling Communication:** WebSockets (wss://)
**Integration:** iframe embed / direct link

### Browser APIs used:

* `navigator.mediaDevices.getUserMedia()`
* `RTCPeerConnection`
* `RTCDataChannel` (optional)
* `MediaRecorder`

---

## 2.2 Backend (Python)

**Core Framework:**

* **FastAPI** (fast, async-ready, OpenAPI support)

**Media Server / Signaling:**

* WebSocket server inside FastAPI for WebRTC signaling
* Optional TURN/STUN server (Coturn)

**AI Pipeline Components:**

* Python Whisper (or cloud STT)
* Pyannote / speaker diarization
* LLM summarization (OpenAI, local LLM, or Ollama)

**Digital Signature Engine:**

* RSA key pair generation
* SHA-256 hashing
* Base64 encoding
* Custom signer + verification using `cryptography` library
* No third-party dependency (in-house module)

**Storage:**

* PostgreSQL (for metadata)
* MinIO / S3 / GCS (for recordings & PDFs)
* Redis (optional message queue)

---

## 2.3 AI Layer (Expanded Technical View)

### 1. **Speech-to-Text (Transcription)**

Options:

| Engine              | Notes                          |
| ------------------- | ------------------------------ |
| **Whisper (local)** | High accuracy, Python-friendly |
| **Deepgram**        | Real-time, scalable            |
| **AssemblyAI**      | Easy speaker-detection         |
| **Google STT**      | Industrial grade               |

### 2. **Speaker Diarization**

Required for multi-speaker accuracy:

* Pyannote `SpeakerDiarization` model
* Or built-in diarization if using an advanced STT provider

Output:

```json
[
  { "speaker": "Speaker 1", "text": "...", "start": 1.2, "end": 5.4 },
  { "speaker": "Speaker 2", "text": "...", "start": 5.5, "end": 8.9 }
]
```

### 3. **LLM Summarization**

Prompt fed to LLM:

```
You are a legal-grade summarization AI. 
Identify each speaker, summarize what was asked and answered, extract:
- Questions
- Answers
- Decisions
- Agreements
- Action items
Output clean JSON.
```

LLM transforms diarized transcript → **structured summary**.

---

# 3. **Detailed Component Architecture**

```
+---------------------------+
|   Embeddable Web Widget   |
| (React + WebRTC frontend) |
+------------+--------------+
             |
             | WebSocket (Signaling)
             v
+----------------------------+
|    FastAPI Signaling       |
|  (Offer/Answer exchange)   |
+------------+---------------+
             |
             | WebRTC P2P or via TURN
             v
+----------------------------+
|       Media Recording      |
| (Client-side or SFU mode)  |
+------------+---------------+
             |
             | File Upload (POST)
             v
+----------------------------+
|   Storage (S3 / MinIO)     |
+------------+---------------+
             |
             | Event Trigger
             v
+----------------------------+
|  AI Pipeline Orchestrator  |
| (STT → Diarization → LLM)  |
+------------+---------------+
             |
             | Summary JSON
             v
+----------------------------+
| Digital Signature Engine   |
|  RSA + SHA256 Signatures   |
+------------+---------------+
             |
             | PDF + Metadata
             v
+----------------------------+
|    REST API + Webhooks     |
+----------------------------+
```

---

# 4. **WebRTC Technical Details**

## 4.1 Signaling Messages

Frontend sends:

```json
{
  "type": "offer",
  "sdp": "..."
}
```

Backend relays to other peer:

```json
{
  "type": "answer",
  "sdp": "..."
}
```

ICE exchange messages:

```json
{
  "type": "ice-candidate",
  "candidate": { ... }
}
```

## 4.2 Connection Model

**Option 1 (MVP): P2P WebRTC**
No media servers → lower cost.

**Option 2: TURN-assisted**
For firewalls/NAT issues.

**Option 3 (Scale): SFU (Janus/Mediasoup)**
For multi-party recording or cloud-side recording.

---

# 5. **Recording System (Technical)**

### MVP Recording Design

* Browser’s `MediaRecorder` captures mixed audio+video stream.
* Blob is uploaded to:
  `POST /v1/recordings/upload`

### Recording Format

* WebM or MP4
* 48kHz audio
* H.264 / VP8 video encoding

### Storage Rules

* Stored on S3/minio with naming:
  `/recordings/{sessionId}/{timestamp}.webm`

---

# 6. **Digital Signature Module (Technical)**

(From your earlier request, integrated here)

### Algorithm

* RSA 2048 bits
* SHA256 hashing
* Base64 encoding
* Custom signature schema, no external provider

### Summary Signing Process

1. Summary JSON is canonicalized:

```python
json.dumps(summary, sort_keys=True, separators=(",", ":"))
```

2. Compute hash:

```
SHA256:<hex_digest>
```

3. Sign:

```python
private_key.sign(
    data_bytes,
    padding.PKCS1v15(),
    hashes.SHA256()
)
```

4. Base64 encode signature.

5. Store:

```json
{
  "signatureId": "sig_123",
  "publicKeyId": "accubrief-main-key-1",
  "signatureValue": "base64string",
  "documentHash": "SHA256:abcd1234...",
  "createdAt": "timestamp"
}
```

### Verification API

Client uploads:

* document (base64)
* signature
* publicKeyId

System:

* Repeats hash
* Loads public key
* Verifies integrity

---

# 7. **REST API Technical Details**

## Example – Create Session

```
POST /v1/sessions
```

Payload:

```json
{
  "host": { "name": "John", "id": "123" },
  "client": { "name": "Emma", "id": "999" }
}
```

Backend returns widget URLs:

```json
{
  "sessionId": "sess_abc",
  "widgetUrls": {
    "host": "https://accubrief.app/widget/sess_abc?role=host&token=XYZ",
    "client": "https://accubrief.app/widget/sess_abc?role=client&token=ABC"
  }
}
```

---

# 8. **AI Summary JSON Structure**

Example:

```json
{
  "overview": "High-level summary...",
  "participants": [
    { "name": "Host", "role": "Service Provider" },
    { "name": "Client", "role": "Customer" }
  ],
  "questions": [...],
  "answers": [...],
  "decisions": [...],
  "agreements": [...],
  "actionItems": [...]
}
```

---

# 9. **Integration Model – Technical Details**

AccuBrief is NOT an SDK.
Integrators interact via:

### 1. **Widget**

Embed via:

```html
<iframe src="https://accubrief.app/widget/<sessionId>?token=XYZ"></iframe>
```

### 2. **REST APIs**

For operations:

* Start/stop call
* Upload recording
* Fetch summary
* Verify digital signature

### 3. **Webhooks**

Sent as:

```
POST <client-webhook-url>
Headers:
  X-AccuBrief-Signature: sha256=...
Body:
{
  "event": "summary.ready",
  "sessionId": "...",
  "summaryId": "...",
  "summaryUrl": "..."
}
}
```

---

# 10. **High-Level Data Flow (Deep Technical)**

```
Client → Embed Widget → WebRTC Setup → Recording → Upload → AI Pipeline → Summary JSON → Sign → PDF → Webhook → Verification API
```

Detailed:

1. **Client starts session**
2. Backend generates secure join token
3. WebRTC handshake via FastAPI WebSocket
4. Browser captures recording → uploads to S3
5. Worker processes recording:

   * Extract audio
   * STT with timestamps
   * Diarization
   * Chunk-level LLM summarization
   * Merge segments → Final summary
6. Backend signs JSON summary using RSA
7. Generate PDF (HTML template → PDF)
8. Store outputs in S3
9. Send webhook to host system
10. Host system can fetch a signed summary anytime
11. Anyone can verify signature via public API

---

# 11. **Security Technical Details**

### Communication

* HTTPS everywhere
* WSS for signaling

### Tokens

* Join tokens:

  * Short-lived JWT
  * Encodes sessionId, role (host/client)

### Storage

* Recordings encrypted at rest
* Keys stored in encrypted format

### Non-repudiation

* Digital signature ensures:

  * No tampering
  * No modifications possible after session
  * Audit trail maintained

---

# 12. **Scalability Considerations**

### Horizontal Scalability

* FastAPI backend can run multiple pods
* Recordings/summary pipeline runs asynchronously via workers

### WebRTC

* P2P reduces server load
* TURN only handles NAT traversal
* SFU upgrade path available

### AI Pipeline

* Stateless workers consume jobs from Redis or AWS SQS

---

# 13. **Deployment Details**

Suggested environments:

| Environment | Purpose       |
| ----------- | ------------- |
| dev         | rapid testing |
| staging     | QA + preview  |
| production  | full-scale    |

**Docker + Kubernetes recommended** for production.

---

# ✔️ Your Technical Blueprint Is Ready

If you want, I can now generate:

### 🔹 **A full SRS (Software Requirements Specification)**

### 🔹 **A full HLD + LLD (high-level & low-level design)**

### 🔹 **A system sequence diagram**

### 🔹 **A code-generation starter kit**

### 🔹 **A downloadable PDF of this technical document**

Just tell me **“Generate SRS”**, **“Generate LLD”**, or **“Generate PDF”**.
