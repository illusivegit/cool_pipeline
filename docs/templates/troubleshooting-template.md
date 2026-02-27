# [Component/Service] Troubleshooting: [Issue Name]

## Quick Reference

**Problem:** [One-line description]
**Severity:** 🔴 Critical / 🟡 High / 🟢 Medium / ⚪ Low
**Frequency:** Common / Occasional / Rare
**Affected Components:** [List]
**Estimated Fix Time:** X minutes/hours

---

## Problem Description

### Symptoms

**What you'll observe:**
- Symptom 1: Specific observable behavior
- Symptom 2: Error messages or logs
- Symptom 3: Performance degradation

**User Impact:**
- How users are affected
- Business impact (downtime, data loss, etc.)

### Example Error Messages

```
Error: connection refused at 192.168.1.100:5000
  at connectToServer (process.ts:712)
  at async main (index.ts:45)
```

```log
2025-10-20T12:00:00Z ERROR [component] Failed to connect to database
2025-10-20T12:00:01Z WARN  [component] Retrying connection (attempt 2/5)
```

---

## Root Cause Analysis

### What's Happening

**Technical explanation:**
[Detailed description of why this problem occurs]

**Common triggers:**
1. Trigger condition 1
2. Trigger condition 2
3. Trigger condition 3

**Why it matters:**
[Impact on system/users/operations]

### Affected Versions

- **Introduced in:** Version X.Y.Z (Phase X)
- **Fixed in:** Version A.B.C (if applicable)
- **Workaround available:** Yes/No

---

## Diagnosis Steps

### Step 1: Verify the Problem Exists

```bash
# Check service status
docker compose -p lab ps [service-name]

# Expected: "Up" status
# If "Exited" or "Restarting", proceed to Step 2
```

**What to look for:**
- Container state
- Exit codes
- Restart counts

---

### Step 2: Check Logs

```bash
# View recent logs
docker compose -p lab logs [service-name] --tail 50

# Follow logs in real-time
docker compose -p lab logs [service-name] -f
```

**Key indicators:**
- Error messages containing: "keyword1", "keyword2"
- Warning patterns: "pattern1", "pattern2"
- Absence of expected startup messages

---

### Step 3: Check Dependencies

```bash
# Verify dependent services are healthy
docker compose -p lab ps [dependency-1]
docker compose -p lab ps [dependency-2]

# Test connectivity
curl http://[service-endpoint]
```

**Dependencies to check:**
- Service A → Service B
- Network connectivity
- External resources (databases, APIs)

---

### Step 4: Check Resource Usage

```bash
# Container resource stats
docker stats [container-name]

# Disk space
df -h

# Memory pressure
free -h
```

**Thresholds:**
- CPU: > 80% sustained
- Memory: > 90% used
- Disk: > 85% full

---

## Solution

### Quick Fix (Immediate Resolution)

**If you need to restore service NOW:**

```bash
# Step 1: Stop the problematic component
docker compose -p lab stop [service-name]

# Step 2: Clear any stuck state (if applicable)
docker compose -p lab rm -f [service-name]

# Step 3: Restart
docker compose -p lab up -d [service-name]

# Step 4: Verify
docker compose -p lab logs [service-name] --tail 20
```

**Expected result:**
- Service starts successfully
- No error messages in logs
- Dependent services can connect

**Estimated time:** 2-5 minutes

---

### Permanent Fix

**To prevent this from happening again:**

#### Fix 1: [Configuration Change]

**Edit:** `path/to/config.yml`

```yaml
# Before
component:
  setting: old_value

# After
component:
  setting: new_value
  additional_setting: recommended_value
```

**Why this fixes it:**
[Explanation of how this addresses the root cause]

---

#### Fix 2: [Code/Deployment Change]

**Update:** `path/to/file.ext`

```diff
- old_code_line
+ new_code_line
```

**Apply:**
```bash
# Rebuild if code changed
docker compose -p lab build [service-name]

# Restart with new config/code
docker compose -p lab up -d [service-name]
```

---

### Verification

**Confirm the fix worked:**

1. **Service Health:**
   ```bash
   docker compose -p lab ps [service-name]
   # Status should be "Up (healthy)"
   ```

2. **Functionality Test:**
   ```bash
   curl http://localhost:PORT/health
   # Expected: {"status": "ok"}
   ```

3. **Monitor for Recurrence:**
   ```bash
   # Watch logs for 5 minutes
   docker compose -p lab logs [service-name] -f
   # Should NOT see previous error messages
   ```

4. **Metrics Check (if applicable):**
   - Open Grafana dashboard: http://localhost:3000
   - Check [specific metric]
   - Should see normal values

---

## Prevention

### Proactive Measures

**To avoid this in the future:**

1. **Configuration:**
   - Set [parameter] to [recommended value]
   - Enable [feature] for better resilience

2. **Monitoring:**
   - Alert on [metric] > [threshold]
   - Dashboard panel added: [name]

3. **Testing:**
   - Add integration test: [test name]
   - Run before deployment: `make test`

4. **Documentation:**
   - Update deployment checklist
   - Add to pre-flight verification

### Early Warning Signs

**Monitor for these indicators:**
- Metric: [metric_name] trending upward
- Log pattern: Increase in [warning message]
- Resource: Disk usage > 70%

**If you see these, investigate before issue occurs.**

---

## Related Issues

### Similar Problems
- [Issue #123](link): Related but different cause
- [Troubleshooting: Another Issue](./another-issue.md)

### Related Decisions
- [DD-X-005](../DESIGN-DECISIONS.md#dd-x-005): Why this approach was chosen

### Known Bugs
- [GitHub Issue #456](link): Upstream bug tracking

---

## Escalation Path

### When to Escalate

Escalate if:
- Quick fix doesn't work after 2 attempts
- Problem recurs within 1 hour
- Multiple components affected
- Production outage > 15 minutes

### Who to Contact

| Severity | Contact | Response Expectation |
|----------|---------|----------------------|
| 🔴 Critical | Primary on-call (self) | Immediate |
| 🟡 High | Incident log + notification | Within 1 hour |
| 🟢 Medium | Incident log entry | End of day |

### Information to Provide

**When escalating, include:**
1. Symptom timeline (when it started)
2. Steps already taken
3. Relevant logs (attach as files)
4. System state before issue (if known)
5. Impact assessment (users affected, data loss)

---

## Appendix

### Debugging Commands

```bash
# Comprehensive diagnostic dump
docker compose -p lab config > config-dump.yml
docker compose -p lab ps > container-status.txt
docker compose -p lab logs --no-color > all-logs.txt

# Network debugging
docker network inspect [network-name]
docker exec [container] ping [other-container]

# File system inspection
docker exec [container] ls -la /path/to/directory
docker exec [container] cat /path/to/config
```

### Log Analysis

**Grep patterns for common causes:**
```bash
# Connection errors
docker compose -p lab logs [service] | grep -i "connection refused"

# Memory issues
docker compose -p lab logs [service] | grep -i "out of memory"

# Configuration errors
docker compose -p lab logs [service] | grep -i "invalid config"
```

### Environment Variables to Check

| Variable | Expected Value | How to Check |
|----------|----------------|--------------|
| `VAR_NAME` | `value` | `docker exec [container] env \| grep VAR_NAME` |

---

## Document History

| Date | Change | Author |
|------|--------|--------|
| YYYY-MM-DD | Initial version | Name |
| YYYY-MM-DD | Added prevention section | Name |
| YYYY-MM-DD | Updated for Phase X | Name |

---

**Template Version:** 1.0
**Last Updated:** YYYY-MM-DD
**Verified On:** Phase X deployment
