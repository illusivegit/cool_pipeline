# Configuration Snippets

This directory contains reusable configuration snippets extracted from the OpenTelemetry Observability Lab documentation.

## Purpose

These snippets provide quick-reference code examples for common configurations without requiring you to read through full documentation files.

## Available Snippets

### Nginx Configuration
- **[nginx-cors-headers.conf](nginx-cors-headers.conf)** - CORS headers configuration for Nginx
- **[nginx-dns-resolver.conf](nginx-dns-resolver.conf)** - Docker DNS resolver configuration
- **[nginx-proxy-pass.conf](nginx-proxy-pass.conf)** - Variable-based proxy_pass configuration

### OpenTelemetry Collector
- **[otel-collector-traces.yml](otel-collector-traces.yml)** - Trace pipeline configuration
- **[otel-collector-logs.yml](otel-collector-logs.yml)** - Log pipeline with attribute hints
- **[otel-collector-memory-limiter.yml](otel-collector-memory-limiter.yml)** - Memory limiter processor

### Prometheus
- **[prometheus-scrape.yml](prometheus-scrape.yml)** - Scrape configuration for Flask backend
- **[prometheus-retention.yml](prometheus-retention.yml)** - Retention policy configuration

### Flask Backend
- **[flask-otel-tracing.py](flask-otel-tracing.py)** - OTel tracing setup
- **[flask-otel-metrics.py](flask-otel-metrics.py)** - OTel metrics setup
- **[flask-otel-logging.py](flask-otel-logging.py)** - OTel logging setup
- **[flask-middleware.py](flask-middleware.py)** - Request/response middleware with telemetry

### Grafana
- **[grafana-datasource-tempo.yml](grafana-datasource-tempo.yml)** - Tempo datasource with trace→log correlation
- **[grafana-datasource-loki.yml](grafana-datasource-loki.yml)** - Loki datasource with log→trace correlation

### Docker Compose
- **[docker-compose-healthcheck.yml](docker-compose-healthcheck.yml)** - Healthcheck configuration examples
- **[docker-compose-depends-on.yml](docker-compose-depends-on.yml)** - Service dependency configuration

## Usage

These snippets are referenced in:
- **[CONFIGURATION-REFERENCE.md](../CONFIGURATION-REFERENCE.md)** - Complete configuration guide
- **[DESIGN-DECISIONS.md](../DESIGN-DECISIONS.md)** - Architectural decisions
- **[IMPLEMENTATION-GUIDE.md](../IMPLEMENTATION-GUIDE.md)** - Implementation patterns

## Contributing

When adding new snippets:
1. Extract only the relevant configuration section
2. Add comments explaining key parameters
3. Include source file reference
4. Update this README.md index

---

**Last Updated:** October 22, 2025
