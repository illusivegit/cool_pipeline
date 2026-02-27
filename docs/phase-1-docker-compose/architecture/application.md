# Application Architecture

## Overview

This document describes the architecture of the full-stack task manager application deployed as part of the OpenTelemetry Observability Lab. The application demonstrates comprehensive observability instrumentation across three tiers: frontend, backend, and data storage.

The application is designed specifically for observability learning and testing, featuring built-in endpoints for error simulation, performance testing, and load generation.

## Application Stack

The deployed application is a **full-stack task manager** instrumented for observability:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     APPLICATION DEPLOYMENT (VM)                         │
│  IP: 192.168.122.250                                                    │
│  Network: otel-network (Docker bridge)                                  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        FRONTEND TIER                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Nginx (nginx:alpine) - Port 8080 (host) → 80 (container)         │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Static File Serving:                                       │  │  │
│  │  │  • /usr/share/nginx/html/index.html (Task Manager UI)       │  │  │
│  │  │  • /usr/share/nginx/html/app.js (Dynamic API calls)         │  │  │
│  │  │  • /usr/share/nginx/html/styles.css (Responsive design)     │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Reverse Proxy (Solves CORS):                               │  │  │
│  │  │  location /api/ {                                           │  │  │
│  │  │    resolver 127.0.0.11 ipv6=off valid=30s;  # Docker DNS    │  │  │
│  │  │    set $backend_upstream http://backend:5000;               │  │  │
│  │  │    proxy_pass $backend_upstream;  # Variable-based routing  │  │  │
│  │  │    proxy_set_header X-Real-IP $remote_addr;                 │  │  │
│  │  │  }                                                          │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  Dynamic Link Generation (app.js):                                │  │
│  │  • Grafana: http://${window.location.hostname}:3000               │  │
│  │  • Prometheus: http://${window.location.hostname}:9090            │  │
│  │  → Works on localhost, VM IP, or cloud hostname                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP /api/* → backend:5000/api/*
┌─────────────────────────────────────────────────────────────────────────┐
│                         BACKEND TIER                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Flask API (Python 3.12) - Port 5000                              │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Application Framework:                                     │  │  │
│  │  │  • Flask 3.0 - Lightweight web framework                    │  │  │
│  │  │  • Flask-SQLAlchemy 3.1.1 - ORM layer                       │  │  │
│  │  │  • Flask-CORS - Cross-origin support                        │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  RESTful API Endpoints:                                     │  │  │
│  │  │  • GET    /api/tasks         - List all tasks               │  │  │
│  │  │  • GET    /api/tasks/:id     - Get single task              │  │  │
│  │  │  • POST   /api/tasks         - Create task                  │  │  │
│  │  │  • PUT    /api/tasks/:id     - Update task                  │  │  │
│  │  │  • DELETE /api/tasks/:id     - Delete task                  │  │  │
│  │  │  • GET    /api/simulate-slow - Performance testing          │  │  │
│  │  │  • GET    /api/simulate-error - Error injection             │  │  │
│  │  │  • POST   /api/smoke/db      - DB load generation           │  │  │
│  │  │  • GET    /health            - Health check                 │  │  │
│  │  │  • GET    /metrics           - Prometheus metrics           │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Instrumentation Layer (3 Pillars):                         │  │  │
│  │  │                                                             │  │  │
│  │  │  ① TRACES (OpenTelemetry SDK)                              [] [] []   
│  │  │    • FlaskInstrumentor: HTTP request/response spans         │  │  │
│  │  │    • SQLAlchemyInstrumentor: DB query spans                 │  │  │
│  │  │    • LoggingInstrumentor: Log correlation                   │  │  │
│  │  │    • OTLP Exporter → otel-collector:4318/v1/traces          │  │  │
│  │  │    • Resource attributes: service.name, version, env        │  │  │
│  │  │                                                             │  │  │
│  │  │  ② METRICS (HYBRID: Prometheus Client + OTel SDK)          [] [] []  
│  │  │    Prometheus Client (scraped at /metrics):                 │  │  │
│  │  │    • http_requests_total (Counter)                          │  │  │
│  │  │    • http_request_duration_seconds (Histogram)              │  │  │
│  │  │    • http_errors_total (Counter)                            │  │  │
│  │  │    • db_query_duration_seconds (Histogram)                  │  │  │
│  │  │                                                             │  │  │
│  │  │    OpenTelemetry Metrics (for demonstration):               │  │  │
│  │  │    • database_query_duration_seconds (Histogram)            │  │  │
│  │  │                                                             │  │  │
│  │  │  ③ LOGS (OpenTelemetry SDK)                                [] [] []   
│  │  │    • Structured JSON logging (python-json-logger)           │  │  │
│  │  │    • Automatic trace_id/span_id injection                   │  │  │
│  │  │    • OTLP Exporter → otel-collector:4318/v1/logs            │  │  │
│  │  │    • LoggingHandler for OTLP export                         │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Critical Design Fix: Application Context                   │  │  │
│  │  │  Problem: SQLAlchemy event listeners caused RuntimeError    │  │  │
│  │  │  Solution:                                                  │  │  │
│  │  │    def _before_cursor_execute(...):  # Plain function       │  │  │
│  │  │        # Record query start time                            │  │  │
│  │  │                                                             │  │  │
│  │  │    with app.app_context():  # Activate Flask context        │  │  │
│  │  │        event.listen(db.engine, 'before_cursor_execute', ...)│  │  │
│  │  │        event.listen(db.engine, 'after_cursor_execute', ...) │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ SQLAlchemy ORM
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA TIER                                       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  SQLite Database                                                  │  │
│  │  Path: /app/data/tasks.db (absolute path - critical!)             │  │
│  │  Volume: backend-data (named volume for persistence)              │  │
│  │                                                                   │  │
│  │  Schema:                                                          │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  Table: tasks                                               │  │  │
│  │  │  • id: INTEGER PRIMARY KEY AUTOINCREMENT                    │  │  │
│  │  │  • title: VARCHAR(200) NOT NULL                             │  │  │
│  │  │  • description: TEXT                                        │  │  │
│  │  │  • completed: BOOLEAN DEFAULT 0                             │  │  │
│  │  │  • created_at: DATETIME DEFAULT CURRENT_TIMESTAMP           │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                   │  │
│  │  Instrumentation:                                                 │  │
│  │  • Every query captured by SQLAlchemyInstrumentor                 │  │
│  │  • Query duration tracked via event listeners:                    │  │
│  │    - before_cursor_execute: Start timer                           │  │
│  │    - after_cursor_execute: Calculate duration, emit metric        │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Architecture Wins

### 1. Nginx Reverse Proxy (Not CORS Headers)
- **Problem:** Browser CORS blocking `http://vm:8080 → http://vm:5000` API calls
- **Option A (Rejected):** Add CORS headers to Flask (complexity, preflight requests)
- **Option B (Chosen):** Nginx `/api/*` proxy to `backend:5000`
- **Result:** Same-origin requests, no CORS complexity, production-ready pattern

### 2. Dynamic DNS Resolution in Nginx
- **Problem:** Cached IP for `backend` became stale when container restarted → 502 errors
- **Solution:** `resolver 127.0.0.11` + variable-based `proxy_pass`
- **Magic:** Nginx re-resolves DNS on every request, eliminates stale cache

### 3. Healthcheck-Driven Startup Ordering
- **Problem:** Frontend started before backend → DNS lookup failed → 502 errors
- **Solution:** Backend Python healthcheck + `depends_on: service_healthy`
- **Result:** Frontend waits until backend is truly ready, not just "started"

## Implementation Details

### Frontend (Nginx + Vanilla JavaScript)

**Technology Stack:**
- Nginx Alpine (static file server + reverse proxy)
- Vanilla JavaScript (no framework dependencies)
- CSS3 for responsive design

**Key Features:**
- Dynamic link generation for observability tools (Grafana, Prometheus, Tempo)
- RESTful API consumption via Fetch API
- Toast notifications for user feedback
- Performance timing via `performance.now()` for client-side metrics
- Testing utilities: error simulation, slow requests, bulk operations, database smoke tests

**API Integration:**
All API calls use the `/api` prefix which Nginx proxies to `backend:5000`:
```javascript
const API_URL = '/api';
fetch(`${API_URL}/tasks`, {...})
```

### Backend (Flask + OpenTelemetry)

**Technology Stack:**
- Flask 3.0 (web framework)
- Flask-SQLAlchemy 3.1.1 (ORM)
- Flask-CORS (cross-origin support)
- OpenTelemetry SDK (traces, logs)
- Prometheus Client (metrics)

**Key Implementation Patterns:**

1. **HYBRID Metrics Strategy:**
   - Prometheus Client exports metrics at `/metrics` endpoint for scraping
   - OpenTelemetry Metrics SDK used for database query duration (demonstration)
   - Rationale: Prometheus scraping is primary; OTel metrics show SDK capabilities

2. **Trace Context Propagation:**
   - FlaskInstrumentor automatically creates spans for HTTP requests
   - SQLAlchemyInstrumentor creates child spans for database queries
   - Custom spans added for business logic operations

3. **Structured Logging with Correlation:**
   - JSON formatted logs using `python-json-logger`
   - Automatic trace_id and span_id injection for correlation
   - Dual handlers: StreamHandler (stdout) + OTel LoggingHandler (OTLP export)

4. **Database Query Metrics:**
   - SQLAlchemy event listeners (`before_cursor_execute`, `after_cursor_execute`)
   - Calculates query duration and emits to Prometheus histogram
   - Labels by operation type (SELECT, INSERT, UPDATE, DELETE)

### Database (SQLite)

**Schema Definition:**
```python
class Task(db.Model):
    __tablename__ = 'tasks'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=True)
    completed = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
```

**Storage:**
- Path: `/app/data/tasks.db` (must be absolute for SQLite)
- Volume: `backend-data` (Docker named volume for persistence)
- Automatic schema creation via `db.create_all()` in app context

## Docker Compose Configuration

### Service Definitions

**Backend Service:**
```yaml
backend:
  build: ./backend
  container_name: flask-backend
  ports:
    - "5000:5000"
  environment:
    - OTEL_SERVICE_NAME=flask-backend
    - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
    - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
  volumes:
    - ./backend:/app
    - backend-data:/app/data
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/metrics', timeout=2).read()"]
    interval: 10s
    timeout: 3s
    retries: 5
    start_period: 5s
  depends_on:
    - otel-collector
```

**Frontend Service:**
```yaml
frontend:
  image: nginx:alpine
  container_name: frontend
  ports:
    - "8080:80"
  volumes:
    - ./frontend:/usr/share/nginx/html:ro
    - ./frontend/default.conf:/etc/nginx/conf.d/default.conf:ro
  depends_on:
    backend:
      condition: service_healthy
```

### Network Configuration
- Network: `otel-network` (bridge driver)
- DNS: Docker's embedded DNS server at `127.0.0.11`
- Service discovery: Container names resolve to IP addresses

## API Reference

### Task Management

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/tasks` | List all tasks | - | `{tasks: [...], count: N}` |
| GET | `/api/tasks/:id` | Get single task | - | `{id, title, description, completed, created_at}` |
| POST | `/api/tasks` | Create task | `{title, description?, completed?}` | Created task (201) |
| PUT | `/api/tasks/:id` | Update task | `{title?, description?, completed?}` | Updated task |
| DELETE | `/api/tasks/:id` | Delete task | - | `{message: "Task deleted successfully"}` |

### Observability Testing

| Method | Endpoint | Description | Parameters |
|--------|----------|-------------|------------|
| GET | `/api/simulate-error` | Trigger 500 error | - |
| GET | `/api/simulate-slow` | Simulate latency | `delay` (seconds, default: 2.0) |
| POST | `/api/smoke/db` | Generate DB load | `ops` (count), `type` (read/write/rw) |
| GET | `/health` | Health check | - |
| GET | `/metrics` | Prometheus metrics | - |

## Observability Integration

### Metrics Export
- **Source:** Prometheus Client library
- **Endpoint:** `http://flask-backend:5000/metrics`
- **Scraper:** Prometheus (configured in `prometheus.yml`)
- **Frequency:** 15-second scrape interval

### Traces Export
- **Source:** OpenTelemetry SDK
- **Protocol:** OTLP/HTTP
- **Endpoint:** `http://otel-collector:4318/v1/traces`
- **Backend:** Grafana Tempo (via OTel Collector)

### Logs Export
- **Source:** OpenTelemetry SDK + LoggingHandler
- **Protocol:** OTLP/HTTP
- **Endpoint:** `http://otel-collector:4318/v1/logs`
- **Backend:** Grafana Loki (via OTel Collector)

## Known Issues and Solutions

### SQLAlchemy Event Listener Context Error
**Issue:** Runtime error when registering SQLAlchemy event listeners outside Flask app context

**Solution:** Wrap event listener registration in `with app.app_context():`
```python
with app.app_context():
    event.listen(db.engine, "before_cursor_execute", _before_cursor_execute)
    event.listen(db.engine, "after_cursor_execute", _after_cursor_execute)
```

### Nginx Backend DNS Caching
**Issue:** Nginx caches backend IP, causing 502 errors after container restart

**Solution:** Dynamic DNS resolution with resolver directive and variable-based proxy_pass
```nginx
resolver 127.0.0.11 ipv6=off valid=30s;
set $backend_upstream http://backend:5000;
proxy_pass $backend_upstream;
```

### Frontend Startup Race Condition
**Issue:** Frontend container starts before backend is ready to accept requests

**Solution:** Health check dependency in docker-compose.yml
```yaml
depends_on:
  backend:
    condition: service_healthy
```

## Performance Characteristics

### Expected Latencies
- **Task List (GET /api/tasks):** < 50ms for < 100 tasks
- **Task Create (POST /api/tasks):** < 100ms
- **Database Query:** < 10ms (SQLite in-memory operations)
- **Simulate Slow:** Configurable (default 2 seconds)

### Metrics Collection Overhead
- **Prometheus Scrape:** ~5ms per scrape (15s interval)
- **OTel Trace Export:** Batched, negligible impact
- **OTel Log Export:** Batched, < 1ms per log entry

---

**Document Version:** 1.0
**Last Updated:** 2025-10-22
**Maintained By:** OpenTelemetry Observability Lab
