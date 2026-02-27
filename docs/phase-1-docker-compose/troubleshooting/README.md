# Troubleshooting Guide Index

## Overview

This directory contains operational playbooks for common issues encountered when deploying and running the OpenTelemetry Observability Lab. Each guide provides:

- **Symptoms:** How to recognize the issue
- **Diagnosis:** Steps to confirm the root cause
- **Fix:** Actionable solutions
- **Prevention:** How to avoid the issue in the future

---

## Available Guides

### 📊 **[Metrics Dropdown Issue](metrics-dropdown-issue.md)**
**Problem:** Grafana metrics dropdown empty or not showing expected labels

**When to use:** After deployment when setting up Grafana dashboards

**Key Topics:**
- Prometheus label API time-range requirements
- Browser DevTools debugging methodology
- Grafana query editor troubleshooting
- Complete troubleshooting journey with hypothesis testing

**Status:** Comprehensive guide (992 lines) - includes full debugging journey

---

### 🔍 **[Trace Search Guide](trace-search-guide.md)**
**Problem:** Finding specific traces in Tempo/Grafana using TraceQL

**When to use:** When investigating issues via distributed tracing

**Key Topics:**
- TraceQL query syntax and examples
- Finding slow requests (duration filters)
- Finding errors (status filters)
- Filtering by endpoint, service, or custom attributes
- Trace ID correlation from logs

**Status:** Detailed reference guide (533 lines)

---

### 🔧 **[OTel Collector Issues](otel-collector-issues.md)**
**Problem:** OpenTelemetry Collector not receiving/exporting data, memory issues, pipeline problems

**When to use:** When telemetry data isn't flowing correctly

**Key Topics:**
- Collector not receiving data from backend
- Memory limit issues and OOM crashes
- Data not reaching Tempo/Loki
- High CPU usage
- Pipeline configuration problems
- Exporter and receiver troubleshooting
- Performance tuning

**Status:** Comprehensive guide (600+ lines)

---

### ⚠️ **[Common Issues](common-issues.md)**
**Problem:** Quick reference for frequently encountered verification issues

**When to use:** During deployment verification or post-deployment troubleshooting

**Key Topics:**
- Backend "unhealthy" status
- Nginx 502 "backend could not be resolved"
- Grafana panels show "No data"
- DB P95 Latency panel empty
- Quick fixes and diagnosis commands

**Status:** Quick reference guide (88 lines)

---

## Related Documentation

### For Deeper Troubleshooting:
- **[JOURNEY.md](../JOURNEY.md)** - Complete story of all major issues encountered during development
  - Battle #1: "Working Outside of Application Context"
  - Battle #2: The Disappearing Database
  - Battle #3: The Phantom Code Cache
  - Battle #4: The Metric Duplication Mystery
  - Battle #5: The Disappearing Metrics Dropdown

### For Architecture Understanding:
- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - System design and component relationships
- **[DESIGN-DECISIONS.md](../DESIGN-DECISIONS.md)** - Rationale for technical choices
- **[architecture/network.md](../architecture/network.md)** - Nginx proxy and DNS resolution
- **[architecture/observability.md](../architecture/observability.md)** - OTel, Prometheus, Tempo, Loki

### For Verification:
- **[VERIFICATION-GUIDE.md](../VERIFICATION-GUIDE.md)** - Step-by-step post-deployment verification and CI/CD testing

---

## Troubleshooting Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. Identify Symptoms                                       │
│     - What's broken? Container unhealthy? 502 error?        │
│     - Check docker compose -p lab ps                        │
│     - Check docker compose -p lab logs <service>            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Consult Common Issues First                             │
│     → Check common-issues.md for quick fixes                │
│     → 80% of problems have known solutions                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Use Specialized Guides                                  │
│     → Metrics/Grafana issues → metrics-dropdown-issue.md    │
│     → Trace investigation → trace-search-guide.md           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Dive into JOURNEY.md                                    │
│     → Read battle stories for similar issues                │
│     → Understand root causes and prevention                 │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Check Architecture Docs                                 │
│     → Verify your understanding of how it should work       │
│     → Review DESIGN-DECISIONS.md for context                │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Reference Commands

### Health Checks
```bash
# Check all containers
docker compose -p lab ps

# Check specific service logs
docker compose -p lab logs backend --tail=100

# Check backend health
curl http://192.168.122.250:5000/health

# Check Prometheus targets
curl -s http://192.168.122.250:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check Grafana
curl http://192.168.122.250:3000/api/health
```

### DNS/Network Checks
```bash
# Test backend DNS from frontend
docker compose -p lab exec frontend getent hosts backend

# Check network membership
docker inspect -f '{{.Name}} -> {{range .NetworkSettings.Networks}}{{.Name}}{{end}}' $(docker compose -p lab ps -q)

# Test backend from frontend
docker compose -p lab exec frontend wget -qO- http://backend:5000/api/tasks
```

### Metrics Checks
```bash
# View backend metrics
curl http://192.168.122.250:5000/metrics

# Check if Prometheus is scraping
curl -s http://192.168.122.250:9090/api/v1/targets | grep flask-backend

# Generate test traffic
for i in {1..10}; do curl http://192.168.122.250:8080/api/tasks; sleep 1; done
```

### Trace Checks
```bash
# Check Tempo is running
curl http://192.168.122.250:3200/ready

# Search traces via Grafana
# Open: http://192.168.122.250:3000 → Explore → Tempo
# Query: {duration > 500ms}
```

---

## Contributing

Found a new issue and solved it? Add a guide:

1. Use the format from existing guides (Symptoms → Diagnosis → Fix → Prevention)
2. Include actual commands that can be copy-pasted
3. Link to related architecture docs
4. Update this README.md index

---

**Last Updated:** October 22, 2025
**Total Guides:** 4
**Coverage:** Deployment verification, metrics, tracing, networking, OTel Collector
