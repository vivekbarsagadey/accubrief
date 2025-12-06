# State Machine Diagrams - AccuBrief

## Overview

This document describes the state machines for all major entities in AccuBrief. State machines define the valid states, transitions, and triggers for each entity type.

## 1. Session State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                     SESSION LIFECYCLE                       │
                                  └─────────────────────────────────────────────────────────────┘

                                                          API: POST /sessions
                                                                  │
                                                                  ▼
                                                        ┌─────────────────┐
                                                        │    SCHEDULED    │
                                                        │                 │
                                                        │  Initial state  │
                                                        │  after creation │
                                                        └────────┬────────┘
                                                                 │
                                              Both participants join via widget
                                                                 │
                                                                 ▼
                                                        ┌─────────────────┐
                                                        │     ACTIVE      │
                                                        │                 │
                                                        │ Call in progress│
                                                        │ Recording active│
                                                        └────────┬────────┘
                                                                 │
                                                    Host clicks "End Call"
                                                    or API: POST /sessions/{id}/end
                                                                 │
                                                                 ▼
                                                        ┌─────────────────┐
                                                        │      ENDED      │
                                                        │                 │
                                                        │ Recording saved │
                                                        │ Pipeline queued │
                                                        └────────┬────────┘
                                                                 │
                                                      Worker picks up job
                                                                 │
                                                                 ▼
                                                        ┌─────────────────┐
                                                        │   PROCESSING    │
                                                        │                 │
                                                        │  STT running    │
                                                        │  LLM generating │
                                                        └────────┬────────┘
                                                                 │
                                              ┌──────────────────┴──────────────────┐
                                              │                                     │
                                         Success                                Failure
                                              │                                     │
                                              ▼                                     ▼
                                    ┌─────────────────┐                   ┌─────────────────┐
                                    │    COMPLETED    │                   │     FAILED      │
                                    │                 │                   │                 │
                                    │ Summary ready   │                   │ Error occurred  │
                                    │ Webhook sent    │                   │ Webhook sent    │
                                    └─────────────────┘                   └─────────────────┘
```

### State Definitions

| State | Description | Entry Actions | Exit Actions |
|-------|-------------|---------------|--------------|
| **SCHEDULED** | Session created, waiting for participants | Create session record, Generate tokens | - |
| **ACTIVE** | Both participants connected, call in progress | Set started_at, Start recording | Stop recording |
| **ENDED** | Call terminated, processing pending | Set ended_at, Upload recording | Queue pipeline job |
| **PROCESSING** | AI pipeline running | Update status | - |
| **COMPLETED** | Summary generated and signed | Attach signature, Send webhook | - |
| **FAILED** | Processing error occurred | Log error, Send failure webhook | - |

### Transition Rules

| From | To | Trigger | Guard Conditions |
|------|-----|---------|------------------|
| SCHEDULED | ACTIVE | Both participants join | WebRTC connected |
| ACTIVE | ENDED | Host ends call OR timeout | Recording uploaded |
| ENDED | PROCESSING | Worker picks up job | Recording available |
| PROCESSING | COMPLETED | Pipeline succeeds | Summary signed |
| PROCESSING | FAILED | Pipeline error | - |

### Implementation

```python
from enum import Enum
from typing import Optional

class SessionStatus(Enum):
    SCHEDULED = "scheduled"
    ACTIVE = "active"
    ENDED = "ended"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class SessionStateMachine:
    """State machine for session lifecycle."""
    
    TRANSITIONS = {
        SessionStatus.SCHEDULED: [SessionStatus.ACTIVE],
        SessionStatus.ACTIVE: [SessionStatus.ENDED],
        SessionStatus.ENDED: [SessionStatus.PROCESSING],
        SessionStatus.PROCESSING: [SessionStatus.COMPLETED, SessionStatus.FAILED],
        SessionStatus.COMPLETED: [],
        SessionStatus.FAILED: [],
    }
    
    @classmethod
    def can_transition(cls, current: SessionStatus, target: SessionStatus) -> bool:
        """Check if transition is valid."""
        return target in cls.TRANSITIONS.get(current, [])
    
    @classmethod
    def transition(cls, session, target: SessionStatus) -> None:
        """Execute state transition with validation."""
        if not cls.can_transition(session.status, target):
            raise ValueError(
                f"Invalid transition: {session.status.value} -> {target.value}"
            )
        session.status = target
