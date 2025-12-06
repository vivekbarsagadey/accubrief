**design document** you can hand to architects + devs.

I’ll split it into:

* **Part 1 – HLD (High-Level Design)**
* **Part 2 – LLD (Low-Level Design)**

---

# Part 1 – High-Level Design (HLD)

## 1. System Goals

AccuBrief is a **pluggable service** that gives any platform:

* **Secure video calls** (via widget)
* **Recording → AI-powered summaries**
* **Digitally signed summary documents** (non-repudiation)
* **Simple integration via REST + Webhooks + Widget**

It must be:

* Backend: **Python (FastAPI)** only
* Frontend: **React-based widget** using WebRTC
* Digital signature: **in-house**, no 3rd-party signer

---

## 2. System Context

### 2.1 Actors

* **Host Application** (CRM / case mgmt / portal)
* **Host User** (lawyer/consultant/doctor)
* **Client User** (end customer)
* **AccuBrief Backend** (FastAPI APIs + signaling + pipeline)
* **AccuBrief Widget** (React/WebRTC)
* **AI Services** (STT, diarization, LLM)
* **Storage Services** (DB + object storage)

### 2.2 Context Diagram (conceptual)

```
Host System (CRM / App)
   |  REST APIs  +  Webhooks
   v
+-----------------------------+
|        AccuBrief API        |
| (sessions, summaries, sigs) |
+------------+----------------+
             |
             | generates widget URLs
             v
       Host Embeds Widget
         (iframe/webview)
     Host User <-> Client User
          | WebRTC via browser
          v
+-----------------------------+
| WebRTC Signaling (WS API)   |
+-----------------------------+
             |
             v
   Recordings -> Object Storage
             |
             v
+-----------------------------+
|  AI Pipeline (STT, LLM)     |
+-----------------------------+
             |
             v
+-----------------------------+
| Digital Signature Engine    |
+-----------------------------+
             |
             v
     Signed JSON + PDF
             |
             v
    Webhooks back to host
```

---

## 3. Logical Architecture

### 3.1 Main Components

1. **API Gateway (FastAPI)**

   * Exposes REST APIs (`/v1/sessions`, `/v1/summaries`, `/v1/signatures/verify`)
   * Handles auth, tenant resolution, session orchestration

2. **Signaling Service (WebSocket)**

   * WebRTC signaling (offer/answer/ICE messaging)
   * Manages per-session “rooms”

3. **Widget Frontend (React)**

   * Embeddable UI (iframe / new tab)
   * Handles WebRTC media, recording, basic UX

4. **Recording Management**

   * Accepts recording uploads (MVP: client-to-backend upload)
   * Stores in object storage (S3/MinIO)

5. **AI Pipeline Service**

   * Transcription (STT)
   * Speaker diarization
   * LLM-based summarization
   * Generates structured summary JSON + PDF

6. **Digital Signature Module**

   * In-house RSA key management
   * JSON canonicalization + SHA-256 hashing
   * Signing + verification

7. **Storage Layer**

   * **PostgreSQL** – metadata (sessions, recordings, summaries, signatures, tenants)
   * **Object Storage** – raw recordings, generated PDFs
   * (Optional Redis/Queue) – for pipeline jobs

8. **Webhook Dispatcher**

   * Sends event notifications to host system (summary.ready, summary.failed, etc.)

---

## 4. Deployment Architecture

### 4.1 Services

* `accubrief-api` (FastAPI app)
* `accubrief-worker` (async pipeline worker – could be separate deployable)
* `accubrief-widget` (React SPA – static hosting)
* `coturn` (STUN/TURN)
* `postgres`
* `minio` (or S3)
* `redis` (if using queue like RQ/Celery)

### 4.2 Environment Layout

* **Dev:** docker-compose with all services
* **Staging:** K8s cluster, staging DB, STUN/TURN
* **Prod:** Multi-node K8s, load-balanced, auto-scaling workers

---

## 5. Data Model Overview (HLD)

Key entities:

* **Tenant**
* **Session**
* **Participant**
* **Recording**
* **Summary**
* **SigningKey**
* **Signature**

At HLD level:

* `Session` has many `Participants`, `Recordings`, and 0..1 `Summary`
* `Summary` has 0..1 associated `Signature`
* `Signature` references `SigningKey` (for public key details)

---

## 6. High-Level Flows

### 6.1 Start Session Flow

1. Host app calls `POST /v1/sessions`
2. AccuBrief creates session + participants in DB
3. Returns `sessionId` + widget URLs (host/client)
4. Host app renders host widget link, optionally sends client link

### 6.2 Call & Recording Flow

1. Users open widget URLs → React app loads
2. Widget connects to signaling WebSocket & sets up WebRTC
3. When recording should start:

   * Either:

     * Client-side recording using `MediaRecorder`
     * OR backend triggers media server recording (future)
