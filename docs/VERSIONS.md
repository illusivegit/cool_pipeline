# Pinned Version Registry

All image tags and software versions used in this project. The `.env` file is the
single source of truth; this document records provenance and verification dates.

| Component | Image / Version | Source | Last Verified |
|-----------|----------------|--------|---------------|
| **Flask Backend** | `python:3.11-slim` | Docker Hub | 2026-03-02 |
| **Nginx (Frontend)** | `nginx:alpine` | Docker Hub | 2026-03-02 |
| **OTel Collector** | `otel/opentelemetry-collector-contrib:0.96.0` | Docker Hub | 2026-03-02 |
| **Prometheus** | `prom/prometheus:v2.48.1` | Docker Hub | 2026-03-02 |
| **Grafana** | `grafana/grafana:10.2.3` | Docker Hub | 2026-03-02 |
| **Tempo** | `grafana/tempo:2.3.1` | Docker Hub | 2026-03-02 |
| **Loki** | `grafana/loki:2.9.3` | Docker Hub | 2026-03-02 |
| **Alertmanager** | `prom/alertmanager:v0.27.0` | Docker Hub | 2026-03-02 |
| **Node Exporter** | `prom/node-exporter:v1.7.0` | Docker Hub | 2026-03-02 |
| **Promtail** | `grafana/promtail:2.9.3` | Docker Hub | 2026-03-02 |

## Python Dependencies (backend/requirements.txt)

| Package | Version | Purpose |
|---------|---------|---------|
| Flask | 3.0.0 | Web framework |
| Flask-SQLAlchemy | 3.1.1 | ORM |
| Flask-CORS | 4.0.0 | CORS handling |
| opentelemetry-api | 1.22.0 | OTel API |
| opentelemetry-sdk | 1.22.0 | OTel SDK |
| opentelemetry-instrumentation-flask | 0.43b0 | Auto-instrumentation |
| opentelemetry-instrumentation-sqlalchemy | 0.43b0 | DB tracing |
| opentelemetry-instrumentation-logging | 0.43b0 | Log correlation |
| opentelemetry-exporter-otlp-proto-http | 1.22.0 | OTLP exporter |
| prometheus_client | 0.19.0 | Metrics library |

## Updating Versions

1. Edit `.env` with the new image tag.
2. Run `make up` to pull and deploy.
3. Run `make validate-versions` to confirm.
4. Update this table with the new version and verification date.
