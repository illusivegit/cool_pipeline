import os
import logging
import time
from datetime import datetime
from time import perf_counter
from flask import Flask, jsonify, request, Response, g
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import event
from pythonjsonlogger import jsonlogger
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, Counter, Histogram

# OpenTelemetry Imports
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.trace import Status, StatusCode
from opentelemetry._logs import set_logger_provider

# Configure structured logging with JSON formatter
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(
    '%(asctime)s %(name)s %(levelname)s %(message)s %(trace_id)s %(span_id)s'
)
logHandler.setFormatter(formatter)
logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Initialize OpenTelemetry
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "flask-backend"),
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})

# Setup Tracing
tracer_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/traces"
)
span_processor = BatchSpanProcessor(otlp_trace_exporter)
tracer_provider.add_span_processor(span_processor)
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)

# Setup Metrics - OTel meter for internal instrumentation only (span attributes)
# NOTE: No OTLP export - we use prometheus_client for all Prometheus metrics
meter_provider = MeterProvider(resource=resource)
metrics.set_meter_provider(meter_provider)
meter = metrics.get_meter(__name__)

# Setup Logs - Export to OTLP
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)

otlp_log_exporter = OTLPLogExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector:4318')}/v1/logs",
    timeout=5
)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(otlp_log_exporter))

# Bridge stdlib logging to OpenTelemetry logs SDK
otel_log_handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().addHandler(otel_log_handler)

# NOTE: OTel metrics for Prometheus removed to eliminate duplication.
# We now use ONLY prometheus_client metrics exposed at /metrics endpoint.
# OTel still handles traces (Tempo) and logs (Loki) via OTLP collector.

# Database query duration tracking (OTel-only, for span attributes)
database_query_duration = meter.create_histogram(
    name="database_query_duration_seconds",
    description="Database query duration in seconds",
    unit="s"
)

# Prometheus Client Metrics (exported via /metrics endpoint for scraping)
# These are the ONLY metrics sent to Prometheus (no duplication)
prom_http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

prom_http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'status_code']
)

prom_http_errors_total = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['method', 'endpoint', 'status_code']
)

# Histogram for SQLite query latency (seconds)
# Buckets chosen for typical SQLite operations (2ms to 2s range)
prom_db_query_duration_seconds = Histogram(
    'db_query_duration_seconds',
    'SQLite query duration in seconds',
    ['operation'],  # SELECT/INSERT/UPDATE/DELETE
    buckets=(0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2)
)

# Initialize Flask App
app = Flask(__name__)
CORS(app)

# Database Configuration - Use absolute path for SQLite
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:////app/data/tasks.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Instrument Flask and Logging (safe outside app context)
FlaskInstrumentor().instrument_app(app)
LoggingInstrumentor().instrument(set_logging_format=True)

# Database Model
class Task(db.Model):
    __tablename__ = 'tasks'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=True)
    completed = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'completed': self.completed,
            'created_at': self.created_at.isoformat()
        }

# SQLAlchemy event listener functions for Prometheus DB query duration tracking
# NOTE: Defined as plain functions (not decorators) to avoid "Working outside of application context" error
# These will be attached to db.engine inside the app context block below
def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    """Record query start time before execution"""
    context._query_start_time = perf_counter()

def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    """Record query duration after execution and classify operation type"""
    try:
        started = context._query_start_time
    except AttributeError:
        return

    elapsed = perf_counter() - started

    # Classify operation type from SQL statement
    s = statement.lstrip().upper()
    op = "SELECT"
    if s.startswith("INSERT"):
        op = "INSERT"
    elif s.startswith("UPDATE"):
        op = "UPDATE"
    elif s.startswith("DELETE"):
        op = "DELETE"

    # Record to Prometheus histogram
    prom_db_query_duration_seconds.labels(operation=op).observe(elapsed)

# Create tables and instrument SQLAlchemy within app context
with app.app_context():
    os.makedirs('/app/data', exist_ok=True)
    # Instrument SQLAlchemy inside app context where db.engine is accessible
    SQLAlchemyInstrumentor().instrument(engine=db.engine)
    db.create_all()
    logger.info("Database initialized")

    # Attach SQLAlchemy event listeners for Prometheus DB metrics
    # Must be done inside app context to avoid "Working outside of application context" error
    event.listen(db.engine, "before_cursor_execute", _before_cursor_execute)
    event.listen(db.engine, "after_cursor_execute", _after_cursor_execute)
    logger.info("SQLAlchemy event listeners registered for DB query duration tracking")

