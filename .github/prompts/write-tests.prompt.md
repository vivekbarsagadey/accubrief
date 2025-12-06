```prompt
---
description: Write comprehensive tests for AccuBrief backend (pytest) and frontend (React Testing Library)
tools:
  - create_file
  - read_file
  - semantic_search
  - list_code_usages
  - runTests
---

# Write Tests for AccuBrief

You are a testing expert for Python (pytest) and React (React Testing Library/Jest). Write comprehensive, maintainable tests for AccuBrief following best practices.

## Backend Testing (Python + pytest)

### Test Structure

```
backend/tests/
├── __init__.py
├── conftest.py              # Shared fixtures
├── api/
│   └── v1/
│       ├── test_sessions.py
│       ├── test_recordings.py
│       ├── test_summaries.py
│       └── test_signatures.py
├── services/
│   ├── test_session_service.py
│   ├── test_summary_pipeline.py
│   └── test_webhook_dispatcher.py
├── crypto/
│   ├── test_signing_service.py
│   └── test_verification_service.py
└── integration/
    └── test_tenant_isolation.py
```

### pytest Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "-v",
    "--cov=app",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--asyncio-mode=auto"
]
asyncio_mode = "auto"
```

### Common Fixtures

```python
# tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.models.db import Base, get_db
from app.core.security import get_current_tenant

# Test database
SQLALCHEMY_TEST_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_TEST_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture(scope="function")
def db_session():
    """Create a fresh database session for each test."""
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture
def client(db_session):
    """Test client with database override."""
    def override_get_db():
        try:
            yield db_session
        finally:
            pass
    
    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def mock_tenant():
    """Mock tenant for testing."""
    class MockTenant:
        id = "tenant_test_001"
        name = "Test Tenant"
        api_key = "test_api_key"
    return MockTenant()


@pytest.fixture
def authenticated_client(client, mock_tenant):
    """Test client with authentication."""
    def override_get_current_tenant():
        return mock_tenant
    
    app.dependency_overrides[get_current_tenant] = override_get_current_tenant
    yield client
    app.dependency_overrides.clear()
```

### API Route Tests

```python
# tests/api/v1/test_sessions.py
import pytest
from fastapi import status


class TestSessionsAPI:
    """Test session management endpoints."""
    
    def test_create_session_success(self, authenticated_client):
        """Test creating a new session."""
        response = authenticated_client.post(
            "/v1/sessions",
            json={
                "host": {"name": "Dr. Smith", "external_user_id": "user_123"},
                "client": {"name": "John Doe"},
                "auto_start_recording": True
            }
        )
        
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "session_id" in data
        assert data["session_id"].startswith("sess_")
        assert "widget_urls" in data
        assert "host" in data["widget_urls"]
        assert "client" in data["widget_urls"]
    
    def test_create_session_unauthorized(self, client):
        """Test creating session without API key fails."""
        response = client.post(
            "/v1/sessions",
            json={"host": {"name": "Dr. Smith"}, "client": {"name": "John"}}
        )
        
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
    
    def test_get_session_success(self, authenticated_client, db_session):
        """Test retrieving an existing session."""
        # Create session first
        create_response = authenticated_client.post(
            "/v1/sessions",
            json={"host": {"name": "Dr. Smith"}, "client": {"name": "John"}}
        )
        session_id = create_response.json()["session_id"]
        
        # Get session
        response = authenticated_client.get(f"/v1/sessions/{session_id}")
        
        assert response.status_code == status.HTTP_200_OK
        assert response.json()["session_id"] == session_id
    
    def test_get_session_not_found(self, authenticated_client):
        """Test getting non-existent session returns 404."""
        response = authenticated_client.get("/v1/sessions/sess_nonexistent")
        
        assert response.status_code == status.HTTP_404_NOT_FOUND
    
    def test_get_session_wrong_tenant(self, authenticated_client, db_session):
        """Test tenant isolation - can't access other tenant's session."""
        # This test would require setting up two different tenants
        # and verifying cross-tenant access is blocked
        pass
```

### Service Tests

```python
# tests/services/test_session_service.py
import pytest
from app.services.session_service import create_session_service
from app.schemas.session import CreateSessionRequest, ParticipantSchema


class TestSessionService:
    """Test session service functions."""
    
    def test_create_session(self, db_session):
        """Test session creation."""
        service = create_session_service(db_session)
        
        request = CreateSessionRequest(
            host=ParticipantSchema(name="Dr. Smith"),
            client=ParticipantSchema(name="John Doe"),
            auto_start_recording=True
        )
        
        session = service["create_session"](request, "tenant_001")
        
        assert session.id.startswith("sess_")
        assert session.tenant_id == "tenant_001"
        assert session.status == "scheduled"
        assert session.host["name"] == "Dr. Smith"
    
    def test_get_session_filters_by_tenant(self, db_session):
        """Test that get_session filters by tenant_id."""
        service = create_session_service(db_session)
        
        # Create session for tenant_001
        request = CreateSessionRequest(
            host=ParticipantSchema(name="Dr. Smith"),
            client=ParticipantSchema(name="John")
        )
        session = service["create_session"](request, "tenant_001")
        
        # Try to get with different tenant - should return None
        result = service["get_session"](session.id, "tenant_002")
        assert result is None
        
        # Get with correct tenant - should return session
        result = service["get_session"](session.id, "tenant_001")
        assert result is not None
        assert result.id == session.id
    
    def test_soft_delete_session(self, db_session):
        """Test session soft delete."""
        service = create_session_service(db_session)
        
        # Create session
        request = CreateSessionRequest(
            host=ParticipantSchema(name="Dr. Smith"),
            client=ParticipantSchema(name="John")
        )
        session = service["create_session"](request, "tenant_001")
        
        # Soft delete
        service["end_session"](session.id, "tenant_001", "user_001")
        
        # Verify session is soft deleted
        result = service["get_session"](session.id, "tenant_001")
        assert result.status == "ended"
```

