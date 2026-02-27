# Docker Build & Runtime Optimization

## Overview

This guide covers Docker image optimization, build caching strategies, and runtime performance tuning for the OpenTelemetry Observability Lab.

**Related:** [Deployment Architecture](deployment.md), [JOURNEY.md Battle #3](../JOURNEY.md)

---

## Table of Contents

- [Build Optimization](#build-optimization)
- [Layer Caching](#layer-caching)
- [Multi-Stage Builds](#multi-stage-builds)
- [BuildKit Features](#buildkit-features)
- [Image Size Optimization](#image-size-optimization)
- [Runtime Optimization](#runtime-optimization)
- [Development vs Production](#development-vs-production)
- [Common Issues](#common-issues)

---

## Build Optimization

### Current Dockerfile (Backend)

**File:** `backend/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /app/data

EXPOSE 5000

CMD ["python", "app.py"]
```

**What's Good:**
- ✅ Uses slim base image (smaller size)
- ✅ Copies `requirements.txt` before code (better caching)
- ✅ Uses `--no-cache-dir` to reduce image size

**What Could Be Better:**
- ⚠️ No multi-stage build
- ⚠️ Copies all files (including `.pyc`, `__pycache__`)
- ⚠️ No BuildKit cache mounts
- ⚠️ No security scanning

---

## Layer Caching

### How Docker Caching Works

Docker caches each layer. If a layer changes, **all subsequent layers are invalidated**.

**Bad Layer Order:**
```dockerfile
FROM python:3.11-slim
COPY . .  # ❌ Copies everything - cache busts on any change
RUN pip install -r requirements.txt  # ❌ Reinstalls every time
```

**Good Layer Order:**
```dockerfile
FROM python:3.11-slim
COPY requirements.txt .  # ✅ Only invalidates if dependencies change
RUN pip install -r requirements.txt
COPY . .  # ✅ Code changes don't bust pip install cache
```

### Optimizing Layer Order

**Principle:** Order from least-frequently-changing to most-frequently-changing.

```dockerfile
# 1. Base image (rarely changes)
FROM python:3.11-slim

# 2. System packages (rarely change)
RUN apt-get update && apt-get install -y \
    some-package \
    && rm -rf /var/lib/apt/lists/*

# 3. Dependencies (change occasionally)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Application code (changes frequently)
COPY . .
```

### .dockerignore File

**Create `.dockerignore` to exclude unnecessary files:**

```
# Git
.git
.gitignore

# Python
__pycache__
*.pyc
*.pyo
*.pyd
.Python
*.so
*.egg
*.egg-info
dist
build
.pytest_cache
.coverage

# IDE
.vscode
.idea
*.swp
*.swo
*~

# Documentation
README.md
docs/
*.md

# Development
.env
.env.local
docker-compose*.yml
Dockerfile*

# Testing
tests/
.tox/

# CI/CD
.github/
.gitlab-ci.yml
Jenkinsfile
```

**Impact:**
- Smaller build context (faster upload to Docker daemon)
- Fewer layers invalidated on unrelated file changes
- Faster builds

---

## Multi-Stage Builds

### Why Multi-Stage Builds?

Separate build environment from runtime environment:
- **Build stage:** Includes compilers, dev tools
- **Runtime stage:** Only includes runtime dependencies
- **Result:** Smaller images, better security

### Example: Optimized Backend Dockerfile

```dockerfile
# Stage 1: Builder
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

# Copy only the wheels from builder
COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .

# Install from wheels (no compilation needed)
RUN pip install --no-cache /wheels/* \
    && rm -rf /wheels

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Copy application code
COPY --chown=appuser:appuser . .

# Create data directory
RUN mkdir -p /app/data

EXPOSE 5000

CMD ["python", "app.py"]
```

**Benefits:**
- Smaller final image (no gcc, build tools)
- Faster deployments (less to transfer)
- Better security (fewer attack surfaces)

**Size comparison:**
- Original: ~400MB
- Multi-stage: ~250MB

---

## BuildKit Features

### Enable BuildKit

```bash
# Export environment variable
export DOCKER_BUILDKIT=1

# Or in docker-compose.yml
version: "3.8"
services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
      args:
        BUILDKIT_INLINE_CACHE: 1
```

### BuildKit Cache Mounts

**Dramatically faster builds by caching package managers:**

```dockerfile
# Syntax directive MUST be first line
# syntax=docker/dockerfile:1

FROM python:3.11-slim

WORKDIR /app

# Cache pip downloads
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip

COPY requirements.txt .

# Mount pip cache during install
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

COPY . .

CMD ["python", "app.py"]
```

**Benefits:**
- `pip` doesn't re-download packages on every build
- Rebuilds are 10-50x faster
- Cache persists between builds

### BuildKit Secret Mounts

**For builds that need secrets (API tokens, SSH keys):**

```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.11-slim

# Mount secret during build (not stored in image)
RUN --mount=type=secret,id=pip_token \
    pip config set global.index-url https://pypi.org/simple/ \
    && pip install -r requirements.txt
```

**Usage:**
```bash
docker build --secret id=pip_token,src=.pip_token .
```

**Security:** Secret is NOT stored in any layer!

---

## Image Size Optimization

### Technique 1: Use Slim/Alpine Base Images

```dockerfile
# Large (1GB+)
FROM python:3.11

# Better (400MB)
FROM python:3.11-slim

# Smallest (50MB, but compatibility issues)
FROM python:3.11-alpine
```

**Recommendation:** Use `slim` for Python (Alpine has musl libc compatibility issues)

### Technique 2: Combine RUN Commands

❌ **Bad (creates multiple layers):**
```dockerfile
RUN apt-get update
RUN apt-get install -y gcc
RUN pip install -r requirements.txt
RUN apt-get remove -y gcc
```

✅ **Good (one layer):**
```dockerfile
RUN apt-get update && \
    apt-get install -y gcc && \
    pip install -r requirements.txt && \
    apt-get remove -y gcc && \
    rm -rf /var/lib/apt/lists/*
```

### Technique 3: Clean Up in Same Layer

```dockerfile
RUN apt-get update && apt-get install -y \
    package1 \
    package2 \
    && rm -rf /var/lib/apt/lists/*  # ✅ Clean up in same RUN
```

### Technique 4: Use --no-install-recommends

```dockerfile
# Without flag: Installs 150 packages
RUN apt-get install -y python3

# With flag: Installs 30 packages
RUN apt-get install -y --no-install-recommends python3
```

### Technique 5: Remove Build Dependencies

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && pip install -r requirements.txt \
    && apt-get purge -y --auto-remove gcc \
    && rm -rf /var/lib/apt/lists/*
```

---

## Runtime Optimization

### Resource Limits

**Set memory and CPU limits:**

```yaml
# docker-compose.yml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Healthchecks

**Add healthchecks for faster failure detection:**

```yaml
services:
  backend:
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
```

### Read-Only Filesystem

**Improve security with read-only root filesystem:**

```yaml
services:
  backend:
    read_only: true
    volumes:
      - ./data:/app/data  # Only this is writable
    tmpfs:
      - /tmp  # Temporary files
```

### Non-Root User

```dockerfile
RUN useradd -m -u 1000 appuser
USER appuser
```

**Benefits:**
- Security (principle of least privilege)
- Prevents accidental system modification

---

## Development vs Production

### Development Dockerfile

**File:** `backend/Dockerfile.dev`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dev dependencies
RUN pip install --no-cache-dir debugpy pytest pytest-cov black flake8

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Don't copy code (use volume mount)

# Development environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_ENV=development

# Enable debugger
EXPOSE 5000 5678

CMD ["python", "-m", "debugpy", "--listen", "0.0.0.0:5678", "--wait-for-client", "app.py"]
```

**docker-compose.dev.yml:**
```yaml
services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.dev
    volumes:
      - ./backend:/app  # Live code reload
    environment:
      - FLASK_ENV=development
```

### Production Dockerfile

**File:** `backend/Dockerfile.prod`

```dockerfile
# syntax=docker/dockerfile:1

# Builder stage
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .

RUN pip install --no-cache /wheels/* && rm -rf /wheels

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

USER appuser

COPY --chown=appuser:appuser . .

RUN mkdir -p /app/data

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_ENV=production

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "app:app"]
```

---

## Common Issues

### Issue: "Code changes not reflected"

**Symptom:** Modified code but container still runs old version

**From JOURNEY.md Battle #3:**

**Cause:** Docker layer cache serving old code layer

**Solutions:**

1. **Force rebuild:**
   ```bash
   docker compose -p lab build --no-cache backend
   docker compose -p lab up -d backend
   ```

2. **Use development mode with volume mounts:**
   ```yaml
   services:
     backend:
       volumes:
         - ./backend:/app  # Live code updates
   ```

3. **Set PYTHONDONTWRITEBYTECODE:**
   ```dockerfile
   ENV PYTHONDONTWRITEBYTECODE=1
   ```
   Prevents Python bytecode caching that can mask changes.

### Issue: "Slow build times"

**Solutions:**

1. **Enable BuildKit:**
   ```bash
   export DOCKER_BUILDKIT=1
   ```

2. **Use cache mounts:**
   ```dockerfile
   RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
   ```

3. **Optimize layer order (dependencies before code):**
   ```dockerfile
   COPY requirements.txt .
   RUN pip install -r requirements.txt
   COPY . .  # Changed frequently
   ```

4. **Use .dockerignore to reduce context size**

### Issue: "Large image sizes"

**Solutions:**

1. **Use slim base images:**
   ```dockerfile
   FROM python:3.11-slim  # Not python:3.11
   ```

2. **Multi-stage builds:**
   ```dockerfile
   FROM python:3.11 AS builder
   # ... build steps ...
   FROM python:3.11-slim
   COPY --from=builder /app /app
   ```

3. **Clean up in same layer:**
   ```dockerfile
   RUN apt-get update && apt-get install -y gcc && pip install -r requirements.txt && apt-get remove -y gcc
   ```

---

## Performance Benchmarks

### Build Time Comparison

| Approach | First Build | Rebuild (no changes) | Rebuild (code change) |
|----------|-------------|----------------------|-----------------------|
| **Basic** | 120s | 5s | 115s |
| **With .dockerignore** | 90s | 5s | 85s |
| **BuildKit + cache mounts** | 90s | 3s | 8s |
| **Multi-stage** | 100s | 3s | 8s |

### Image Size Comparison

| Dockerfile | Image Size | Layers |
|------------|-----------|--------|
| **Basic (full image)** | 1.2GB | 12 |
| **Slim base** | 450MB | 10 |
| **Multi-stage** | 280MB | 8 |
| **Multi-stage + optimized** | 220MB | 6 |

---

## Best Practices Checklist

### Build Optimization
- [ ] Use `DOCKER_BUILDKIT=1`
- [ ] Create `.dockerignore` file
- [ ] Order layers from least-to-most frequently changed
- [ ] Use BuildKit cache mounts for package managers
- [ ] Combine related `RUN` commands
- [ ] Clean up in the same layer

### Security
- [ ] Use non-root user
- [ ] Use multi-stage builds (no build tools in final image)
- [ ] Don't hardcode secrets in Dockerfile
- [ ] Use `--no-install-recommends` for apt packages
- [ ] Scan images with `docker scan` or Trivy

### Size Optimization
- [ ] Use slim or alpine base images
- [ ] Remove build dependencies after use
- [ ] Use `--no-cache-dir` for pip
- [ ] Clean up apt cache (`rm -rf /var/lib/apt/lists/*`)
- [ ] Use multi-stage builds

### Development
- [ ] Separate dev and prod Dockerfiles
- [ ] Use volume mounts for live reloading
- [ ] Set `PYTHONDONTWRITEBYTECODE=1`
- [ ] Set `PYTHONUNBUFFERED=1`
- [ ] Include dev tools (debugpy, pytest)

### Production
- [ ] Use production WSGI server (gunicorn)
- [ ] Set resource limits (CPU, memory)
- [ ] Configure healthchecks
- [ ] Use read-only filesystem where possible
- [ ] Set restart policy (`restart: unless-stopped`)

---

## References

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [JOURNEY.md Battle #3](../JOURNEY.md) - The Phantom Code Cache story

---

**Last Updated:** 2025-10-22
**Version:** 1.0
**Related Files:**
- [deployment.md](deployment.md) - Deployment architecture
- [JOURNEY.md](../JOURNEY.md) - Battle #3: The Phantom Code Cache
- [IMPLEMENTATION-GUIDE.md](../IMPLEMENTATION-GUIDE.md) - Lesson #2: Docker Caching