4. After call ends, recording is uploaded to backend and stored

### 6.3 AI Summary Flow

1. Worker is triggered after recording upload or session end
2. Worker:

   * Downloads recording
   * Extracts audio
   * Runs STT → transcript
   * Runs diarization → who said what
   * Sends processed transcript to LLM for structured summary
   * Saves summary JSON and generates PDF
   * Calls digital signature module
   * Marks summary as `signed`
3. Webhook `summary.ready` is sent

### 6.4 Signature Verification Flow

1. External system calls `/v1/summaries/{summaryId}` (gets `signatureMeta`)
2. Or `/v1/signatures/verify` with document + signature
3. Digital signature module:

   * Recomputes hash
   * Loads public key
   * Verifies RSA signature
4. Returns `isValid`, `reason`, `documentHash`, etc.

---

# Part 2 – Low-Level Design (LLD)

Now we go module by module, down to classes, methods, table schema, and core algorithms.

---

## 1. Backend LLD (FastAPI)

### 1.1 Package Structure

```text
backend/app
├── main.py
├── core/
├── api/v1/
├── services/
├── crypto/
├── models/
├── schemas/
├── workers/
└── utils/
```

---

### 1.2 Core

#### 1.2.1 `core/config.py`

* **Class:** `Settings(BaseSettings)`

  * `ENV: str`
  * `DATABASE_URL: str`
  * `S3_ENDPOINT: str`
  * `S3_BUCKET_RECORDINGS: str`
  * `S3_BUCKET_SUMMARIES: str`
  * `TURN_URL: str`
  * `LLM_ENDPOINT: str`
  * `STT_ENDPOINT: str`
  * `ACCUBRIEF_MAIN_KEY_ID: str`
  * etc.

* **Function:** `get_settings()` – returns singleton config

#### 1.2.2 `core/security.py`

* **Function:** `authenticate_api_key(api_key: str) -> Tenant`

* **Function:** `create_join_token(session_id: str, role: str, tenant_id: str) -> str`

  * JWT with:

    * `sub: sessionId`
    * `role: host/client`
    * `tenantId`
    * `exp`

* **Function:** `decode_join_token(token: str) -> JoinTokenPayload`

---

### 1.3 Models (ORM – SQLAlchemy)

#### 1.3.1 `Session` (session_model.py)

Fields:

* `id: UUID / string (sess_xxx)`
* `tenant_id: FK Tenant`
* `status: Enum('scheduled','active','ended','processing','completed','failed')`
* `created_at: datetime`
* `started_at: datetime | null`
* `ended_at: datetime | null`
* `auto_start_recording: bool`
* `webhook_url: str | null`

#### 1.3.2 `Participant` (participant_model.py)

Fields:

* `id`
* `session_id: FK Session`
* `external_user_id: str | null`
* `name: str`
* `role: Enum('host','client')`

#### 1.3.3 `Recording` (recording_model.py)

Fields:

* `id`
* `session_id: FK Session`
* `file_path: str` (S3 path)
* `duration_seconds: int | null`
* `mime_type: str`
* `created_at: datetime`
* `status: Enum('uploaded','processed','failed')`

#### 1.3.4 `Summary` (summary_model.py)

Fields:

* `id (sum_xxx)`
* `session_id: FK Session`
* `json_data: JSONB`
* `pdf_path: str` (S3)
* `generated_at: datetime`
* `signed: bool`
* `signature_id: FK Signature | null`
* `status: Enum('pending','processing','ready','failed')`

#### 1.3.5 `SigningKey` (signing_key_model.py)

Fields:

* `id` (publicKeyId)
* `public_key_pem: text`
* `algorithm: str` (e.g., RS256)
* `created_at: datetime`
* `expires_at: datetime | null`
* `is_active: bool`

#### 1.3.6 `Signature` (signature_model.py)

Fields:

* `id` (sig_xxx)
* `summary_id: FK Summary`
* `public_key_id: FK SigningKey`
* `document_hash: str`
* `signature_value: text` (base64)
* `created_at: datetime`
* `algorithm: str`

---

### 1.4 Schemas (Pydantic)

#### 1.4.1 `schemas/session.py`

* `CreateSessionRequest`

  * `host: ParticipantInfo`
  * `client: ParticipantInfo`
  * `webhookUrl: str | None`
* `CreateSessionResponse`

  * `sessionId: str`
  * `widgetUrls: { host: str, client: str }`
* `SessionDetailsResponse`

  * `sessionId, status, createdAt, startedAt, endedAt, ...`

#### 1.4.2 `schemas/summary.py`

