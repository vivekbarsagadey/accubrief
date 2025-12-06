# PRD: AccuBrief

## 1. Product overview

### 1.1 Document title and version

- **PRD**: AccuBrief - AI-Powered Video Communication & Documentation Platform
- **Type**: Project-level
- **Version**: 1.0
- **Date**: 2025-12-07

### 1.2 Product summary

AccuBrief is a pluggable service that provides any platform with secure video calls, automatic recording, AI-powered summaries, and digitally signed documents. The system is designed as a standalone component that integrates seamlessly with existing applications through REST APIs, webhooks, and an embeddable widget.

The platform addresses the critical need for documented conversations with verifiable authenticity in professional settings. Whether it's legal consultations, medical appointments, or professional meetings, AccuBrief ensures that every conversation is recorded, transcribed, summarized, and signed with a tamper-proof digital signature that provides legal non-repudiation.

AccuBrief operates as a loosely coupled service, requiring no internal database access from the host application. Integration is straightforward: the host system creates sessions via API, embeds the widget, and receives webhooks when summaries are ready.

## 2. Goals

### 2.1 Business goals

- Provide a turnkey solution for documented video conversations
- Enable legal non-repudiation through digital signatures
- Reduce manual documentation effort by 90% through AI summarization
- Create a scalable SaaS offering for professional service industries
- Generate revenue through API usage-based pricing model
- Establish AccuBrief as the standard for verifiable conversation documentation

### 2.2 User goals

- Conduct secure video calls without complex setup
- Automatically receive professional summaries of conversations
- Have tamper-proof evidence of what was discussed and agreed
- Integrate easily with existing CRM/case management systems
- Access recordings and summaries at any time
- Verify document authenticity through public APIs

### 2.3 Non-goals

- AccuBrief is NOT a CRM or case management tool
- AccuBrief is NOT a workflow automation system
- AccuBrief does NOT provide user management for host applications
- AccuBrief does NOT support group calls (1:1 only in v1.0)
- AccuBrief does NOT provide real-time transcription (post-call only in v1.0)
- AccuBrief does NOT integrate with third-party signature providers

## 3. User personas

### 3.1 Key user types

- Host Users (professionals conducting sessions)
- Client Users (customers/clients joining sessions)
- Integrator Developers (building integrations with AccuBrief)
- System Administrators (managing and monitoring the system)

### 3.2 Basic persona details

- **Legal Professional (Host User)**: Attorney conducting client consultations who needs documented evidence of advice given and client acknowledgments
- **Healthcare Provider (Host User)**: Doctor conducting telehealth appointments requiring documented consent and treatment discussions
- **Financial Advisor (Host User)**: Consultant discussing investment strategies who needs proof of disclosures and client understanding
- **End Client (Client User)**: Consumer participating in professional consultations who wants records of what was discussed
- **Integration Developer**: Software engineer at a CRM company integrating AccuBrief into their platform
- **Platform Administrator**: DevOps/IT professional managing AccuBrief deployment and monitoring

### 3.3 Role-based access

- **Host Role**: Can create sessions, start/stop recording, end sessions, access all recordings and summaries for their tenant
- **Client Role**: Can join sessions via provided link, participate in calls, receives summary copies
- **API Consumer**: Server-to-server access with API key, full CRUD operations on sessions/summaries
- **Widget User**: Limited access via JWT token, scoped to specific session and role

## 4. Functional requirements

### 4.1 Session management (Priority: High)

- Create video sessions with host and client participant information
- Generate secure, time-limited widget URLs for each participant
- Support session lifecycle: scheduled → active → ended → processing → completed
- Allow session termination by host
- Auto-trigger summary pipeline on session end

### 4.2 WebRTC communication (Priority: High)

- Provide embeddable React widget for video calls
- Handle WebRTC signaling via WebSocket connections
- Support SDP offer/answer exchange for peer connection
- Relay ICE candidates for NAT traversal
- Integrate with TURN/STUN servers for firewall compatibility
- Enable camera/microphone controls (mute, toggle)

### 4.3 Recording management (Priority: High)