### Crypto Tests

```python
# tests/crypto/test_signing_service.py
import pytest
import json
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend
from app.crypto.signing_service import create_signing_service


@pytest.fixture
def test_keys():
    """Generate test RSA key pair."""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    return {
        "private_key": private_key,
        "public_key": private_key.public_key(),
        "public_key_id": "key_test_001"
    }


class TestSigningService:
    """Test digital signature operations."""
    
    def test_sign_summary(self, test_keys):
        """Test signing a summary produces valid signature."""
        mock_kms = type('MockKMS', (), {
            'get_active_signing_key': lambda self, tenant_id: type('Key', (), {
                'private_key': test_keys["private_key"],
                'public_key_id': test_keys["public_key_id"]
            })()
        })()
        
        service = create_signing_service(mock_kms)
        
        summary_data = {
            "overview": "Test summary",
            "participants": [{"name": "Dr. Smith"}, {"name": "John"}]
        }
        
        signature = service["sign_summary"](summary_data, "tenant_001")
        
        assert signature["signature_id"].startswith("sig_")
        assert signature["public_key_id"] == "key_test_001"
        assert signature["document_hash"].startswith("SHA256:")
        assert signature["algorithm"] == "RS256"
        assert "signature_value" in signature
    
    def test_signature_is_deterministic(self, test_keys):
        """Test same data produces same hash."""
        mock_kms = type('MockKMS', (), {
            'get_active_signing_key': lambda self, tenant_id: type('Key', (), {
                'private_key': test_keys["private_key"],
                'public_key_id': test_keys["public_key_id"]
            })()
        })()
        
        service = create_signing_service(mock_kms)
        
        summary_data = {"key": "value", "nested": {"a": 1, "b": 2}}
        
        sig1 = service["sign_summary"](summary_data, "tenant_001")
        sig2 = service["sign_summary"](summary_data, "tenant_001")
        
        # Hash should be identical for same data
        assert sig1["document_hash"] == sig2["document_hash"]
```

---

## Frontend Testing (React Testing Library)

### Test Structure

```
frontend-widget/src/
├── __tests__/
│   ├── components/
│   │   ├── VideoTile.test.tsx
│   │   ├── ControlsBar.test.tsx
│   │   └── RecordingIndicator.test.tsx
│   ├── hooks/
│   │   ├── useWebRTC.test.ts
│   │   └── useSession.test.ts
│   └── pages/
│       └── Widget.test.tsx
└── setupTests.ts
```

### Component Tests

```typescript
// __tests__/components/VideoTile.test.tsx
import { render, screen } from '@testing-library/react';
import { VideoTile } from '../../components/VideoTile';

describe('VideoTile', () => {
  it('renders video element', () => {
    render(<VideoTile stream={null} label="Host" />);
    
    expect(screen.getByRole('video')).toBeInTheDocument();
    expect(screen.getByText('Host')).toBeInTheDocument();
  });

  it('shows muted icon when muted', () => {
    render(<VideoTile stream={null} label="Host" muted={true} />);
    
    const video = screen.getByRole('video');
    expect(video).toHaveAttribute('muted');
  });
});
```

```typescript
// __tests__/components/ControlsBar.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { ControlsBar } from '../../components/ControlsBar';

describe('ControlsBar', () => {
  const mockHandlers = {
    onMuteToggle: jest.fn(),
    onCameraToggle: jest.fn(),
    onRecordingToggle: jest.fn(),
    onEndCall: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls onMuteToggle when mute button clicked', () => {
    render(<ControlsBar {...mockHandlers} isMuted={false} />);
    
    fireEvent.click(screen.getByRole('button', { name: /mute/i }));
    
    expect(mockHandlers.onMuteToggle).toHaveBeenCalledTimes(1);
  });

  it('calls onEndCall when end call button clicked', () => {
    render(<ControlsBar {...mockHandlers} isMuted={false} />);
    
    fireEvent.click(screen.getByRole('button', { name: /end call/i }));
    
    expect(mockHandlers.onEndCall).toHaveBeenCalledTimes(1);
  });
});
```

---

## Critical Testing Checklist

### Backend Tests
- [ ] Test tenant isolation (can't access other tenant's data)
- [ ] Test soft delete (records marked deleted, not removed)
- [ ] Test signature integrity (verify hash matches)
- [ ] Test API authentication (401 without API key)
- [ ] Test validation errors (422 for invalid input)
- [ ] Mock external services (STT, LLM, S3)

### Frontend Tests
- [ ] Test component rendering
- [ ] Test user interactions (clicks, input)
- [ ] Test WebRTC state changes
- [ ] Test error states
- [ ] Mock API responses
```