* `SummarySections`

  * `conversationOverview: str`
  * `participants: List`
  * `questionsAndAnswers: List`
  * `decisions: List`
  * `actionItems: List`

* `SummaryResponse`

  * `summaryId`
  * `sessionId`
  * `generatedAt`
  * `language`
  * `style`
  * `signed`
  * `signatureAlgorithm`
  * `sections: SummarySections`
  * `signatureMeta: SignatureMetaSchema | None`

#### 1.4.3 `schemas/signature.py`

* `SignatureMetaSchema`

  * `signatureId`
  * `signatureValue`
  * `documentHash`
  * `publicKeyId`
  * `createdAt`
  * `signatureAlgorithm`

* `VerifyBySummaryIdRequest`

  * `summaryId: str`

* `VerifyByDocumentRequest`

  * `document: str (base64)`
  * `signatureValue: str`
  * `publicKeyId: str`

* `VerifySignatureResponse`

  * `isValid: bool`
  * `reason: str | None`
  * `summaryId: str | None`
  * etc.

---

### 1.5 Services LLD

#### 1.5.1 `SessionService` (session_service.py)

**Class:** `SessionService`

* `create_session(tenant: Tenant, request: CreateSessionRequest) -> CreateSessionResponse`

  * Insert `Session`
  * Insert `Participants`
  * Generate join tokens
  * Build widget URLs

* `get_session(session_id: str, tenant: Tenant) -> SessionDetailsDto`

* `end_session(session_id: str, tenant: Tenant)`

  * Set `status = 'ended'`
  * Optionally enqueue summary job

#### 1.5.2 `RecordingService` (recording_service.py)

* `create_recording(session_id, upload_metadata) -> Recording`
* `update_recording_status(recording_id, status)`
* `get_recordings_for_session(session_id) -> List[Recording]`

For upload:

* Provide pre-signed URL or accept multipart upload directly.

#### 1.5.3 `SummaryPipelineService` (summary_pipeline_service.py)

**Core method:**

```python
def run_pipeline_for_session(session_id: str) -> None:
    recording = select_best_recording(session_id)
    audio_path = audio_utils.extract_audio(recording.file_path)
    transcript = transcription_service.transcribe(audio_path)
    diarized = diarization_service.diarize(transcript)
    summary_json = llm_summary_service.create_summary(diarized)
    summary_record = save_summary_json(session_id, summary_json)
    pdf_path = pdf_utils.generate_pdf(summary_json)
    attach_pdf_to_summary(summary_record, pdf_path)
    sig_meta = signing_service.sign_summary(summary_record.id, summary_json)
    mark_summary_signed(summary_record, sig_meta)
    webhook_dispatcher.send_summary_ready(session_id, summary_record.id)
```

#### 1.5.4 `TranscriptionService` (transcription_service.py)

* `transcribe(audio_path: str) -> Transcript`

  * Handles API call / local model run
  * Returns structure:

    * list of segments with timestamps

#### 1.5.5 `DiarizationService` (diarization_service.py)

* `diarize(transcript: Transcript) -> DiarizedTranscript`

  * Map segments to speakers
  * Output consistent `speakerId`

#### 1.5.6 `LLMSummaryService` (llm_summary_service.py)

* `create_summary(diarized: DiarizedTranscript) -> Dict`

  * Builds prompt
  * Calls LLM
  * Validates JSON structure
  * Normalizes to `SummarySections` shape

#### 1.5.7 `WebhookDispatcher` (webhook_dispatcher.py)

* `send_event(tenant: Tenant, event_type: str, payload: dict)`

  * HMAC sign payload
  * POST to tenant webhook URL
  * Retry with backoff

---

### 1.6 Crypto LLD

#### 1.6.1 `KMSService` (kms_service.py)

* `get_active_signing_key(tenant_id: str | None) -> SigningKey`
* `get_public_key_by_id(public_key_id: str) -> bytes`

`SigningKey` dataclass:

* `public_key_id: str`
* `private_key: RSAPrivateKey`
* `public_key_pem: bytes`
* `algorithm: str`

#### 1.6.2 `SigningService` (signing_service.py)

* `sign_summary_json(tenant_id: str, summary_id: str, summary_data: dict) -> SignatureMeta`

  * `canonical_bytes = canonical_json_bytes(summary_data)`
  * `document_hash = compute_sha256_hash(canonical_bytes)`
  * `signature = rsa_sign(private_key, canonical_bytes)`
  * `signature_b64 = base64.b64encode(signature).decode()`
  * Save to `Signature` table

#### 1.6.3 `VerificationService` (verification_service.py)

* `verify_json_with_meta(data: dict, signature_value_b64: str, document_hash_expected: str, public_key_id: str, algorithm: str='RS256') -> VerificationResult`

  * Recompute hash
  * Compare with expected
  * Load public key
  * Verify signature
  * Return detailed result

