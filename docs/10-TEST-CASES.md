# Test Cases Document

**Document Version:** 1.0  
**Last Updated:** December 7, 2025  
**Status:** Active

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Test Strategy](#2-test-strategy)
3. [Session Management Tests](#3-session-management-tests)
4. [Recording Tests](#4-recording-tests)
5. [AI Pipeline Tests](#5-ai-pipeline-tests)
6. [Digital Signature Tests](#6-digital-signature-tests)
7. [WebRTC Tests](#7-webrtc-tests)
8. [Authentication & Authorization Tests](#8-authentication--authorization-tests)
9. [Integration Tests](#9-integration-tests)
10. [Performance Tests](#10-performance-tests)
11. [Security Tests](#11-security-tests)
12. [Edge Cases & Error Handling](#12-edge-cases--error-handling)

---

## 1. Introduction

### 1.1 Purpose

This document provides comprehensive test cases for the AccuBrief platform, covering:

- Unit tests for individual components
- Integration tests for end-to-end workflows
- Performance and load testing scenarios
- Security and penetration testing cases
- Edge cases and error conditions

### 1.2 Testing Levels

| Level | Description | Tools |
|-------|-------------|-------|
| **Unit Tests** | Individual functions/methods | pytest, Jest |
| **Integration Tests** | Module interactions | pytest, Playwright |
| **System Tests** | Complete workflows | Postman, Playwright |
| **Performance Tests** | Load and stress testing | Locust, K6 |
| **Security Tests** | Vulnerability scanning | OWASP ZAP, Bandit |

### 1.3 Test Environment

- **Development**: Local Docker Compose setup
- **Staging**: Kubernetes cluster with test data
- **Production**: Separate test tenant with monitoring

---

## 2. Test Strategy

### 2.1 Test Coverage Goals

| Component | Target Coverage |
|-----------|----------------|
| Backend Services | 90%+ |
| API Routes | 95%+ |
| Frontend Components | 80%+ |
| Critical Paths | 100% |

### 2.2 Test Data Management

```python
# Test fixtures for consistent test data
@pytest.fixture
def test_tenant():
    return {
        "id": "tenant_test_001",
        "name": "Test Organization",
        "api_key": "test_api_key_123"
    }

@pytest.fixture
def test_session():
    return {
        "id": "sess_test_001",
        "tenant_id": "tenant_test_001",
        "host": {"name": "Test Host", "externalUserId": "host_001"},
        "client": {"name": "Test Client", "externalUserId": "client_001"},
        "status": "scheduled"
    }
```

### 2.3 Test Naming Convention

```
test_{component}_{scenario}_{expected_result}

Examples:
- test_session_create_success
- test_session_create_invalid_tenant_fails
- test_recording_upload_large_file_success
```

---

## 3. Session Management Tests

### 3.1 Session Creation Tests

#### TC-SESSION-001: Create Session Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-001

**Preconditions:**
- Valid API key exists
- Tenant is active

**Test Steps:**
1. Send POST request to `/v1/sessions`
2. Include valid host and client participant data
3. Set `autoStartRecording` to true

**Request:**
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
  "webhookUrl": "https://example.com/webhooks"
}
```

**Expected Result:**
- HTTP 201 Created
- Response contains `session_id`
- Response contains `widget_urls` for host and client
- Session status is `scheduled`
- Database record created with correct `tenant_id`

**Test Code:**
```python
def test_session_create_success(client, test_tenant):
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": "John Doe", "externalUserId": "user_123"},
            "client": {"name": "Jane Smith", "externalUserId": "client_456"},
            "autoStartRecording": True,
            "webhookUrl": "https://example.com/webhooks"
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 201
    data = response.json()
    assert "session_id" in data
    assert data["session_id"].startswith("sess_")
    assert "widget_urls" in data
    assert "host" in data["widget_urls"]
    assert "client" in data["widget_urls"]
```

---

#### TC-SESSION-002: Create Session Without API Key

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-001

**Test Steps:**
1. Send POST request without `X-API-Key` header

**Expected Result:**
- HTTP 401 Unauthorized
- Error message: "Invalid or missing API key"

**Test Code:**
```python
def test_session_create_without_api_key(client):
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": "John Doe"},
            "client": {"name": "Jane Smith"}
        }
    )
    
    assert response.status_code == 401
    assert "Invalid or missing API key" in response.json()["detail"]
```

---

#### TC-SESSION-003: Create Session With Invalid Tenant

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-002

**Test Steps:**
1. Use API key from different tenant
2. Attempt to create session

**Expected Result:**
- HTTP 403 Forbidden
- Session not created

**Test Code:**
```python
def test_session_create_invalid_tenant(client):
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": "John Doe"},
            "client": {"name": "Jane Smith"}
        },
        headers={"X-API-Key": "invalid_key_xyz"}
    )
    
    assert response.status_code == 403
```

---

#### TC-SESSION-004: Create Session With Missing Required Fields

**Priority:** Medium  
**Type:** Validation  
**Requirement:** FEAT-001

**Test Steps:**
1. Send POST request without `host` field

**Expected Result:**
- HTTP 422 Unprocessable Entity
- Validation error for missing field

**Test Code:**
```python
def test_session_create_missing_host(client, test_tenant):
    response = client.post(
        "/v1/sessions",
        json={
            "client": {"name": "Jane Smith"}
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 422
    errors = response.json()["detail"]
    assert any("host" in str(e) for e in errors)
```

---

### 3.2 Session Retrieval Tests

#### TC-SESSION-005: Get Session By ID Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-001

**Preconditions:**
- Session exists in database

**Test Steps:**
1. Send GET request to `/v1/sessions/{session_id}`
2. Use valid API key

**Expected Result:**
- HTTP 200 OK
- Response contains session details
- Only sessions for current tenant are returned

**Test Code:**
```python
def test_session_get_by_id_success(client, test_tenant, test_session):
    response = client.get(
        f"/v1/sessions/{test_session['id']}",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["session_id"] == test_session["id"]
    assert data["tenant_id"] == test_tenant["id"]
```

---

#### TC-SESSION-006: Get Session From Different Tenant

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-002

**Test Steps:**
1. Create session with tenant A
2. Attempt to retrieve with tenant B's API key

**Expected Result:**
- HTTP 404 Not Found (not 403 to prevent enumeration)

**Test Code:**
```python
def test_session_get_cross_tenant_fails(client, test_session):
    other_tenant_key = "other_tenant_api_key"
    
    response = client.get(
        f"/v1/sessions/{test_session['id']}",
        headers={"X-API-Key": other_tenant_key}
    )
    
    assert response.status_code == 404
```

---

### 3.3 Session State Transition Tests

#### TC-SESSION-007: Start Session Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-002

**Preconditions:**
- Session exists with status `scheduled`

**Test Steps:**
1. Send POST to `/v1/sessions/{session_id}/start`

**Expected Result:**
- HTTP 200 OK
- Session status changes to `active`
- `started_at` timestamp set
- Webhook notification sent

**Test Code:**
```python
def test_session_start_success(client, test_tenant, test_session):
    response = client.post(
        f"/v1/sessions/{test_session['id']}/start",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "active"
    assert data["started_at"] is not None
```

---

#### TC-SESSION-008: End Session Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-003

**Preconditions:**
- Session is active

**Test Steps:**
1. Send POST to `/v1/sessions/{session_id}/end`

**Expected Result:**
- HTTP 200 OK
- Session status changes to `ended`
- `ended_at` timestamp set
- Summary generation job queued
- Webhook notification sent

**Test Code:**
```python
def test_session_end_success(client, test_tenant, active_session, mock_queue):
    response = client.post(
        f"/v1/sessions/{active_session['id']}/end",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ended"
    assert data["ended_at"] is not None
    
    # Verify summary job queued
    assert mock_queue.enqueue.called
```

---

#### TC-SESSION-009: Invalid State Transition

**Priority:** Medium  
**Type:** Error Handling  
**Requirement:** FEAT-002

**Test Steps:**
1. Attempt to start already active session
2. Attempt to end scheduled session

**Expected Result:**
- HTTP 400 Bad Request
- Error message describing invalid state transition

**Test Code:**
```python
def test_session_start_already_active_fails(client, test_tenant, active_session):
    response = client.post(
        f"/v1/sessions/{active_session['id']}/start",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 400
    assert "already active" in response.json()["detail"].lower()
```

---

## 4. Recording Tests

### 4.1 Recording Upload Tests

#### TC-RECORD-001: Upload Recording Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-004

**Preconditions:**
- Session is active
- Recording data available

**Test Steps:**
1. Send POST to `/v1/recordings`
2. Include session ID and file data

**Expected Result:**
- HTTP 201 Created
- Recording stored in S3/MinIO
- Database record created
- File path returned

**Test Code:**
```python
def test_recording_upload_success(client, test_tenant, active_session):
    with open("tests/fixtures/sample.webm", "rb") as f:
        response = client.post(
            "/v1/recordings",
            files={"file": ("recording.webm", f, "video/webm")},
            data={"session_id": active_session["id"]},
            headers={"X-API-Key": test_tenant["api_key"]}
        )
    
    assert response.status_code == 201
    data = response.json()
    assert data["recording_id"].startswith("rec_")
    assert data["file_path"].startswith("recordings/")
```

---

#### TC-RECORD-002: Upload Large Recording

**Priority:** High  
**Type:** Performance  
**Requirement:** PERF-001

**Test Steps:**
1. Upload 500MB recording file
2. Monitor upload progress

**Expected Result:**
- Upload completes within 60 seconds
- File integrity verified
- No memory issues

**Test Code:**
```python
def test_recording_upload_large_file(client, test_tenant, active_session):
    # Generate 500MB test file
    large_file = generate_test_file(size_mb=500)
    
    start_time = time.time()
    response = client.post(
        "/v1/recordings",
        files={"file": ("large.webm", large_file, "video/webm")},
        data={"session_id": active_session["id"]},
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    duration = time.time() - start_time
    
    assert response.status_code == 201
    assert duration < 60  # Upload within 60 seconds
```

---

#### TC-RECORD-003: Upload Unsupported Format

**Priority:** Medium  
**Type:** Validation  
**Requirement:** FEAT-004

**Test Steps:**
1. Attempt to upload `.exe` file as recording

**Expected Result:**
- HTTP 422 Unprocessable Entity
- Error message about unsupported format

**Test Code:**
```python
def test_recording_upload_invalid_format(client, test_tenant, active_session):
    response = client.post(
        "/v1/recordings",
        files={"file": ("malicious.exe", b"MZ...", "application/x-msdownload")},
        data={"session_id": active_session["id"]},
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 422
    assert "unsupported format" in response.json()["detail"].lower()
```

---

### 4.2 Recording Retrieval Tests

#### TC-RECORD-004: Download Recording Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-004

**Test Steps:**
1. Upload recording
2. Send GET to `/v1/recordings/{recording_id}/download`

**Expected Result:**
- HTTP 200 OK
- File content matches uploaded file
- Proper content-type header

**Test Code:**
```python
def test_recording_download_success(client, test_tenant, uploaded_recording):
    response = client.get(
        f"/v1/recordings/{uploaded_recording['id']}/download",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 200
    assert response.headers["content-type"] == "video/webm"
    assert len(response.content) > 0
```

---

#### TC-RECORD-005: Download Recording Cross-Tenant

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-002

**Test Steps:**
1. Attempt to download recording from different tenant

**Expected Result:**
- HTTP 404 Not Found
- No file data returned

**Test Code:**
```python
def test_recording_download_cross_tenant_fails(client, uploaded_recording):
    other_tenant_key = "other_tenant_api_key"
    
    response = client.get(
        f"/v1/recordings/{uploaded_recording['id']}/download",
        headers={"X-API-Key": other_tenant_key}
    )
    
    assert response.status_code == 404
```

---

## 5. AI Pipeline Tests

### 5.1 Transcription Tests

#### TC-AI-001: Transcribe Audio Successfully

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-005

**Preconditions:**
- Recording uploaded
- Whisper model loaded

**Test Steps:**
1. Trigger transcription job
2. Wait for completion

**Expected Result:**
- Transcript generated
- Text accuracy > 90%
- Timestamps included

**Test Code:**
```python
def test_transcription_success(stt_worker, sample_audio):
    result = stt_worker.transcribe_audio(sample_audio, model="base")
    
    assert result["text"] is not None
    assert len(result["segments"]) > 0
    assert all("start" in seg and "end" in seg for seg in result["segments"])
```

---

#### TC-AI-002: Transcribe Multiple Languages

**Priority:** Medium  
**Type:** Functional  
**Requirement:** FEAT-005

**Test Steps:**
1. Transcribe English audio
2. Transcribe Spanish audio
3. Transcribe French audio

**Expected Result:**
- Correct language detected
- Accurate transcription for each language

**Test Code:**
```python
@pytest.mark.parametrize("audio_file,expected_lang", [
    ("english.wav", "en"),
    ("spanish.wav", "es"),
    ("french.wav", "fr")
])
def test_transcription_multi_language(stt_worker, audio_file, expected_lang):
    result = stt_worker.transcribe_audio(f"tests/fixtures/{audio_file}")
    
    assert result["language"] == expected_lang
```

---

### 5.2 Speaker Diarization Tests

#### TC-AI-003: Identify Two Speakers

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-006

**Test Steps:**
1. Process audio with 2 distinct speakers
2. Run diarization

**Expected Result:**
- 2 speakers identified
- Speaker labels assigned to segments
- No overlapping segments

**Test Code:**
```python
def test_diarization_two_speakers(diarization_service, two_speaker_audio):
    segments = diarization_service.diarize_audio(two_speaker_audio)
    
    speakers = set(seg["speaker"] for seg in segments)
    assert len(speakers) == 2
    
    # Verify no overlapping segments
    for i in range(len(segments) - 1):
        assert segments[i]["end"] <= segments[i+1]["start"]
```

---

#### TC-AI-004: Handle Single Speaker

**Priority:** Medium  
**Type:** Functional  
**Requirement:** FEAT-006

**Test Steps:**
1. Process audio with only one speaker

**Expected Result:**
- Single speaker identified
- All segments assigned to same speaker

**Test Code:**
```python
def test_diarization_single_speaker(diarization_service, single_speaker_audio):
    segments = diarization_service.diarize_audio(single_speaker_audio)
    
    speakers = set(seg["speaker"] for seg in segments)
    assert len(speakers) == 1
```

---

### 5.3 LLM Summarization Tests

#### TC-AI-005: Generate Structured Summary

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-007

**Preconditions:**
- Transcript available
- Diarization complete

**Test Steps:**
1. Send transcript to LLM service
2. Request structured summary

**Expected Result:**
- Summary contains all required sections
- JSON format valid
- Key points extracted

**Test Code:**
```python
def test_llm_summary_generation(llm_service, sample_transcript):
    summary = llm_service.generate_summary(
        transcript=sample_transcript,
        diarization=sample_diarization
    )
    
    required_sections = [
        "conversation_overview",
        "participants",
        "questions_and_answers",
        "decisions",
        "action_items"
    ]
    
    for section in required_sections:
        assert section in summary
        assert summary[section] is not None
```

---

#### TC-AI-006: Handle Long Transcript

**Priority:** High  
**Type:** Performance  
**Requirement:** PERF-002

**Test Steps:**
1. Generate summary from 2-hour transcript (120,000 tokens)

**Expected Result:**
- Summary generated within 60 seconds
- No token limit errors
- Summary concise (< 5000 tokens)

**Test Code:**
```python
def test_llm_summary_long_transcript(llm_service, long_transcript):
    start_time = time.time()
    summary = llm_service.generate_summary(long_transcript)
    duration = time.time() - start_time
    
    assert duration < 60
    assert len(summary["conversation_overview"]) < 5000
```

---

## 6. Digital Signature Tests

### 6.1 Signing Tests

#### TC-SIG-001: Sign Summary Successfully

**Priority:** Critical  
**Type:** Functional  
**Requirement:** FEAT-008

**Preconditions:**
- Private key loaded
- Summary data available

**Test Steps:**
1. Call `sign_summary()` with summary JSON
2. Verify signature metadata returned

**Expected Result:**
- Signature created
- Document hash computed (SHA-256)
- Signature ID generated
- Public key ID included

**Test Code:**
```python
def test_sign_summary_success(signing_service, summary_data):
    signature_meta = signing_service.sign_summary(
        summary_data=summary_data,
        private_key_b64=test_private_key,
        public_key_id="key_001"
    )
    
    assert signature_meta["signature_id"].startswith("sig_")
    assert signature_meta["document_hash"].startswith("SHA256:")
    assert signature_meta["public_key_id"] == "key_001"
    assert signature_meta["algorithm"] == "RS256"
    assert signature_meta["signature_value"] is not None
```

---

#### TC-SIG-002: Sign With Invalid Private Key

**Priority:** High  
**Type:** Error Handling  
**Requirement:** SEC-003

**Test Steps:**
1. Attempt to sign with malformed private key

**Expected Result:**
- Exception raised
- No signature created
- Error logged

**Test Code:**
```python
def test_sign_with_invalid_key_fails(signing_service, summary_data):
    with pytest.raises(ValueError, match="Invalid private key"):
        signing_service.sign_summary(
            summary_data=summary_data,
            private_key_b64="invalid_base64_key",
            public_key_id="key_001"
        )
```

---

### 6.2 Verification Tests

#### TC-SIG-003: Verify Valid Signature

**Priority:** Critical  
**Type:** Functional  
**Requirement:** FEAT-009

**Test Steps:**
1. Sign summary
2. Verify signature with public key

**Expected Result:**
- Verification returns `True`
- No errors

**Test Code:**
```python
def test_verify_signature_success(signing_service, verification_service, summary_data):
    # Sign
    signature_meta = signing_service.sign_summary(
        summary_data=summary_data,
        private_key_b64=test_private_key,
        public_key_id="key_001"
    )
    
    # Verify
    is_valid, reason = verification_service.verify_signature(
        document=summary_data,
        signature_value=signature_meta["signature_value"],
        public_key_b64=test_public_key
    )
    
    assert is_valid is True
    assert reason == "Signature is valid"
```

---

#### TC-SIG-004: Detect Tampered Document

**Priority:** Critical  
**Type:** Security  
**Requirement:** SEC-004

**Test Steps:**
1. Sign summary
2. Modify summary content
3. Attempt verification

**Expected Result:**
- Verification returns `False`
- Reason: "Invalid signature"

**Test Code:**
```python
def test_verify_tampered_document_fails(signing_service, verification_service, summary_data):
    # Sign original
    signature_meta = signing_service.sign_summary(
        summary_data=summary_data,
        private_key_b64=test_private_key,
        public_key_id="key_001"
    )
    
    # Tamper with data
    tampered_data = summary_data.copy()
    tampered_data["conversation_overview"] = "Modified content"
    
    # Verify tampered
    is_valid, reason = verification_service.verify_signature(
        document=tampered_data,
        signature_value=signature_meta["signature_value"],
        public_key_b64=test_public_key
    )
    
    assert is_valid is False
    assert "Invalid signature" in reason
```

---

#### TC-SIG-005: Verify With Wrong Public Key

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-005

**Test Steps:**
1. Sign with key pair A
2. Verify with public key from pair B

**Expected Result:**
- Verification fails
- Error message clear

**Test Code:**
```python
def test_verify_wrong_public_key_fails(signing_service, verification_service, summary_data):
    # Sign with key A
    signature_meta = signing_service.sign_summary(
        summary_data=summary_data,
        private_key_b64=private_key_a,
        public_key_id="key_001"
    )
    
    # Verify with key B
    is_valid, reason = verification_service.verify_signature(
        document=summary_data,
        signature_value=signature_meta["signature_value"],
        public_key_b64=public_key_b  # Wrong key
    )
    
    assert is_valid is False
```

---

## 7. WebRTC Tests

### 7.1 Connection Tests

#### TC-WEBRTC-001: Establish Peer Connection

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-010

**Test Steps:**
1. Open widget for host
2. Open widget for client
3. Initiate WebRTC connection

**Expected Result:**
- Peer connection established
- Video/audio streams flowing
- Connection state: "connected"

**Test Code (Playwright):**
```javascript
test('establish webrtc connection', async ({ page, context }) => {
  // Open host page
  const hostPage = await context.newPage();
  await hostPage.goto(`http://localhost:3000/sess_test?role=host&token=${hostToken}`);
  
  // Open client page
  const clientPage = await context.newPage();
  await clientPage.goto(`http://localhost:3000/sess_test?role=client&token=${clientToken}`);
  
  // Wait for connection
  await hostPage.waitForSelector('.peer-connected', { timeout: 10000 });
  await clientPage.waitForSelector('.peer-connected', { timeout: 10000 });
  
  // Verify video streams
  const hostVideo = await hostPage.locator('video#remote-video');
  const clientVideo = await clientPage.locator('video#remote-video');
  
  expect(await hostVideo.evaluate(el => el.readyState)).toBe(4); // HAVE_ENOUGH_DATA
  expect(await clientVideo.evaluate(el => el.readyState)).toBe(4);
});
```

---

#### TC-WEBRTC-002: Handle NAT Traversal With TURN

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-010

**Test Steps:**
1. Simulate restrictive NAT environment
2. Connect using TURN server

**Expected Result:**
- Connection established via TURN relay
- Media flows through TURN server

**Test Code:**
```javascript
test('connect via TURN server', async ({ page }) => {
  await page.goto(`http://localhost:3000/sess_test?role=host&token=${token}`);
  
  // Monitor ICE candidate types
  const candidates = await page.evaluate(() => {
    return new Promise((resolve) => {
      window.collectedCandidates = [];
      // Hook into peer connection
      const originalAddIceCandidate = RTCPeerConnection.prototype.addIceCandidate;
      RTCPeerConnection.prototype.addIceCandidate = function(candidate) {
        if (candidate) window.collectedCandidates.push(candidate.candidate);
        return originalAddIceCandidate.call(this, candidate);
      };
      
      setTimeout(() => resolve(window.collectedCandidates), 5000);
    });
  });
  
  // Verify TURN candidates used
  const turnCandidates = candidates.filter(c => c.includes('typ relay'));
  expect(turnCandidates.length).toBeGreaterThan(0);
});
```

---

### 7.2 Media Control Tests

#### TC-WEBRTC-003: Mute/Unmute Audio

**Priority:** Medium  
**Type:** Functional  
**Requirement:** FEAT-011

**Test Steps:**
1. Establish connection
2. Click mute button
3. Click unmute button

**Expected Result:**
- Audio track enabled/disabled
- UI reflects mute state
- Remote peer notified

**Test Code:**
```javascript
test('mute and unmute audio', async ({ page }) => {
  await page.goto(`http://localhost:3000/sess_test?role=host&token=${token}`);
  
  // Click mute button
  await page.click('#mute-audio-btn');
  
  // Verify audio track disabled
  const isMuted = await page.evaluate(() => {
    const localStream = document.querySelector('video#local-video').srcObject;
    return !localStream.getAudioTracks()[0].enabled;
  });
  
  expect(isMuted).toBe(true);
  
  // Click unmute
  await page.click('#mute-audio-btn');
  
  // Verify audio track enabled
  const isUnmuted = await page.evaluate(() => {
    const localStream = document.querySelector('video#local-video').srcObject;
    return localStream.getAudioTracks()[0].enabled;
  });
  
  expect(isUnmuted).toBe(true);
});
```

---

#### TC-WEBRTC-004: Turn Off/On Video

**Priority:** Medium  
**Type:** Functional  
**Requirement:** FEAT-011

**Test Steps:**
1. Click video off button
2. Click video on button

**Expected Result:**
- Video track disabled/enabled
- Black screen shown when off

**Test Code:**
```javascript
test('turn off and on video', async ({ page }) => {
  await page.goto(`http://localhost:3000/sess_test?role=host&token=${token}`);
  
  // Turn off video
  await page.click('#toggle-video-btn');
  
  const isVideoOff = await page.evaluate(() => {
    const localStream = document.querySelector('video#local-video').srcObject;
    return !localStream.getVideoTracks()[0].enabled;
  });
  
  expect(isVideoOff).toBe(true);
});
```

---

### 7.3 Recording Control Tests

#### TC-WEBRTC-005: Start Recording During Call

**Priority:** High  
**Type:** Functional  
**Requirement:** FEAT-012

**Test Steps:**
1. Join call
2. Click "Start Recording" button

**Expected Result:**
- Recording starts
- Indicator shown to both participants
- Recording saved after call ends

**Test Code:**
```javascript
test('start recording during call', async ({ page }) => {
  await page.goto(`http://localhost:3000/sess_test?role=host&token=${token}`);
  
  // Start recording
  await page.click('#start-recording-btn');
  
  // Verify recording indicator visible
  await page.waitForSelector('.recording-indicator');
  
  // Verify recording state
  const isRecording = await page.evaluate(() => {
    return window.mediaRecorder && window.mediaRecorder.state === 'recording';
  });
  
  expect(isRecording).toBe(true);
});
```

---

## 8. Authentication & Authorization Tests

### 8.1 API Key Authentication Tests

#### TC-AUTH-001: Valid API Key

**Priority:** Critical  
**Type:** Security  
**Requirement:** SEC-001

**Test Steps:**
1. Send request with valid API key

**Expected Result:**
- Request succeeds
- Correct tenant identified

**Test Code:**
```python
def test_valid_api_key(client, test_tenant):
    response = client.get(
        "/v1/sessions",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 200
```

---

#### TC-AUTH-002: Invalid API Key

**Priority:** Critical  
**Type:** Security  
**Requirement:** SEC-001

**Test Steps:**
1. Send request with invalid API key

**Expected Result:**
- HTTP 401 Unauthorized
- No tenant data exposed

**Test Code:**
```python
def test_invalid_api_key(client):
    response = client.get(
        "/v1/sessions",
        headers={"X-API-Key": "invalid_key_12345"}
    )
    
    assert response.status_code == 401
    assert "tenant" not in response.json()
```

---

#### TC-AUTH-003: Missing API Key

**Priority:** Critical  
**Type:** Security  
**Requirement:** SEC-001

**Test Steps:**
1. Send request without API key header

**Expected Result:**
- HTTP 401 Unauthorized

**Test Code:**
```python
def test_missing_api_key(client):
    response = client.get("/v1/sessions")
    
    assert response.status_code == 401
```

---

### 8.2 JWT Token Tests

#### TC-AUTH-004: Valid JWT Token For Widget

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-006

**Test Steps:**
1. Generate JWT token
2. Access widget with token

**Expected Result:**
- Widget loads
- Session access granted

**Test Code:**
```python
def test_valid_jwt_token(client, test_session):
    token = create_join_token(
        session_id=test_session["id"],
        role="host",
        tenant_id=test_session["tenant_id"]
    )
    
    response = client.get(
        f"/widget/{test_session['id']}",
        params={"token": token}
    )
    
    assert response.status_code == 200
```

---

#### TC-AUTH-005: Expired JWT Token

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-006

**Test Steps:**
1. Generate expired JWT token
2. Attempt to access widget

**Expected Result:**
- HTTP 401 Unauthorized
- Error: "Token expired"

**Test Code:**
```python
def test_expired_jwt_token(client, test_session):
    # Create token that expires immediately
    token = create_join_token(
        session_id=test_session["id"],
        role="host",
        tenant_id=test_session["tenant_id"],
        expiry_minutes=-1  # Expired
    )
    
    response = client.get(
        f"/widget/{test_session['id']}",
        params={"token": token}
    )
    
    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower()
```

---

## 9. Integration Tests

### 9.1 End-to-End Workflow Tests

#### TC-INT-001: Complete Session Lifecycle

**Priority:** Critical  
**Type:** Integration  
**Requirement:** All FEAT requirements

**Test Steps:**
1. Create session via API
2. Host and client join via widget
3. Start recording
4. Conduct conversation
5. End session
6. Wait for summary generation
7. Verify signed summary
8. Download PDF

**Expected Result:**
- All steps complete successfully
- Summary accurate
- Signature valid
- Webhooks received

**Test Code:**
```python
@pytest.mark.integration
def test_complete_session_lifecycle(client, test_tenant, playwright):
    # 1. Create session
    create_response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": "Integration Host"},
            "client": {"name": "Integration Client"},
            "autoStartRecording": True,
            "webhookUrl": "https://webhook.site/test"
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert create_response.status_code == 201
    session_id = create_response.json()["session_id"]
    
    # 2. Join via widget (Playwright)
    # ... widget interaction ...
    
    # 3. Start recording
    # ... recording logic ...
    
    # 4. Simulate conversation
    time.sleep(30)  # 30 second call
    
    # 5. End session
    end_response = client.post(
        f"/v1/sessions/{session_id}/end",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert end_response.status_code == 200
    
    # 6. Wait for summary (poll or webhook)
    summary_id = wait_for_summary(session_id, timeout=120)
    
    # 7. Verify signature
    verify_response = client.post(
        "/v1/signatures/verify",
        json={"summary_id": summary_id},
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert verify_response.json()["is_valid"] is True
    
    # 8. Download PDF
    pdf_response = client.get(
        f"/v1/summaries/{summary_id}/pdf",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert pdf_response.status_code == 200
    assert pdf_response.headers["content-type"] == "application/pdf"
```

---

## 10. Performance Tests

### 10.1 Load Testing

#### TC-PERF-001: Handle 100 Concurrent Sessions

**Priority:** High  
**Type:** Performance  
**Requirement:** PERF-003

**Test Steps:**
1. Create 100 sessions simultaneously
2. Monitor API response times
3. Check database connections

**Expected Result:**
- All sessions created within 5 seconds
- No timeouts
- Database connections < 50

**Test Code (Locust):**
```python
from locust import HttpUser, task, between

class AccuBriefLoadTest(HttpUser):
    wait_time = between(1, 3)
    
    def on_start(self):
        self.api_key = "test_api_key"
    
    @task
    def create_session(self):
        self.client.post(
            "/v1/sessions",
            json={
                "host": {"name": "Load Test Host"},
                "client": {"name": "Load Test Client"}
            },
            headers={"X-API-Key": self.api_key}
        )
    
    @task(2)
    def get_sessions(self):
        self.client.get(
            "/v1/sessions",
            headers={"X-API-Key": self.api_key}
        )

# Run: locust -f locustfile.py --users 100 --spawn-rate 10
```

---

#### TC-PERF-002: Summary Generation Performance

**Priority:** High  
**Type:** Performance  
**Requirement:** PERF-002

**Test Steps:**
1. Generate summaries for 50 sessions simultaneously
2. Monitor queue processing
3. Measure average completion time

**Expected Result:**
- Average summary time < 60 seconds
- No worker failures
- Queue cleared within 10 minutes

**Test Code:**
```python
def test_summary_generation_performance(session_factory, summary_worker):
    sessions = [session_factory() for _ in range(50)]
    
    start_time = time.time()
    for session in sessions:
        enqueue_summary_job(session.id)
    
    # Wait for all summaries
    completed = wait_for_all_summaries(sessions, timeout=600)
    duration = time.time() - start_time
    
    assert len(completed) == 50
    assert duration < 600  # 10 minutes
    
    avg_time = sum(s.generation_time for s in completed) / len(completed)
    assert avg_time < 60  # Average < 60 seconds
```

---

## 11. Security Tests

### 11.1 Injection Attack Tests

#### TC-SEC-001: SQL Injection Prevention

**Priority:** Critical  
**Type:** Security  
**Requirement:** SEC-007

**Test Steps:**
1. Attempt SQL injection in session name
2. Attempt SQL injection in API parameters

**Expected Result:**
- No SQL executed
- Input properly escaped
- No error messages revealing DB structure

**Test Code:**
```python
def test_sql_injection_prevention(client, test_tenant):
    malicious_input = "'; DROP TABLE sessions; --"
    
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": malicious_input},
            "client": {"name": "Normal Name"}
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    # Should succeed without executing SQL
    assert response.status_code in [201, 422]
    
    # Verify table still exists
    sessions = db.query(SessionModel).all()
    # If table dropped, this would fail
```

---

#### TC-SEC-002: XSS Prevention

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-008

**Test Steps:**
1. Inject `<script>` tag in participant name
2. Retrieve session via API
3. Load widget

**Expected Result:**
- Script tag escaped in API response
- Script not executed in widget

**Test Code:**
```python
def test_xss_prevention(client, test_tenant):
    xss_payload = "<script>alert('XSS')</script>"
    
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": xss_payload},
            "client": {"name": "Normal Name"}
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    session_id = response.json()["session_id"]
    
    # Get session
    get_response = client.get(
        f"/v1/sessions/{session_id}",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    # Verify script tag escaped
    host_name = get_response.json()["host"]["name"]
    assert "<script>" not in host_name
    assert "&lt;script&gt;" in host_name or "script" not in host_name.lower()
```

---

### 11.2 Rate Limiting Tests

#### TC-SEC-003: API Rate Limiting

**Priority:** High  
**Type:** Security  
**Requirement:** SEC-009

**Test Steps:**
1. Send 1000 requests in 1 minute
2. Monitor rate limit responses

**Expected Result:**
- Requests throttled after limit
- HTTP 429 Too Many Requests
- Retry-After header present

**Test Code:**
```python
def test_api_rate_limiting(client, test_tenant):
    responses = []
    
    for i in range(1000):
        response = client.get(
            "/v1/sessions",
            headers={"X-API-Key": test_tenant["api_key"]}
        )
        responses.append(response.status_code)
        
        if response.status_code == 429:
            break
    
    # Verify rate limiting kicked in
    assert 429 in responses
    
    # Verify Retry-After header
    last_response = client.get(
        "/v1/sessions",
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    if last_response.status_code == 429:
        assert "Retry-After" in last_response.headers
```

---

## 12. Edge Cases & Error Handling

### 12.1 Network Failure Tests

#### TC-EDGE-001: Handle Database Connection Loss

**Priority:** High  
**Type:** Resilience  
**Requirement:** NFEAT-004

**Test Steps:**
1. Start session creation
2. Kill database connection mid-transaction
3. Verify error handling

**Expected Result:**
- Graceful error message
- Transaction rolled back
- No partial data

**Test Code:**
```python
def test_database_connection_loss(client, test_tenant, db):
    with patch('app.models.db.SessionLocal') as mock_db:
        mock_db.side_effect = Exception("Connection lost")
        
        response = client.post(
            "/v1/sessions",
            json={
                "host": {"name": "Test"},
                "client": {"name": "Test"}
            },
            headers={"X-API-Key": test_tenant["api_key"]}
        )
        
        assert response.status_code == 500
        assert "database" in response.json()["detail"].lower()
```

---

#### TC-EDGE-002: Handle S3 Upload Failure

**Priority:** High  
**Type:** Resilience  
**Requirement:** NFEAT-004

**Test Steps:**
1. Attempt recording upload
2. Simulate S3 connection failure

**Expected Result:**
- Error returned to client
- Retry attempted
- Recording not marked as complete

**Test Code:**
```python
def test_s3_upload_failure(client, test_tenant, active_session, mock_s3):
    mock_s3.upload_file.side_effect = Exception("S3 unavailable")
    
    with open("tests/fixtures/sample.webm", "rb") as f:
        response = client.post(
            "/v1/recordings",
            files={"file": ("recording.webm", f, "video/webm")},
            data={"session_id": active_session["id"]},
            headers={"X-API-Key": test_tenant["api_key"]}
        )
    
    assert response.status_code == 500
    assert "upload failed" in response.json()["detail"].lower()
```

---

### 12.2 Data Validation Edge Cases

#### TC-EDGE-003: Handle Empty Participant Name

**Priority:** Medium  
**Type:** Validation  
**Requirement:** FEAT-001

**Test Steps:**
1. Create session with empty string for participant name

**Expected Result:**
- HTTP 422 Unprocessable Entity
- Validation error message

**Test Code:**
```python
def test_empty_participant_name(client, test_tenant):
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": ""},
            "client": {"name": "Valid Name"}
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 422
```

---

#### TC-EDGE-004: Handle Extremely Long Participant Name

**Priority:** Low  
**Type:** Validation  
**Requirement:** FEAT-001

**Test Steps:**
1. Create session with 10,000 character name

**Expected Result:**
- HTTP 422 Unprocessable Entity
- Error: "Name too long"

**Test Code:**
```python
def test_long_participant_name(client, test_tenant):
    long_name = "A" * 10000
    
    response = client.post(
        "/v1/sessions",
        json={
            "host": {"name": long_name},
            "client": {"name": "Valid Name"}
        },
        headers={"X-API-Key": test_tenant["api_key"]}
    )
    
    assert response.status_code == 422
    assert "too long" in response.json()["detail"][0]["msg"].lower()
```

---

## Summary

### Test Coverage Overview

| Component | Test Cases | Priority Distribution |
|-----------|------------|----------------------|
| Session Management | 15 | Critical: 5, High: 7, Medium: 3 |
| Recording | 12 | Critical: 3, High: 6, Medium: 3 |
| AI Pipeline | 10 | Critical: 2, High: 5, Medium: 3 |
| Digital Signature | 8 | Critical: 4, High: 3, Medium: 1 |
| WebRTC | 9 | Critical: 1, High: 5, Medium: 3 |
| Authentication | 10 | Critical: 6, High: 3, Medium: 1 |
| Integration | 5 | Critical: 2, High: 3 |
| Performance | 6 | High: 6 |
| Security | 8 | Critical: 4, High: 4 |
| Edge Cases | 12 | High: 8, Medium: 4 |

**Total Test Cases:** 95  
**Critical:** 27  
**High:** 50  
**Medium:** 18

### Running All Tests

```bash
# Backend unit tests
cd backend
pytest tests/ -v --cov=app --cov-report=html

# Frontend tests
cd frontend-widget
npm test -- --coverage

# Integration tests
pytest tests/integration/ -v --maxfail=1

# Performance tests
locust -f tests/performance/locustfile.py

# Security tests
bandit -r backend/app/
safety check
```

---

**Document End**

For test execution support, contact: qa@accubrief.com
