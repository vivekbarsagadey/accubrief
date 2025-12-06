# Sequence Diagrams - AccuBrief

## Overview

This document contains sequence diagrams for all major flows in AccuBrief. Each diagram shows the interactions between components with timing and message flow.

## 1. Session Creation Flow

```
┌────────────┐    ┌─────────────┐    ┌────────────┐    ┌────────────┐
│  Host App  │    │ AccuBrief   │    │ PostgreSQL │    │   Redis    │
│  (Client)  │    │    API      │    │     DB     │    │   Queue    │
└─────┬──────┘    └──────┬──────┘    └──────┬─────┘    └─────┬──────┘
      │                  │                  │                │
      │ POST /v1/sessions│                  │                │
      │ {host, client}   │                  │                │
      │─────────────────▶│                  │                │
      │                  │                  │                │
      │                  │ Validate API Key │                │
      │                  │─────────────────▶│                │
      │                  │◀─────────────────│                │
      │                  │   Tenant Info    │                │
      │                  │                  │                │
      │                  │ Generate IDs     │                │
      │                  │ (sess_, part_)   │                │
      │                  │                  │                │
      │                  │ INSERT session   │                │
      │                  │─────────────────▶│                │
      │                  │◀─────────────────│                │
      │                  │                  │                │
      │                  │ INSERT host      │                │
      │                  │ participant      │                │
      │                  │─────────────────▶│                │
      │                  │◀─────────────────│                │
      │                  │                  │                │
      │                  │ INSERT client    │                │
      │                  │ participant      │                │
      │                  │─────────────────▶│                │
      │                  │◀─────────────────│                │
      │                  │                  │                │
      │                  │ Generate JWT     │                │
      │                  │ tokens (host,    │                │
      │                  │ client)          │                │
      │                  │                  │                │
      │  201 Created     │                  │                │
      │  {sessionId,     │                  │                │
      │   widgetUrls}    │                  │                │
      │◀─────────────────│                  │                │
      │                  │                  │                │
```

---

## 2. Widget Join and WebRTC Connection Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│   Host     │    │   Widget   │    │ Signaling  │    │   Client   │    │   Widget   │
│  Browser   │    │   (Host)   │    │   Server   │    │  Browser   │    │  (Client)  │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │                 │
      │  Open Widget    │                 │                 │                 │
      │  URL            │                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Validate JWT    │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │   Token Valid   │                 │                 │
      │                 │                 │                 │                 │
      │ Request Camera/ │                 │                 │                 │
      │ Microphone      │                 │                 │                 │
      │◀────────────────│                 │                 │                 │
      │                 │                 │                 │                 │
      │ Grant Permission│                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Connect WSS     │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │  Connected      │                 │                 │
      │                 │                 │                 │                 │
      │                 │                 │                 │  Open Widget    │
      │                 │                 │                 │  URL            │
      │                 │                 │                 │────────────────▶│
      │                 │                 │                 │                 │
      │                 │                 │                 │                 │ Validate JWT
      │                 │                 │◀────────────────│◀────────────────│
      │                 │                 │                 │                 │
      │                 │                 │                 │ Grant Permissions
      │                 │                 │                 │◀────────────────│
      │                 │                 │                 │                 │
      │                 │                 │ Connect WSS     │                 │
      │                 │                 │◀────────────────│◀────────────────│
      │                 │                 │  Connected      │                 │
      │                 │                 │                 │                 │
      │                 │ peer-joined     │                 │                 │
      │                 │ {role: client}  │                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │                 │                 │                 │
      │                 │ Create          │                 │                 │
      │                 │ RTCPeerConnection                 │                 │
      │                 │                 │                 │                 │
      │                 │ Create Offer    │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │                 │ Forward Offer   │                 │
      │                 │                 │────────────────▶│────────────────▶│
      │                 │                 │                 │                 │
      │                 │                 │                 │ setRemoteDescription
      │                 │                 │                 │                 │
      │                 │                 │ Create Answer   │                 │
      │                 │                 │◀────────────────│◀────────────────│
      │                 │ Forward Answer  │                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │                 │                 │                 │
      │                 │ setRemoteDescription              │                 │
      │                 │                 │                 │                 │
      │                 │ ICE Candidates  │                 │                 │
      │                 │◀───────────────▶│◀───────────────▶│◀───────────────▶│
      │                 │   (Multiple)    │   (Relay)       │   (Multiple)    │
      │                 │                 │                 │                 │
      │                 │◀═══════════════════════════════════════════════════▶│
      │                 │           P2P Media Stream Established              │
      │                 │                 │                 │                 │