---

### 1.7 API Layer LLD

Example: `api/v1/summaries.py`

* `@router.get("/{summary_id}")`

  * Loads `Summary` from DB
  * Loads `Signature` & `SigningKey`
  * Maps to `SummaryResponse`

Example: `api/v1/signatures.py`

* `@router.post("/verify")`

  * Branch:

    * `VerifyBySummaryIdRequest` → lookup summary + signature
    * `VerifyByDocumentRequest` → direct verification
  * Call `VerificationService`
  * Return `VerifySignatureResponse`

---

## 2. Frontend LLD (React Widget)

### 2.1 Entry & Routing

* `src/index.tsx`:

  * Render `<App />` into root
* `App.tsx`:

  * Parse `sessionId`, `role`, `token` from URL
  * Render `<WidgetPage />`

### 2.2 `Widget.tsx` (pages/Widget.tsx)

Responsibilities:

* Call backend `/v1/sessions/{sessionId}` with `Authorization: Bearer <token>` or special header
* Initialize:

  * `useSession(sessionId, token)`
  * `useSignaling(sessionId, token)`
  * `useWebRTC(signalingConnection)`
* Render:

  * `<VideoTile>` for local/remote
  * `<ControlsBar>` with buttons
  * `<RecordingIndicator>` when active

Props/State:

* `sessionState: { status, participants }`
* `webrtcState: { localStream, remoteStream, connectionStatus }`
* `recordingState: { isRecording, error? }`

### 2.3 `useSignaling.ts`

* `useEffect`:

  * Connect to `wss://api.accubrief.com/v1/signaling/{sessionId}?token=...`
  * Listen for messages:

    * `offer`, `answer`, `ice-candidate`, `peer-joined`, `peer-left`
  * Expose:

    * `sendOffer(sdp)`
    * `sendAnswer(sdp)`
    * `sendIceCandidate(candidate)`

### 2.4 `useWebRTC.ts`

* Creates RTCPeerConnection
* Hooks into signaling events:

  * On `offer` → setRemoteDescription + createAnswer
  * On `answer` → setRemoteDescription
  * On `ice-candidate` → addIceCandidate
* Attach local media tracks
* Expose:

  * `localStream`
  * `remoteStream`
  * `startCall()`, `endCall()`

### 2.5 Recording LLD

Option (MVP): **Client-side MediaRecorder**

* When “Start Recording” clicked:

  * Create `MediaRecorder(localStream or mixedStream)`
  * On `dataavailable` push chunks
* On “Stop Recording”:

  * Create Blob from chunks
  * Upload via `api.uploadRecording(sessionId, blob)`

Server returns `recordingId`, backend triggers pipeline.

---

## 3. Worker / Pipeline LLD

### 3.1 Queue Pattern

* Redis-backed queue (e.g., RQ/Celery)
* Job type: `summary_pipeline_job`
* Payload: `{ "sessionId": "...", "recordingId": "..." }`

### 3.2 Worker `summary_worker.py`

Pseudocode:

```python
def handle_summary_job(session_id, recording_id):
    recording = RecordingService.get(recording_id)
    file_path = storage.download(recording.file_path)
    audio_path = audio_utils.extract_audio(file_path)
    transcript = transcription_service.transcribe(audio_path)
    diarized = diarization_service.diarize(transcript)
    summary_json = llm_summary_service.create_summary(diarized)
    summary_record = SummaryService.save_json(session_id, summary_json)
    pdf_path = pdf_utils.generate_pdf(summary_json)
    SummaryService.attach_pdf(summary_record.id, pdf_path)
    sig_meta = signing_service.sign_summary_json(
        tenant_id=summary_record.tenant_id,
        summary_id=summary_record.id,
        summary_data=summary_json
    )
    SummaryService.attach_signature(summary_record.id, sig_meta)
    webhook_dispatcher.send_summary_ready(session_id, summary_record.id)
```

---

## 4. Security / Error Handling LLD

### 4.1 Auth

* API key for server-to-server calls:

  * Validate in `Depends(get_current_tenant)`
* Join token for widget:

  * Validate for:

    * `sessionId` match
    * `role` match
    * `tenantId` correctness
    * expiry

### 4.2 Common Error Responses

* `401 Unauthorized` – invalid API key / token
* `403 Forbidden` – tenant mismatch
* `404 Not Found` – session/summary/recording not found
* `422 Unprocessable` – invalid payload
* `500 Internal Server Error` – unexpected errors

### 4.3 Logging

* Log fields:

  * `tenantId`
  * `sessionId`
  * `summaryId`
  * event type (pipeline_step, webhook_send, sign_doc)
* No raw transcript or PII in logs.