```

---

## 2. Recording State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                    RECORDING LIFECYCLE                      │
                                  └─────────────────────────────────────────────────────────────┘

                                              MediaRecorder starts in widget
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │   RECORDING     │
                                                │                 │
                                                │ Capturing media │
                                                │ Chunks in memory│
                                                └────────┬────────┘
                                                         │
                                                  Stop recording
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   UPLOADING     │
                                                │                 │
                                                │ Blob to backend │
                                                │ Multipart upload│
                                                └────────┬────────┘
                                                         │
                                      ┌──────────────────┴──────────────────┐
                                      │                                     │
                                   Success                               Failure
                                      │                                     │
                                      ▼                                     ▼
                            ┌─────────────────┐                   ┌─────────────────┐
                            │    UPLOADED     │                   │  UPLOAD_FAILED  │
                            │                 │                   │                 │
                            │ Stored in S3    │                   │ Retry possible  │
                            │ Metadata saved  │                   └────────┬────────┘
                            └────────┬────────┘                            │
                                     │                                  Retry
                                     │                                     │
                                     │                     ┌───────────────┘
                                     │                     │
                                     ▼                     ▼
                            ┌─────────────────┐         ┌─────────────────┐
                            │   PROCESSING    │◀────────│   UPLOADING     │
                            │                 │         └─────────────────┘
                            │ Audio extraction│
                            └────────┬────────┘
                                     │
                      ┌──────────────┴──────────────┐
                      │                             │
                   Success                       Failure
                      │                             │
                      ▼                             ▼
            ┌─────────────────┐           ┌─────────────────┐
            │    PROCESSED    │           │     FAILED      │
            │                 │           │                 │
            │ Ready for STT   │           │ Needs attention │
            └─────────────────┘           └─────────────────┘
```

### State Definitions

| State | Description | Entry Actions |
|-------|-------------|---------------|
| **RECORDING** | Media being captured | Initialize MediaRecorder |
| **UPLOADING** | Blob being uploaded | Create upload record |
| **UPLOAD_FAILED** | Upload failed | Log error, Schedule retry |
| **UPLOADED** | File in storage | Save file path, Update metadata |
| **PROCESSING** | Being processed | Extract audio |
| **PROCESSED** | Ready for pipeline | Mark as ready |
| **FAILED** | Processing failed | Log error |

### Transition Rules

| From | To | Trigger |
|------|-----|---------|
| RECORDING | UPLOADING | Stop button / Session end |
| UPLOADING | UPLOADED | Upload complete (2xx) |
| UPLOADING | UPLOAD_FAILED | Network error / Timeout |
| UPLOAD_FAILED | UPLOADING | Retry triggered |
| UPLOADED | PROCESSING | Pipeline started |
| PROCESSING | PROCESSED | Audio extracted |
| PROCESSING | FAILED | Extraction error |

---

## 3. Summary State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                     SUMMARY LIFECYCLE                       │
                                  └─────────────────────────────────────────────────────────────┘

                                                   Session ended
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │     PENDING     │
                                              │                 │
                                              │ Record created  │
                                              │ Waiting worker  │
                                              └────────┬────────┘
                                                       │
                                              Worker picks up job
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │   TRANSCRIBING  │
                                              │                 │
                                              │  STT running    │
                                              └────────┬────────┘
                                                       │
                                              ┌────────┴────────┐
                                              │                 │
                                           Success           Failure
                                              │                 │
                                              ▼                 │
                                    ┌─────────────────┐         │
                                    │   DIARIZING     │         │
                                    │                 │         │
                                    │ Speaker ID      │         │
                                    └────────┬────────┘         │
                                             │                  │
                                    ┌────────┴────────┐         │
                                    │                 │         │
                                 Success           Failure      │
                                    │                 │         │
                                    ▼                 │         │
                          ┌─────────────────┐         │         │
                          │   SUMMARIZING   │         │         │
                          │                 │         │         │
                          │  LLM running    │         │         │
                          └────────┬────────┘         │         │
                                   │                  │         │
                          ┌────────┴────────┐         │         │
                          │                 │         │         │
                       Success           Failure      │         │
                          │                 │         │         │
                          ▼                 │         │         │
                ┌─────────────────┐         │         │         │
                │   GENERATING    │         │         │         │
                │      PDF        │         │         │         │
                └────────┬────────┘         │         │         │
                         │                  │         │         │
                ┌────────┴────────┐         │         │         │
                │                 │         │         │         │
             Success           Failure      │         │         │
                │                 │         │         │         │
                ▼                 ▼         ▼         ▼         ▼
      ┌─────────────────┐     ┌───────────────────────────────────┐
      │     SIGNING     │     │             FAILED                │
      │                 │     │                                   │
      │  RSA signing    │     │ Pipeline error at any stage       │
      └────────┬────────┘     └───────────────────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
   Success           Failure
      │                 │
      ▼                 ▼
