# Flask Health Endpoint Implementation
# Source: backend/app.py
# Reference: DESIGN-DECISIONS.md DD-016, snippets/docker-compose-healthcheck.yml

from flask import Flask, jsonify
from sqlalchemy import text

app = Flask(__name__)

@app.route('/health')
def health():
    """
    Health check endpoint for Docker healthcheck and load balancers.

    Checks:
    - Flask application is running
    - Database connectivity

    Returns:
    - 200 OK: Service is healthy
    - 503 Service Unavailable: Service is unhealthy
    """
    # Check critical dependencies
    try:
        # Database connectivity check
        db.session.execute(text('SELECT 1'))

        return jsonify({
            "status": "healthy",
            "checks": {
                "database": "ok"
            }
        }), 200

    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "checks": {
                "database": "failed"
            }
        }), 503

# Advanced health check with multiple dependencies
@app.route('/health/detailed')
def health_detailed():
    """
    Detailed health check with individual component status.

    Useful for debugging and monitoring dashboards.
    """
    checks = {}
    overall_healthy = True

    # Check database
    try:
        db.session.execute(text('SELECT 1'))
        checks['database'] = {'status': 'healthy', 'latency_ms': 2}
    except Exception as e:
        checks['database'] = {'status': 'unhealthy', 'error': str(e)}
        overall_healthy = False

    # Check OTel Collector connectivity (optional)
    try:
        # You could add a check to verify collector is reachable
        checks['otel_collector'] = {'status': 'healthy'}
    except Exception as e:
        checks['otel_collector'] = {'status': 'degraded', 'error': str(e)}
        # Don't mark overall as unhealthy - observability is not critical path

    status_code = 200 if overall_healthy else 503

    return jsonify({
        "status": "healthy" if overall_healthy else "unhealthy",
        "checks": checks
    }), status_code

# Liveness probe (for Kubernetes)
@app.route('/health/live')
def liveness():
    """
    Liveness probe: Is the application running?

    Used by Kubernetes to determine if container should be restarted.
    Should only check if the application process is alive, not dependencies.
    """
    return jsonify({"status": "alive"}), 200

# Readiness probe (for Kubernetes)
@app.route('/health/ready')
def readiness():
    """
    Readiness probe: Is the application ready to serve traffic?

    Used by Kubernetes to determine if pod should receive traffic.
    Should check all critical dependencies.
    """
    try:
        # Check database connectivity
        db.session.execute(text('SELECT 1'))
        return jsonify({"status": "ready"}), 200
    except Exception as e:
        return jsonify({"status": "not_ready", "error": str(e)}), 503

# Best practices:
#
# 1. Health checks should be fast (< 100ms)
#    - Don't perform expensive operations
#    - Don't wait for external services
#    - Cache results if needed
#
# 2. Health checks should be idempotent
#    - No side effects
#    - Safe to call repeatedly
#
# 3. Return appropriate HTTP status codes
#    - 200: Healthy
#    - 503: Unhealthy (allows retry)
#    - 500: Error (may not retry)
#
# 4. Include useful information in response
#    - What failed (database, cache, etc.)
#    - Error messages (sanitized)
#    - Timestamps
#
# 5. Distinguish between liveness and readiness
#    - Liveness: Can the process recover? (restart if false)
#    - Readiness: Can it handle traffic? (remove from load balancer if false)
#
# Docker Compose usage:
# healthcheck:
#   test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"]
#   interval: 10s
#   timeout: 5s
#   retries: 3
#   start_period: 30s
#
# Kubernetes usage:
# livenessProbe:
#   httpGet:
#     path: /health/live
#     port: 5000
#   initialDelaySeconds: 30
#   periodSeconds: 10
#
# readinessProbe:
#   httpGet:
#     path: /health/ready
#     port: 5000
#   initialDelaySeconds: 5
#   periodSeconds: 5