# Middleware for request tracking
@app.before_request
def before_request():
    request.start_time = time.time()
    g.prom_start_time = time.time()
    current_span = trace.get_current_span()
    logger.info(
        "Incoming request",
        extra={
            "method": request.method,
            "path": request.path,
            "trace_id": format(current_span.get_span_context().trace_id, '032x') if current_span else None,
            "span_id": format(current_span.get_span_context().span_id, '016x') if current_span else None
        }
    )

@app.after_request
def after_request(response):
    if hasattr(request, 'start_time'):
        duration = time.time() - request.start_time
        method = request.method
        endpoint = request.endpoint or "unknown"
        status_code = str(response.status_code)

        # Record Prometheus client metrics (exposed at /metrics)
        # This is the ONLY source of metrics for Prometheus now
        if hasattr(g, 'prom_start_time'):
            prom_duration = time.time() - g.prom_start_time
            prom_http_requests_total.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).inc()

            prom_http_request_duration_seconds.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).observe(prom_duration)

            # Track errors for SLI dashboards
            if response.status_code >= 400:
                prom_http_errors_total.labels(
                    method=method,
                    endpoint=endpoint,
                    status_code=status_code
                ).inc()

        # Log response (with trace context for correlation)
        current_span = trace.get_current_span()
        logger.info(
            "Request completed",
            extra={
                "method": method,
                "path": request.path,
                "status_code": response.status_code,
                "duration_seconds": duration,
                "trace_id": format(current_span.get_span_context().trace_id, '032x') if current_span else None,
                "span_id": format(current_span.get_span_context().span_id, '016x') if current_span else None
            }
        )

    return response

# API Routes
@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    with tracer.start_as_current_span("health_check") as span:
        span.set_attribute("health.status", "healthy")
        return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}), 200

@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """Get all tasks"""
    with tracer.start_as_current_span("get_all_tasks") as span:
        try:
            query_start = time.time()
            tasks = Task.query.all()
            query_duration_time = time.time() - query_start

            database_query_duration.record(query_duration_time, {
                "operation": "select",
                "table": "tasks"
            })

            span.set_attribute("db.query.duration", query_duration_time)
            span.set_attribute("db.result.count", len(tasks))

            logger.info(f"Retrieved {len(tasks)} tasks from database")

            return jsonify({
                "tasks": [task.to_dict() for task in tasks],
                "count": len(tasks)
            }), 200
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logger.error(f"Error retrieving tasks: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to retrieve tasks"}), 500

@app.route('/api/tasks/<int:task_id>', methods=['GET'])
def get_task(task_id):
    """Get a specific task"""
    with tracer.start_as_current_span("get_task_by_id") as span:
        span.set_attribute("task.id", task_id)

        try:
            query_start = time.time()
            task = Task.query.get(task_id)
            query_duration_time = time.time() - query_start

            database_query_duration.record(query_duration_time, {
                "operation": "select_by_id",
                "table": "tasks"
            })

            if not task:
                span.set_attribute("task.found", False)
                logger.warning(f"Task {task_id} not found")
                return jsonify({"error": "Task not found"}), 404

            span.set_attribute("task.found", True)
            logger.info(f"Retrieved task {task_id}")

            return jsonify(task.to_dict()), 200
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logger.error(f"Error retrieving task {task_id}: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to retrieve task"}), 500

@app.route('/api/tasks', methods=['POST'])
def create_task():
    """Create a new task"""
    with tracer.start_as_current_span("create_task") as span:
        try:
            data = request.get_json()

            if not data or 'title' not in data:
                span.set_attribute("validation.failed", True)
                logger.warning("Task creation failed: missing title")
                return jsonify({"error": "Title is required"}), 400

            span.set_attribute("task.title", data['title'])

            new_task = Task(
                title=data['title'],
                description=data.get('description', ''),
                completed=data.get('completed', False)
            )

            query_start = time.time()
            db.session.add(new_task)
            db.session.commit()
            query_duration_time = time.time() - query_start

            database_query_duration.record(query_duration_time, {
                "operation": "insert",
                "table": "tasks"
            })

            span.set_attribute("task.id", new_task.id)
            span.set_attribute("db.query.duration", query_duration_time)

            logger.info(f"Created new task {new_task.id}: {new_task.title}")

            return jsonify(new_task.to_dict()), 201
        except Exception as e:
            db.session.rollback()
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logger.error(f"Error creating task: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to create task"}), 500