┌─────────────────┐   ┌─────────────────┐
│      READY      │   │     FAILED      │
│                 │   └─────────────────┘
│ Summary signed  │
│ Webhook sent    │
└─────────────────┘
```

### Simplified State (Database)

The database stores a simplified status, while internal processing tracks detailed stages:

```python
class SummaryStatus(Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    READY = "ready"
    FAILED = "failed"

class ProcessingStage(Enum):
    """Internal tracking of pipeline progress."""
    QUEUED = "queued"
    TRANSCRIBING = "transcribing"
    DIARIZING = "diarizing"
    SUMMARIZING = "summarizing"
    GENERATING_PDF = "generating_pdf"
    SIGNING = "signing"
    COMPLETE = "complete"
```

### State Definitions

| State | Description | Entry Actions |
|-------|-------------|---------------|
| **PENDING** | Waiting for worker | Create summary record |
| **PROCESSING** | Pipeline active | Update timestamp |
| **READY** | Complete and signed | Set generated_at, Send webhook |
| **FAILED** | Error occurred | Set error message, Send webhook |

---

## 4. Signature State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                    SIGNATURE LIFECYCLE                      │
                                  └─────────────────────────────────────────────────────────────┘

                                                   Summary ready
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │  CANONICALIZING │
                                              │                 │
                                              │ Sort keys       │
                                              │ Remove spaces   │
                                              └────────┬────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │    HASHING      │
                                              │                 │
                                              │ SHA-256 digest  │
                                              └────────┬────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │    SIGNING      │
                                              │                 │
                                              │ RSA PKCS1v15    │
                                              └────────┬────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │    STORING      │
                                              │                 │
                                              │ Save to DB      │
                                              └────────┬────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │     VALID       │
                                              │                 │
                                              │ Can be verified │
                                              └─────────────────┘
```

### Verification State Flow

```
                                                   Verification Request
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │ LOAD_SIGNATURE  │
                                                │                 │
                                                │ Get from DB     │
                                                └────────┬────────┘
                                                         │
                                        ┌────────────────┴────────────────┐
                                        │                                 │
                                      Found                          Not Found
                                        │                                 │
                                        ▼                                 ▼
                              ┌─────────────────┐               ┌─────────────────┐
                              │ RECOMPUTE_HASH  │               │   NOT_SIGNED    │
                              │                 │               └─────────────────┘
                              │ Hash document   │
                              └────────┬────────┘
                                       │
                              ┌────────┴────────┐
                              │                 │
                           Match             Mismatch
                              │                 │
                              ▼                 ▼
                    ┌─────────────────┐ ┌─────────────────┐
                    │ VERIFY_SIGNATURE│ │  HASH_MISMATCH  │
                    │                 │ │                 │
                    │ RSA verify      │ │ Content changed │
                    └────────┬────────┘ └─────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                  Valid            Invalid
                    │                 │
                    ▼                 ▼
          ┌─────────────────┐ ┌─────────────────┐
          │    VERIFIED     │ │ SIG_INVALID     │
          │                 │ │                 │
          │ isValid: true   │ │ Tampered/Wrong  │
          └─────────────────┘ └─────────────────┘
```

---

## 5. Webhook Delivery State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                   WEBHOOK DELIVERY LIFECYCLE                │
                                  └─────────────────────────────────────────────────────────────┘

                                                       Event triggered
                                                            │
                                                            ▼
                                                  ┌─────────────────┐
                                                  │     PENDING     │
                                                  │                 │
                                                  │ Created record  │
                                                  │ Attempt: 0      │
                                                  └────────┬────────┘
                                                           │
                                                     Send webhook
                                                           │
                                                           ▼
                                                  ┌─────────────────┐
                                                  │   DELIVERING    │
                                                  │                 │
                                                  │ HTTP POST       │
                                                  └────────┬────────┘
                                                           │
                                        ┌──────────────────┴──────────────────┐
                                        │                                     │
                                    2xx Response                       Error/Timeout
                                        │                                     │
                                        ▼                                     ▼
                              ┌─────────────────┐                   ┌─────────────────┐
                              │     SUCCESS     │                   │    RETRYING     │
                              │                 │                   │                 │
                              │ Delivery done   │                   │ Schedule retry  │
                              │ Log response    │                   │ Increment count │
                              └─────────────────┘                   └────────┬────────┘
                                                                             │
                                                              ┌──────────────┴──────────────┐
                                                              │                             │
                                                         attempts < 5                  attempts >= 5
                                                              │                             │
                                                              ▼                             ▼
                                                    ┌─────────────────┐           ┌─────────────────┐
                                                    │     PENDING     │           │     FAILED      │
                                                    │                 │           │                 │
                                                    │ Wait for retry  │           │ Max retries     │
                                                    └────────┬────────┘           │ Give up         │
                                                             │                    └─────────────────┘
                                                     Retry delay elapsed
                                                             │
                                                             ▼
                                                    ┌─────────────────┐
                                                    │   DELIVERING    │
                                                    └─────────────────┘
```

### Retry Schedule

| Attempt | Delay | Cumulative Time |
|---------|-------|-----------------|
| 1 | 0 | 0 |
| 2 | 1 min | 1 min |
| 3 | 5 min | 6 min |
| 4 | 30 min | 36 min |
| 5 | 2 hours | 2h 36min |

### Implementation

```python
from datetime import datetime, timedelta
from enum import Enum

class DeliveryStatus(Enum):
    PENDING = "pending"
    SUCCESS = "success"
    FAILED = "failed"
    RETRYING = "retrying"

RETRY_DELAYS = [0, 60, 300, 1800, 7200]  # seconds

class WebhookStateMachine:
    """State machine for webhook delivery."""
    
    @classmethod
    def get_next_retry_delay(cls, attempt_count: int) -> int | None:
        """Get delay before next retry, or None if max retries."""
        if attempt_count >= len(RETRY_DELAYS):
            return None
        return RETRY_DELAYS[attempt_count]
    
    @classmethod
    def should_retry(cls, attempt_count: int) -> bool:
        """Check if should retry delivery."""
        return attempt_count < len(RETRY_DELAYS)
    
    @classmethod
    def calculate_next_attempt(cls, attempt_count: int) -> datetime | None:
        """Calculate next attempt time."""
        delay = cls.get_next_retry_delay(attempt_count)
        if delay is None:
            return None
        return datetime.utcnow() + timedelta(seconds=delay)
```

---

## 6. WebRTC Connection State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                   WEBRTC CONNECTION LIFECYCLE               │
                                  └─────────────────────────────────────────────────────────────┘

                                                     Widget loads
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │      NEW        │
                                                │                 │
                                                │ Init connection │
                                                └────────┬────────┘
                                                         │
                                          Request getUserMedia
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │ GETTING_MEDIA   │
                                                │                 │
                                                │ Camera/Mic req  │
                                                └────────┬────────┘
                                                         │
                                        ┌────────────────┴────────────────┐
                                        │                                 │
                                    Granted                            Denied
                                        │                                 │
                                        ▼                                 ▼
                              ┌─────────────────┐               ┌─────────────────┐
                              │  CONNECTING     │               │   MEDIA_ERROR   │
                              │                 │               └─────────────────┘
                              │ WS + WebRTC     │
                              └────────┬────────┘
                                       │
                          ┌────────────┴────────────┐
                          │                         │
                      Connected                   Error
                          │                         │
                          ▼                         ▼
                ┌─────────────────┐       ┌─────────────────┐
                │   CONNECTED     │       │ CONNECT_FAILED  │
                │                 │       └─────────────────┘
                │ P2P established │
                └────────┬────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
         End call            Connection lost
              │                     │
              ▼                     ▼
    ┌─────────────────┐   ┌─────────────────┐
    │  DISCONNECTED   │   │  RECONNECTING   │
    │                 │   │                 │
    │ Clean shutdown  │   │ Auto-retry      │
    └─────────────────┘   └────────┬────────┘
                                   │
                        ┌──────────┴──────────┐
                        │                     │
                   Reconnected            Max retries
                        │                     │
                        ▼                     ▼
              ┌─────────────────┐   ┌─────────────────┐
              │   CONNECTED     │   │  DISCONNECTED   │
              └─────────────────┘   └─────────────────┘
```

### RTCPeerConnection States

AccuBrief maps native WebRTC states to simplified app states:

| Native State | App State | Description |
|--------------|-----------|-------------|
| `new` | CONNECTING | Connection object created |
| `connecting` | CONNECTING | Negotiating connection |
| `connected` | CONNECTED | P2P established |
| `disconnected` | RECONNECTING | Temporary network issue |
| `failed` | CONNECT_FAILED | Connection failed |
| `closed` | DISCONNECTED | Connection closed |

---

## 7. Signing Key State Machine

### State Diagram

```
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                    SIGNING KEY LIFECYCLE                    │
                                  └─────────────────────────────────────────────────────────────┘

                                                     Key generated
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │     ACTIVE      │
                                                │                 │
                                                │ Used for signing│
                                                └────────┬────────┘
                                                         │
                              ┌───────────────┬──────────┴───────────┬───────────────┐
                              │               │                      │               │
                         New key          Time expires          Compromised       Normal
                         created                                                 retirement
                              │               │                      │               │
                              ▼               ▼                      ▼               ▼
                    ┌─────────────────┐                     ┌─────────────────┐
                    │   DEPRECATED    │                     │    REVOKED      │
                    │                 │                     │                 │
                    │ Still verifies  │                     │ Cannot verify   │
                    │ No new signing  │                     │ Compromised     │
                    └────────┬────────┘                     └─────────────────┘
                             │
                      Grace period ends
                             │
                             ▼
                    ┌─────────────────┐
                    │    EXPIRED      │
                    │                 │
                    │ Still verifies  │
                    │ Archived        │
                    └─────────────────┘
```

### State Definitions

| State | Can Sign | Can Verify | Description |
|-------|----------|------------|-------------|
| **ACTIVE** | ✅ | ✅ | Primary key for new signatures |
| **DEPRECATED** | ❌ | ✅ | Replaced by new key, verify only |
| **EXPIRED** | ❌ | ✅ | Past expiration, verify only |
| **REVOKED** | ❌ | ❌ | Compromised, reject all |

---

## State Machine Testing

### Test Cases

```python
import pytest
from app.models.session_model import SessionStatus
from app.state_machines import SessionStateMachine

class TestSessionStateMachine:
    
    def test_valid_transition_scheduled_to_active(self):
        assert SessionStateMachine.can_transition(
            SessionStatus.SCHEDULED, 
            SessionStatus.ACTIVE
        ) is True
    
    def test_invalid_transition_scheduled_to_completed(self):
        assert SessionStateMachine.can_transition(
            SessionStatus.SCHEDULED, 
            SessionStatus.COMPLETED
        ) is False
    
    def test_invalid_transition_from_completed(self):
        # Terminal state - no transitions allowed
        for status in SessionStatus:
            assert SessionStateMachine.can_transition(
                SessionStatus.COMPLETED, 
                status
            ) is False
    
    def test_transition_raises_on_invalid(self):
        session = Session(status=SessionStatus.SCHEDULED)
        
        with pytest.raises(ValueError):
            SessionStateMachine.transition(session, SessionStatus.COMPLETED)
```