```

---

## 3. Session Recording Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│   Widget   │    │ MediaRecorder│   │ AccuBrief  │    │    S3/     │    │ PostgreSQL │
│   (Host)   │    │    API     │    │    API     │    │   MinIO    │    │     DB     │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │                 │
      │ Session Active  │                 │                 │                 │
      │                 │                 │                 │                 │
      │ Start Recording │                 │                 │                 │
      │ (auto or manual)│                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ MediaRecorder   │                 │                 │
      │                 │ start()         │                 │                 │
      │                 │                 │                 │                 │
      │ Show Recording  │                 │                 │                 │
      │ Indicator       │                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ ondataavailable │                 │                 │
      │◀────────────────│ (chunks)        │                 │                 │
      │                 │                 │                 │                 │
      │ Accumulate      │                 │                 │                 │
      │ Chunks in       │                 │                 │                 │
      │ Memory          │                 │                 │                 │
      │                 │                 │                 │                 │
      │    ... Call Duration ...          │                 │                 │
      │                 │                 │                 │                 │
      │ End Call Button │                 │                 │                 │
      │ Clicked         │                 │                 │                 │
      │                 │                 │                 │                 │
      │ Stop Recording  │                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │ stop()          │                 │                 │
      │                 │                 │                 │                 │
      │ Final Blob      │                 │                 │                 │
      │◀────────────────│                 │                 │                 │
      │                 │                 │                 │                 │
      │ POST /v1/recordings/upload        │                 │                 │
      │ (multipart/form-data)             │                 │                 │
      │──────────────────────────────────▶│                 │                 │
      │                 │                 │                 │                 │
      │                 │                 │ Generate rec_id │                 │
      │                 │                 │                 │                 │
      │                 │                 │ PUT object      │                 │
      │                 │                 │────────────────▶│                 │
      │                 │                 │◀────────────────│                 │
      │                 │                 │  Upload OK      │                 │
      │                 │                 │                 │                 │
      │                 │                 │ INSERT recording│                 │
      │                 │                 │─────────────────│────────────────▶│
      │                 │                 │◀────────────────│◀────────────────│
      │                 │                 │                 │                 │
      │ 201 Created     │                 │                 │                 │
      │ {recordingId}   │                 │                 │                 │
      │◀──────────────────────────────────│                 │                 │
      │                 │                 │                 │                 │
```

---

## 4. AI Summary Pipeline Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│   Redis    │    │  Pipeline  │    │    STT     │    │ Diarization│    │    LLM     │    │  Signing   │
│   Queue    │    │   Worker   │    │  Service   │    │  Service   │    │  Service   │    │  Service   │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │                 │                 │
      │ Job: session_id │                 │                 │                 │                 │
      │────────────────▶│                 │                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Download        │                 │                 │                 │
      │                 │ Recording       │                 │                 │                 │
      │                 │ from S3         │                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Extract Audio   │                 │                 │                 │
      │                 │ (ffmpeg)        │                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Transcribe      │                 │                 │                 │
      │                 │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │                 │ Whisper/        │                 │                 │
      │                 │                 │ Deepgram        │                 │                 │
      │                 │                 │ Processing      │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Transcript      │                 │                 │                 │
      │                 │ + timestamps    │                 │                 │                 │
      │                 │◀────────────────│                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Diarize         │                 │                 │                 │
      │                 │─────────────────│────────────────▶│                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │                 │                 │ Pyannote        │                 │
      │                 │                 │                 │ Speaker ID      │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Speaker-labeled │                 │                 │                 │
      │                 │ transcript      │                 │                 │                 │
      │                 │◀────────────────│◀────────────────│                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Generate Summary│                 │                 │                 │
      │                 │─────────────────│─────────────────│────────────────▶│                 │
      │                 │                 │                 │                 │                 │
      │                 │                 │                 │                 │ OpenAI/Ollama  │
      │                 │                 │                 │                 │ LLM Call       │
      │                 │                 │                 │                 │                 │
      │                 │ Structured JSON │                 │                 │                 │
      │                 │ Summary         │                 │                 │                 │
      │                 │◀────────────────│◀────────────────│◀────────────────│                 │
      │                 │                 │                 │                 │                 │
      │                 │ Generate PDF    │                 │                 │                 │
      │                 │ (WeasyPrint)    │                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Upload PDF to S3│                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │                 │ Sign Summary    │                 │                 │                 │
      │                 │─────────────────│─────────────────│─────────────────│────────────────▶│
      │                 │                 │                 │                 │                 │
      │                 │                 │                 │                 │                 │ Canonicalize
      │                 │                 │                 │                 │                 │ SHA-256
      │                 │                 │                 │                 │                 │ RSA Sign
      │                 │                 │                 │                 │                 │
      │                 │ Signature Meta  │                 │                 │                 │
      │                 │◀────────────────│◀────────────────│◀────────────────│◀────────────────│
      │                 │                 │                 │                 │                 │
      │                 │ Save to DB      │                 │                 │                 │
      │                 │ Send Webhook    │                 │                 │                 │
      │                 │                 │                 │                 │                 │
      │ Job Complete    │                 │                 │                 │                 │
      │◀────────────────│                 │                 │                 │                 │
      │                 │                 │                 │                 │                 │