- Client-side recording using MediaRecorder API
- Automatic upload of recordings to secure object storage
- Support WebM/MP4 formats with H.264/VP8 encoding
- Maintain recording metadata (duration, size, format)
- Link recordings to sessions

### 4.4 AI summary pipeline (Priority: High)

- Extract audio from video recordings
- Transcribe audio using Speech-to-Text (Whisper/Deepgram)
- Perform speaker diarization to identify who said what
- Generate structured summaries using LLM
- Produce JSON summary with sections: overview, Q&A, decisions, action items
- Generate professional PDF documents

### 4.5 Digital signature system (Priority: High)

- In-house RSA-based signing (no third-party dependencies)
- SHA-256 document hashing with JSON canonicalization
- Sign summary JSON documents
- Support key rotation with multiple active keys
- Provide public verification API
- Store signature metadata with summaries

### 4.6 APIs and integration (Priority: High)

- RESTful API with versioning (/v1/...)
- API key authentication for server-to-server calls
- JWT tokens for widget authentication
- Webhook notifications for async events
- HMAC-signed webhook payloads for security
- Comprehensive error responses with proper HTTP codes

### 4.7 Multi-tenancy (Priority: High)

- Tenant isolation via tenant_id on all data
- API key tied to tenant identification
- Scoped data access per tenant
- Separate webhook URLs per tenant

## 5. User experience

### 5.1 Entry points and first-time user flow

