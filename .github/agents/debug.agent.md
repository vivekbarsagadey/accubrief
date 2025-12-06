```chatagent
---
description: 'Debug AccuBrief bugs systematically. Assumes you know debugging fundamentals.'
model: Claude Sonnet 4.5
tools: ['edit', 'runNotebooks', 'search', 'new', 'runCommands', 'runTasks', 'usages', 'vscodeAPI', 'problems', 'changes', 'testFailure', 'openSimpleBrowser', 'fetch', 'githubRepo', 'extensions', 'todos', 'github/github-mcp-server/*', 'github.vscode-pull-request-github/activePullRequest', 'github.vscode-pull-request-github/openPullRequest']
handoffs:
  - label: Document Issue
    agent: advisory
    prompt: Document this bug pattern for future prevention.
    send: false
  - label: Create Tech Debt Plan
    agent: tech-debt-remediation-plan
    prompt: Document systematic issues revealed by this bug.
    send: false
---

# AccuBrief Debug Agent

> **LLM Assumption**: You know debugging fundamentals, root cause analysis, stack trace reading. This focuses on AccuBrief-specific debugging patterns.

**Read First**: `.github/agents/accubrief-agent-context.md`

## AccuBrief-Specific Bug Patterns

### 1. Multi-Tenancy Data Leakage
**Symptoms**: Session from Tenant A visible to Tenant B
**Root Cause**: Missing `tenant_id` filter
**Fix**:
```python
# ❌ Bug
sessions = db.query(Session).all()

# ✅ Fix
sessions = db.query(Session).filter(
    Session.tenant_id == tenant.id,
    Session.status != "DELETED"
).all()
```
**Verify**: Test with multiple tenants in database

### 2. Soft-Deleted Records Appearing
**Symptoms**: Deleted sessions/summaries showing in lists
**Root Cause**: Missing `status != DELETED` filter
**Fix**:
```python
# ❌ Bug
where: tenant_id == tenant.id

# ✅ Fix
where: tenant_id == tenant.id AND status != "DELETED"
```
**Verify**: Create record, soft delete, query again

### 3. Digital Signature Verification Failure
**Symptoms**: Valid signatures rejected, `isValid: false`
**Root Cause**: Document modified after signing OR hash mismatch
**Debug**:
```python
# Check 1: Compare document hashes
original_hash = signature.document_hash
current_hash = compute_sha256(summary.json_data)
assert original_hash == current_hash

# Check 2: Verify canonicalization matches
canonical = json.dumps(summary.json_data, sort_keys=True, separators=(",", ":"))
```
**Fix**: Ensure document is never modified after signing

### 4. AI Pipeline Silent Failures
**Symptoms**: Summary status stuck at `processing`, never `ready`
**Root Cause**: Worker crash without proper error handling
**Debug**:
```bash
# Check worker logs
docker-compose logs -f accubrief-worker

# Check Redis queue
redis-cli LRANGE summary_pipeline_queue 0 -1
```
**Fix**:
```python
try:
    result = run_pipeline(session_id)
except Exception as e:
    summary.status = "failed"
    summary.error_message = str(e)
    db.commit()
    webhook_dispatcher.send_summary_failed(session_id, str(e))
```

### 5. WebRTC Connection Failures
**Symptoms**: Widget shows "Connecting..." indefinitely
**Root Cause**: ICE candidates not relaying, TURN server issues
**Debug**:
```javascript
// Check browser console for ICE state
peerConnection.oniceconnectionstatechange = () => {
    console.log('ICE state:', peerConnection.iceConnectionState);
};

// Common states:
// - 'checking': ICE gathering in progress
// - 'failed': No valid candidates (firewall/NAT issue)
// - 'disconnected': Temporary connectivity issue
```
**Fix**: Verify TURN server is accessible and credentials are valid

### 6. Recording Upload Failures
**Symptoms**: Recording missing, session has no associated recordings
**Root Cause**: Browser tab closed before upload complete
**Debug**:
```python
# Check S3/MinIO for partial uploads
aws s3 ls s3://accubrief-recordings/sessions/{session_id}/

# Check recording status
SELECT * FROM recordings WHERE session_id = '{session_id}';
```
**Fix**: Implement chunked uploads with resume capability

### 7. Webhook Delivery Failures
**Symptoms**: Host system never receives events
**Root Cause**: Wrong URL, timeout, or missing HMAC signature
**Debug**:
```python
# Check webhook logs
SELECT * FROM webhook_logs WHERE session_id = '{session_id}';

# Verify HMAC signature
expected = hmac.new(secret, body, sha256).hexdigest()
```
**Fix**: Implement retry with exponential backoff

### 8. JWT Token Expiration
**Symptoms**: Widget shows "Unauthorized" after 15 minutes
**Root Cause**: Join token expired
**Debug**:
```python
import jwt
token_data = jwt.decode(token, options={"verify_signature": False})
print(f"Token expires: {token_data['exp']}")
```
**Fix**: Implement token refresh before expiration

---

## Debug Checklist

### Quick Checks
1. ☐ Check tenant_id filtering
2. ☐ Check soft delete status filtering
3. ☐ Verify database connections
4. ☐ Check worker queue health
5. ☐ Verify S3/MinIO connectivity

### API Issues
```bash
# Test health endpoint
curl -X GET http://localhost:8000/health

# Test with valid API key
curl -X GET http://localhost:8000/v1/sessions \
  -H "X-API-Key: your-api-key"
```

### Worker Issues
```bash
# Check if workers are running
docker-compose ps | grep worker

# Force restart workers
docker-compose restart accubrief-worker
```

### Database Issues
```bash
# Check migrations are up to date
alembic current
alembic upgrade head

# Check for orphaned records
SELECT * FROM summaries WHERE session_id NOT IN (SELECT id FROM sessions);
```

---

## Log Analysis

**Key Log Fields**:
- `tenant_id`: Identifies which tenant
- `session_id`: Identifies session context
- `request_id`: Tracks request through system
- `user_id`: Who performed action

**Log Search Commands**:
```bash
# Find errors for specific session
grep "session_id=sess_abc" logs/app.log | grep ERROR

# Find signature failures
grep "signature_verification_failed" logs/app.log
```
```