```

---

## 5. Digital Signature Verification Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  External  │    │ AccuBrief  │    │Verification│    │    KMS     │    │ PostgreSQL │
│   System   │    │    API     │    │  Service   │    │  Service   │    │     DB     │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │                 │
      │ POST /v1/signatures/verify        │                 │                 │
      │ {summaryId}     │                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Load Summary    │                 │                 │
      │                 │─────────────────│─────────────────│────────────────▶│
      │                 │◀────────────────│◀────────────────│◀────────────────│
      │                 │   Summary +     │                 │                 │
      │                 │   Signature     │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Verify          │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │                 │                 │                 │
      │                 │                 │ Canonicalize    │                 │
      │                 │                 │ JSON            │                 │
      │                 │                 │                 │                 │
      │                 │                 │ Compute         │                 │
      │                 │                 │ SHA-256 Hash    │                 │
      │                 │                 │                 │                 │
      │                 │                 │ Compare with    │                 │
      │                 │                 │ stored hash     │                 │
      │                 │                 │                 │                 │
      │                 │                 │ [Hash Match?]   │                 │
      │                 │                 │                 │                 │
      │                 │                 │ Get Public Key  │                 │
      │                 │                 │────────────────▶│                 │
      │                 │                 │◀────────────────│                 │
      │                 │                 │  Public Key     │                 │
      │                 │                 │                 │                 │
      │                 │                 │ RSA Verify      │                 │
      │                 │                 │ (signature,     │                 │
      │                 │                 │  canonical_bytes,                 │
      │                 │                 │  public_key)    │                 │
      │                 │                 │                 │                 │
      │                 │ Verification    │                 │                 │
      │                 │ Result          │                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │                 │                 │                 │
      │ 200 OK          │                 │                 │                 │
      │ {isValid: true, │                 │                 │                 │
      │  documentHash,  │                 │                 │                 │
      │  verifiedAt}    │                 │                 │                 │
      │◀────────────────│                 │                 │                 │
      │                 │                 │                 │                 │
```

---