@app.route('/api/tasks/<int:task_id>', methods=['PUT'])
def update_task(task_id):
    """Update an existing task"""
    with tracer.start_as_current_span("update_task") as span:
        span.set_attribute("task.id", task_id)

        try:
            task = Task.query.get(task_id)

            if not task:
                span.set_attribute("task.found", False)
                logger.warning(f"Task {task_id} not found for update")
                return jsonify({"error": "Task not found"}), 404

            data = request.get_json()

            if 'title' in data:
                task.title = data['title']
            if 'description' in data:
                task.description = data['description']
            if 'completed' in data:
                task.completed = data['completed']
                span.set_attribute("task.completed", data['completed'])

            query_start = time.time()
            db.session.commit()
            query_duration_time = time.time() - query_start

            database_query_duration.record(query_duration_time, {
                "operation": "update",
                "table": "tasks"
            })

            span.set_attribute("db.query.duration", query_duration_time)
            logger.info(f"Updated task {task_id}")

            return jsonify(task.to_dict()), 200
        except Exception as e:
            db.session.rollback()
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logger.error(f"Error updating task {task_id}: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to update task"}), 500

@app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
def delete_task(task_id):
    """Delete a task"""
    with tracer.start_as_current_span("delete_task") as span:
        span.set_attribute("task.id", task_id)

        try:
            task = Task.query.get(task_id)

            if not task:
                span.set_attribute("task.found", False)
                logger.warning(f"Task {task_id} not found for deletion")
                return jsonify({"error": "Task not found"}), 404

            query_start = time.time()
            db.session.delete(task)
            db.session.commit()
            query_duration_time = time.time() - query_start

            database_query_duration.record(query_duration_time, {
                "operation": "delete",
                "table": "tasks"
            })

            span.set_attribute("db.query.duration", query_duration_time)
            logger.info(f"Deleted task {task_id}")

            return jsonify({"message": "Task deleted successfully"}), 200
        except Exception as e:
            db.session.rollback()
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            logger.error(f"Error deleting task {task_id}: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to delete task"}), 500

@app.route('/api/simulate-error', methods=['GET'])
def simulate_error():
    """Endpoint to simulate errors for testing observability"""
    with tracer.start_as_current_span("simulate_error") as span:
        span.set_attribute("error.simulated", True)
        logger.error("Simulated error triggered for testing")
        span.set_status(Status(StatusCode.ERROR, "Simulated error"))
        return jsonify({"error": "This is a simulated error"}), 500

@app.route('/api/simulate-slow', methods=['GET'])
def simulate_slow():
    """Endpoint to simulate slow responses for testing SLOs"""
    with tracer.start_as_current_span("simulate_slow_request") as span:
        delay = float(request.args.get('delay', 2.0))
        span.set_attribute("delay.seconds", delay)
        logger.info(f"Simulating slow request with {delay}s delay")
        time.sleep(delay)
        return jsonify({"message": f"Delayed response after {delay} seconds"}), 200

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    # Generate and return Prometheus metrics in text format
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

@app.route('/api/smoke/db', methods=['POST'])
def db_smoke():
    """
    Generate DB traffic to warm Prometheus histograms.
    Query params:
      ops: total operations (default 200)
      type: 'read' | 'write' | 'rw'  (default 'rw')
    Writes are executed in a transaction and rolled back.
    """
    from sqlalchemy.sql import text

    ops = int(request.args.get('ops', 200))
    mode = request.args.get('type', 'rw').lower()

    read_ops = ops if mode == 'read' else (ops // 2 if mode == 'rw' else 0)
    write_ops = 0 if mode == 'read' else (ops if mode == 'write' else ops - read_ops)

    # Simple SELECT target
    read_stmt = text('SELECT COUNT(*) FROM tasks')

    # Simple INSERT/DELETE target (rolled back)
    insert_stmt = text('INSERT INTO tasks (title, description, completed, created_at) VALUES (:t, :d, :c, :dt)')
    delete_stmt = text('DELETE FROM tasks WHERE title LIKE :prefix')

    try:
        # Do reads without transaction (no state change)
        with db.engine.connect() as conn:
            for _ in range(read_ops):
                conn.execute(read_stmt)

        # Do writes in a transaction and roll back
        with db.engine.connect() as conn:
            trans = conn.begin()
            try:
                for i in range(write_ops):
                    conn.execute(
                        insert_stmt,
                        dict(t=f"smoke-{i}", d="smoke-test", c=False, dt=datetime.utcnow())
                    )
                # Clean them up (observe DELETE path too)
                conn.execute(delete_stmt, dict(prefix='smoke-%'))
                # Roll back so DB remains unchanged
                trans.rollback()
            except Exception:
                trans.rollback()
                raise

        logger.info(f"DB smoke test completed: {read_ops} reads, {write_ops} writes (rolled back)")

        return jsonify({
            "ok": True,
            "requested_ops": ops,
            "performed": {"read": read_ops, "write": write_ops},
            "note": "writes executed in a transaction and rolled back"
        }), 200

    except Exception as e:
        logger.error(f"DB smoke test failed: {str(e)}", exc_info=True)
        return jsonify({"error": "DB smoke test failed", "details": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