- Host application creates session via POST /v1/sessions
- Host receives widget URLs for host and client roles
- Host user opens their widget URL in browser/iframe
- Client receives invitation link (via host app's preferred channel)
- Client opens widget URL and joins the call
- Widget requests camera/microphone permissions
- Connection established, recording starts automatically (if configured)

### 5.2 Core experience

- **Session Start**: Host clicks "Start Call" in widget, client joins via link, WebRTC connection established within 2 seconds
- **During Call**: Clean video tiles, visible controls, recording indicator, stable connection with fallback to TURN
- **Session End**: Host clicks "End Call", recording stops, upload completes, processing begins
- **Summary Delivery**: Webhook notifies host app within 60 seconds, summary available via API
- **Verification**: Any party can verify signature authenticity via public API

### 5.3 Advanced features and edge cases

- Handle network interruptions with reconnection logic
- Graceful degradation if camera unavailable (audio-only mode)
- Invalid/expired token shows clear error screen
- Recording upload retry on network failure
- Pipeline failure triggers summary.failed webhook with reason
- Support for long recordings (> 1 hour)

### 5.4 UI/UX highlights

- Minimal, professional widget design
- Prominent recording indicator (red dot)
- Clear control buttons for mute/unmute, camera toggle, end call
- Loading states during connection
- Error screens with actionable messages
- Responsive design for various embed sizes

## 6. Narrative

A legal advisor receives a new client through their CRM. The CRM, integrated with AccuBrief, automatically creates a session and displays the "Start Consultation" button. The advisor clicks it, opening the AccuBrief widget in a clean overlay. The client receives an SMS with their join link and enters the video call from their phone.

During the 30-minute consultation, the advisor explains legal options while the client asks questions. The entire conversation is being recorded seamlessly. When the call ends, both participants see a "Processing your summary" message.

Within a minute, the CRM receives a webhook notification. The AI has transcribed the conversation, identified each speaker, and produced a structured summary with key topics discussed, questions asked, advice given, and agreed next steps. The summary is digitally signed with AccuBrief's RSA key.

The advisor reviews the summary in their CRM, makes any notes, and shares it with the client. Six months later, when there's a dispute about what was discussed, both parties can verify the document's authenticity through the public verification API, proving it hasn't been tampered with since creation.

## 7. Success metrics

### 7.1 User-centric metrics

- Widget load time < 1 second
- WebRTC connection success rate > 98%
- Call quality rating > 4/5 stars
- Summary accuracy satisfaction > 90%
- User task completion rate > 95%

### 7.2 Business metrics

- Customer activation rate > 80%
- Monthly active sessions growth > 20% MoM
- Churn rate < 5%
- Net Promoter Score > 50
- Average sessions per customer > 10/month

### 7.3 Technical metrics

- API response time < 200ms (p95)
- Summary generation time < 60 seconds (average)
- System uptime > 99.9%
- Recording upload success rate > 99%
- Signature verification accuracy: 100%

## 8. Technical considerations

### 8.1 Integration points

- REST API for session/summary management
- WebSocket for real-time signaling
- Webhook callbacks for async events
- iframe/webview embedding for widget
- S3-compatible storage for recordings/PDFs
- LLM provider APIs (OpenAI/Ollama)
- STT provider APIs (Whisper/Deepgram)

### 8.2 Data storage and privacy

- PostgreSQL for metadata (sessions, summaries, signatures)
- S3/MinIO for recordings and PDF documents
- Encryption at rest for all sensitive data
- Private keys stored in secure environment variables or KMS
- GDPR-compliant data handling
- Configurable data retention policies
- Soft delete for audit trail preservation

### 8.3 Scalability and performance

- Stateless FastAPI backend for horizontal scaling
- Queue-based async pipeline with Redis
- Horizontally scalable AI workers
- CDN for widget static assets
- Database connection pooling
- Caching for frequently accessed data

### 8.4 Potential challenges

- WebRTC NAT traversal in restricted networks
- Large recording uploads on slow connections
- LLM API rate limits and costs
- Ensuring accurate speaker diarization
- Key management for signature system
- Handling concurrent session limits

## 9. Milestones and sequencing

### 9.1 Project estimate

- **Size**: Large
- **Time Estimate**: 12-16 weeks

### 9.2 Team size and composition

- **Recommended Team Size**: 5-7 members
- **Roles**: 2 Backend Engineers, 1 Frontend Engineer, 1 DevOps Engineer, 1 ML/AI Engineer, 1 QA Engineer, 1 Product Manager

### 9.3 Suggested phases

- **Phase 1: Foundation** (Weeks 1-4)
  - Core FastAPI backend with session management
  - PostgreSQL database setup with all models
  - Basic API authentication (API keys)
  - Project infrastructure (Docker, CI/CD)

- **Phase 2: Communication Layer** (Weeks 5-8)
  - React widget with WebRTC integration
  - WebSocket signaling server
  - TURN/STUN configuration
  - Client-side recording with upload

- **Phase 3: AI Pipeline** (Weeks 9-12)
  - Speech-to-text integration
  - Speaker diarization pipeline
  - LLM summarization service
  - PDF generation

- **Phase 4: Signature & Polish** (Weeks 13-16)
  - Digital signature module
  - Verification API
  - Webhook system
  - Testing and security audit
  - Documentation and deployment

## 10. User stories

### 10.1 Session creation

- **ID**: PROJ-001
- **Description**: As a host application, I want to create a video session via API so that I can enable my users to have documented conversations.
- **Acceptance criteria**:
  - POST /v1/sessions accepts host and client participant information
  - Response includes sessionId and widget URLs for both roles
  - Session is created with status "scheduled"
  - API key authentication is required
  - Response time < 200ms

### 10.2 Widget initialization

- **ID**: PROJ-002
- **Description**: As a participant, I want to open the widget URL and have my video call ready so that I can start communicating quickly.
- **Acceptance criteria**:
  - Widget loads within 1 second
  - Camera/microphone permissions are requested
  - Token validation occurs before rendering
  - Invalid tokens show clear error message
  - Loading state is visible during initialization

### 10.3 WebRTC connection

- **ID**: PROJ-003
- **Description**: As a participant, I want to establish a peer-to-peer video connection so that I can see and hear the other party clearly.
- **Acceptance criteria**:
  - WebRTC connection established within 2 seconds
  - Fallback to TURN server when P2P fails
  - Video and audio streams render correctly
  - ICE candidate exchange completes successfully
  - Connection status is visible to user

### 10.4 Call controls

- **ID**: PROJ-004
- **Description**: As a participant, I want to control my audio and video during the call so that I can manage my privacy and participation.
- **Acceptance criteria**:
  - Mute/unmute button toggles microphone
  - Camera toggle turns video on/off
  - Control states are visually indicated
  - Other participant sees muted/video-off status
  - Controls are accessible during entire call

### 10.5 Session recording

- **ID**: PROJ-005
- **Description**: As the system, I want to record the session automatically so that it can be transcribed and summarized.
- **Acceptance criteria**:
  - Recording starts automatically (if configured)
  - Recording indicator visible to both participants
  - MediaRecorder captures combined audio/video stream
  - Recording is stored as WebM or MP4
  - Recording metadata is saved to database

### 10.6 Session termination

- **ID**: PROJ-006
- **Description**: As a host, I want to end the session so that recording stops and summary processing begins.
- **Acceptance criteria**:
  - End call button terminates WebRTC connection
  - Recording is finalized and uploaded
  - Session status changes to "ended"
  - Summary pipeline is triggered automatically
  - Both participants see "call ended" message

### 10.7 Recording upload

- **ID**: PROJ-007
- **Description**: As the widget, I want to upload the recording to secure storage so that it can be processed.
- **Acceptance criteria**:
  - Recording blob is uploaded to S3/MinIO
  - Upload progress is shown (for large files)
  - Retry logic handles network failures
  - Recording record is created in database
  - Upload completes before session cleanup

### 10.8 Audio transcription

- **ID**: PROJ-008
- **Description**: As the system, I want to transcribe the audio from the recording so that it can be analyzed.
- **Acceptance criteria**:
  - Audio is extracted from video recording
  - STT service produces text transcript
  - Timestamps are preserved for each segment
  - Transcription handles multiple languages
  - Errors are logged and reported

### 10.9 Speaker diarization

- **ID**: PROJ-009
- **Description**: As the system, I want to identify different speakers in the transcript so that the summary accurately attributes statements.
- **Acceptance criteria**:
  - Each transcript segment is assigned a speaker ID
  - Speakers are labeled consistently (Speaker 1, Speaker 2)
  - Diarization aligns with transcript timestamps
  - Output includes speaker-labeled segments
  - Host and client can be identified by role

### 10.10 AI summarization

- **ID**: PROJ-010
- **Description**: As the system, I want to generate a structured summary using AI so that users receive organized documentation.
- **Acceptance criteria**:
  - LLM receives diarized transcript as input
  - Summary includes: overview, participants, Q&A, decisions, action items
  - Output is valid JSON matching defined schema
  - Summary is saved to database
  - Generation completes within 60 seconds

### 10.11 PDF generation

- **ID**: PROJ-011
- **Description**: As the system, I want to generate a professional PDF document so that users have a downloadable summary.
- **Acceptance criteria**:
  - PDF is generated from summary JSON
  - PDF includes all summary sections
  - PDF is stored in object storage
  - PDF path is linked to summary record
  - PDF is accessible via download endpoint

### 10.12 Digital signing

- **ID**: PROJ-012
- **Description**: As the system, I want to digitally sign the summary so that its authenticity can be verified later.
- **Acceptance criteria**:
  - Summary JSON is canonicalized (sorted keys, no whitespace)
  - SHA-256 hash is computed
  - RSA signature is created using private key
  - Signature metadata is stored with summary
  - Summary is marked as "signed"

### 10.13 Summary retrieval

- **ID**: PROJ-013
- **Description**: As a host application, I want to retrieve summaries via API so that I can display them to users.
- **Acceptance criteria**:
  - GET /v1/summaries/{summaryId} returns full summary
  - Response includes signature metadata
  - Tenant isolation is enforced
  - 404 returned for non-existent summaries
  - Response format matches documented schema

### 10.14 PDF download

- **ID**: PROJ-014
- **Description**: As a user, I want to download the PDF summary so that I have an offline copy.
- **Acceptance criteria**:
  - GET /v1/summaries/{summaryId}/pdf returns PDF file
  - Correct Content-Type header is set
  - File downloads with appropriate filename
  - Authorization is validated
  - 404 returned if PDF not yet generated

### 10.15 Signature verification by summary ID

- **ID**: PROJ-015
- **Description**: As a third party, I want to verify a summary's signature by its ID so that I can trust its authenticity.
- **Acceptance criteria**:
  - POST /v1/signatures/verify accepts summaryId
  - Response includes isValid boolean
  - Valid signatures return verification details
  - Invalid signatures include reason for failure
  - Response includes document hash and timestamp

### 10.16 Signature verification by document

- **ID**: PROJ-016
- **Description**: As a third party, I want to verify a signature using the document itself so that I can verify offline copies.
- **Acceptance criteria**:
  - POST /v1/signatures/verify accepts document + signature
  - Document can be provided as base64-encoded JSON
  - Public key is looked up by ID
  - Hash is recomputed and compared
  - Detailed verification result is returned

### 10.17 Webhook notification

- **ID**: PROJ-017
- **Description**: As a host application, I want to receive webhook notifications so that I'm informed when summaries are ready.
- **Acceptance criteria**:
  - summary.ready webhook sent when summary is complete
  - summary.failed webhook sent on pipeline failure
  - Webhook includes sessionId and summaryId
  - Payload is HMAC-signed for verification
  - Retry logic with exponential backoff

### 10.18 Session status retrieval

- **ID**: PROJ-018
- **Description**: As a host application, I want to check session status so that I can track progress.
- **Acceptance criteria**:
  - GET /v1/sessions/{sessionId} returns current status
  - Status reflects lifecycle: scheduled → active → ended → processing → completed
  - Response includes timestamps for state transitions
  - Participant information is included
  - 404 returned for non-existent sessions

### 10.19 API key authentication

- **ID**: PROJ-019
- **Description**: As the system, I want to authenticate API requests using API keys so that only authorized tenants can access resources.
- **Acceptance criteria**:
  - X-API-Key header is required for all API calls
  - Invalid keys return 401 Unauthorized
  - Tenant is identified from API key
  - All queries are filtered by tenant_id
  - Rate limiting is applied per API key

### 10.20 Widget token authentication

- **ID**: PROJ-020
- **Description**: As the system, I want to authenticate widget users using JWT tokens so that only invited participants can join.
- **Acceptance criteria**:
  - JWT token includes sessionId, role, and tenantId
  - Tokens expire within 15 minutes
  - Invalid tokens are rejected at widget load
  - Token validation occurs before WebSocket connection
  - Expired tokens show appropriate error message

### 10.21 Error handling

- **ID**: PROJ-021
- **Description**: As a developer, I want clear error responses so that I can handle failures appropriately.
- **Acceptance criteria**:
  - 401 for authentication failures
  - 403 for authorization failures (tenant mismatch)
  - 404 for resource not found
  - 422 for validation errors
  - 500 for unexpected server errors
  - Error responses include message and code

### 10.22 Health check endpoint

- **ID**: PROJ-022
- **Description**: As an operator, I want a health check endpoint so that I can monitor system availability.
- **Acceptance criteria**:
  - GET /health returns system status
  - Response includes database connectivity status
  - Response includes storage connectivity status
  - Response includes worker queue status
  - Returns 503 if any component is unhealthy

### 10.23 Multi-tenant data isolation

- **ID**: PROJ-023
- **Description**: As a tenant, I want my data to be isolated from other tenants so that my information is secure.
- **Acceptance criteria**:
  - Every database query filters by tenant_id
  - Sessions are only visible to owning tenant
  - Summaries are only visible to owning tenant
  - Recordings are only accessible to owning tenant
  - Cross-tenant access attempts return 404

### 10.24 Key rotation support

- **ID**: PROJ-024
- **Description**: As an operator, I want to rotate signing keys so that security is maintained over time.
- **Acceptance criteria**:
  - New key pair can be generated and activated
  - Old keys remain valid for verification
  - New signatures use latest active key
  - Public key ID is included in signature metadata
  - Verification looks up key by ID

### 10.25 Soft delete for audit trail

- **ID**: PROJ-025
- **Description**: As the system, I want to soft delete records so that audit trails are preserved.
- **Acceptance criteria**:
  - Delete operations set deleted_at timestamp
  - Deleted records are excluded from queries
  - deleted_by captures who performed deletion
  - Records can be recovered if needed
  - Audit fields are maintained on all models