## 6. Webhook Notification Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  Pipeline  │    │  Webhook   │    │ PostgreSQL │    │  Host App  │    │   Redis    │
│   Worker   │    │ Dispatcher │    │     DB     │    │  Webhook   │    │   Queue    │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │                 │
      │ Summary Ready   │                 │                 │                 │
      │ Send Webhook    │                 │                 │                 │
      │────────────────▶│                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Build Payload   │                 │                 │
      │                 │ {event, data}   │                 │                 │
      │                 │                 │                 │                 │
      │                 │ Compute HMAC    │                 │                 │
      │                 │ (payload,       │                 │                 │
      │                 │  webhook_secret)│                 │                 │
      │                 │                 │                 │                 │
      │                 │ INSERT delivery │                 │                 │
      │                 │ record          │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │◀────────────────│                 │                 │
      │                 │                 │                 │                 │
      │                 │ POST webhook_url│                 │                 │
      │                 │ Headers:        │                 │                 │
      │                 │  X-AccuBrief-   │                 │                 │
      │                 │  Signature      │                 │                 │
      │                 │─────────────────│────────────────▶│                 │
      │                 │                 │                 │                 │
      │                 │                 │                 │ Verify HMAC     │
      │                 │                 │                 │ Process Event   │
      │                 │                 │                 │                 │
      │                 │ HTTP 200 OK     │                 │                 │
      │                 │◀────────────────│◀────────────────│                 │
      │                 │                 │                 │                 │
      │                 │ UPDATE delivery │                 │                 │
      │                 │ status=success  │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │                 │                 │                 │


                           === FAILURE + RETRY FLOW ===

      │                 │                 │                 │                 │
      │                 │ POST webhook_url│                 │                 │
      │                 │─────────────────│────────────────▶│                 │
      │                 │                 │                 │                 │
      │                 │ HTTP 500 Error  │                 │                 │
      │                 │ (or timeout)    │                 │                 │
      │                 │◀────────────────│◀────────────────│                 │
      │                 │                 │                 │                 │
      │                 │ UPDATE delivery │                 │                 │
      │                 │ status=retrying │                 │                 │
      │                 │ attempt_count++ │                 │                 │
      │                 │────────────────▶│                 │                 │
      │                 │                 │                 │                 │
      │                 │ Schedule Retry  │                 │                 │
      │                 │─────────────────│─────────────────│────────────────▶│
      │                 │                 │                 │                 │
      │                 │                 │                 │                 │
      │                 │       ... After delay ...          │                 │
      │                 │                 │                 │                 │
      │                 │ Retry Job       │                 │                 │
      │                 │◀────────────────│◀────────────────│◀────────────────│
      │                 │                 │                 │                 │
```

---

## 7. End-to-End Session Flow

```
┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
│Host App │  │ AccuBrief│  │  Widget │  │ Widget  │  │Pipeline │  │ Signing │  │Host App │
│ Server  │  │   API   │  │  (Host) │  │ (Client)│  │ Worker  │  │ Service │  │ Webhook │
└────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ══════════════════════════ PHASE 1: SESSION SETUP ══════════════════════════│
     │            │            │            │            │            │            │
     │ POST /sessions          │            │            │            │            │
     │───────────▶│            │            │            │            │            │
     │            │            │            │            │            │            │
     │ {sessionId,│            │            │            │            │            │
     │  widgetUrls}            │            │            │            │            │
     │◀───────────│            │            │            │            │            │
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ════════════════════════ PHASE 2: CALL IN PROGRESS ═════════════════════════│
     │            │            │            │            │            │            │
     │            │  Host joins│            │            │            │            │
     │            │◀───────────│            │            │            │            │
     │            │            │            │            │            │            │
     │            │            │  Client joins           │            │            │
     │            │◀───────────│◀───────────│            │            │            │
     │            │            │            │            │            │            │
     │            │  WebRTC P2P Connection  │            │            │            │
     │            │            │◀══════════▶│            │            │            │
     │            │            │            │            │            │            │
     │            │            │  Recording │            │            │            │
     │            │            │  Started   │            │            │            │
     │            │            │            │            │            │            │
     │            │            │    ...     │            │            │            │
     │            │            │   CALL     │            │            │            │
     │            │            │ DURATION   │            │            │            │
     │            │            │    ...     │            │            │            │
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ════════════════════════ PHASE 3: SESSION END ══════════════════════════════│
     │            │            │            │            │            │            │
     │            │ End Call   │            │            │            │            │
     │            │◀───────────│            │            │            │            │
     │            │            │            │            │            │            │
     │            │ Upload     │            │            │            │            │
     │            │ Recording  │            │            │            │            │
     │            │◀───────────│            │            │            │            │
     │            │            │            │            │            │            │
     │            │ Queue Job  │            │            │            │            │
     │            │────────────│────────────│───────────▶│            │            │
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ════════════════════════ PHASE 4: AI PROCESSING ════════════════════════════│
     │            │            │            │            │            │            │
     │            │            │            │            │ STT        │            │
     │            │            │            │            │────────────│            │
     │            │            │            │            │            │            │
     │            │            │            │            │ Diarize    │            │
     │            │            │            │            │────────────│            │
     │            │            │            │            │            │            │
     │            │            │            │            │ LLM        │            │
     │            │            │            │            │────────────│            │
     │            │            │            │            │            │            │
     │            │            │            │            │ PDF        │            │
     │            │            │            │            │────────────│            │
     │            │            │            │            │            │            │
     │            │            │            │            │ Sign       │            │
     │            │            │            │            │───────────▶│            │
     │            │            │            │            │◀───────────│            │
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ════════════════════════ PHASE 5: NOTIFICATION ═════════════════════════════│
     │            │            │            │            │            │            │
     │            │            │            │            │ Webhook    │            │
     │            │            │            │            │────────────│───────────▶│
     │            │            │            │            │            │            │
     │            │            │            │            │            │         200│
     │            │            │            │            │◀───────────│◀───────────│
     │            │            │            │            │            │            │
     │            │            │            │            │            │            │
     │ ════════════════════════ PHASE 6: RETRIEVAL ════════════════════════════════│
     │            │            │            │            │            │            │
     │ GET /summaries/{id}     │            │            │            │            │
     │───────────▶│            │            │            │            │            │
     │            │            │            │            │            │            │
     │ Summary +  │            │            │            │            │            │
     │ Signature  │            │            │            │            │            │
     │◀───────────│            │            │            │            │            │
     │            │            │            │            │            │            │
```

---

## 8. Summary Retrieval Flow

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  Host App  │    │ AccuBrief  │    │ PostgreSQL │    │    S3/     │
│  (Client)  │    │    API     │    │     DB     │    │   MinIO    │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │                 │
      │ GET /v1/summaries/{id}            │                 │
      │────────────────▶│                 │                 │
      │                 │                 │                 │
      │                 │ Validate API Key│                 │
      │                 │────────────────▶│                 │
      │                 │◀────────────────│                 │
      │                 │   Tenant        │                 │
      │                 │                 │                 │
      │                 │ SELECT summary  │                 │
      │                 │ WHERE tenant_id │                 │
      │                 │────────────────▶│                 │
      │                 │◀────────────────│                 │
      │                 │                 │                 │
      │                 │ SELECT signature│                 │
      │                 │────────────────▶│                 │
      │                 │◀────────────────│                 │
      │                 │                 │                 │
      │ 200 OK          │                 │                 │
      │ {summary +      │                 │                 │
      │  signatureMeta} │                 │                 │
      │◀────────────────│                 │                 │
      │                 │                 │                 │
      │                 │                 │                 │
      │ GET /v1/summaries/{id}/pdf        │                 │
      │────────────────▶│                 │                 │
      │                 │                 │                 │
      │                 │ SELECT pdf_path │                 │
      │                 │────────────────▶│                 │
      │                 │◀────────────────│                 │
      │                 │                 │                 │
      │                 │ GET object      │                 │
      │                 │─────────────────│────────────────▶│
      │                 │◀────────────────│◀────────────────│
      │                 │   PDF bytes     │                 │
      │                 │                 │                 │
      │ 200 OK          │                 │                 │
      │ (PDF stream)    │                 │                 │
      │◀────────────────│                 │                 │
      │                 │                 │                 │
```

---

## Message Formats Summary

### WebSocket Messages

| Message Type | Direction | Payload |
|--------------|-----------|---------|
| offer | Client→Server→Client | `{sdp: string}` |
| answer | Client→Server→Client | `{sdp: string}` |
| ice-candidate | Client→Server→Client | `{candidate, sdpMid, sdpMLineIndex}` |
| peer-joined | Server→Client | `{role: string, name: string}` |
| peer-left | Server→Client | `{role: string, reason: string}` |
| error | Server→Client | `{code: string, message: string}` |

### API Request/Response Summary

| Endpoint | Method | Request | Response |
|----------|--------|---------|----------|
| /v1/sessions | POST | CreateSessionRequest | CreateSessionResponse |
| /v1/sessions/{id} | GET | - | SessionDetailsResponse |
| /v1/sessions/{id}/end | POST | - | EndSessionResponse |
| /v1/summaries/{id} | GET | - | SummaryResponse |
| /v1/summaries/{id}/pdf | GET | - | Binary PDF |
| /v1/signatures/verify | POST | VerifyRequest | VerifyResponse |
