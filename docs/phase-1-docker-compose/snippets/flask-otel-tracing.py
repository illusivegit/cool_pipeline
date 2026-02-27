# Flask OpenTelemetry Tracing Setup
# Source: backend/app.py
# Reference: DESIGN-DECISIONS.md DD-014, CONFIGURATION-REFERENCE.md

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
import os

# Step 1: Define Resource (identifies this service)
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "flask-backend"),
    "service.version": "1.0.0",
    "deployment.environment": "lab"
})

# Step 2: Create Tracer Provider
tracer_provider = TracerProvider(resource=resource)

# Step 3: Configure OTLP Exporter (sends spans to collector)
otlp_trace_exporter = OTLPSpanExporter(
    endpoint=f"{os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')}/v1/traces"
    # Example: http://otel-collector:4318/v1/traces
)

# Step 4: Add Batch Span Processor (buffers spans before sending)
span_processor = BatchSpanProcessor(
    otlp_trace_exporter,
    max_queue_size=2048,         # Queue up to 2048 spans in memory
    schedule_delay_millis=5000,  # Send batch every 5 seconds
    max_export_batch_size=512,   # Send max 512 spans per batch
    export_timeout_millis=30000  # Timeout after 30 seconds
)
tracer_provider.add_span_processor(span_processor)

# Step 5: Set Global Tracer Provider
trace.set_tracer_provider(tracer_provider)

# Step 6: Get Tracer for Manual Instrumentation
tracer = trace.get_tracer(__name__)

# Step 7: Automatic Instrumentation
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)  # Auto-instrument Flask requests

# Step 8: Instrument Database
with app.app_context():
    SQLAlchemyInstrumentor().instrument(engine=db.engine)  # Auto-instrument SQL queries

# Manual Instrumentation Example
@app.route('/api/tasks', methods=['POST'])
def create_task():
    # Create custom span for business logic
    with tracer.start_as_current_span("create_task") as span:
        try:
            data = request.get_json()

            # Add custom span attributes
            span.set_attribute("task.title", data['title'])
            span.set_attribute("validation.success", True)

            # Business logic (automatically creates child SQL span)
            new_task = Task(title=data['title'], description=data.get('description'))
            db.session.add(new_task)
            db.session.commit()

            span.set_attribute("task.id", new_task.id)
            return jsonify(new_task.to_dict()), 201

        except Exception as e:
            # Record exception in span
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            logger.error(f"Error creating task: {str(e)}", exc_info=True)
            return jsonify({"error": "Failed to create task"}), 500

# What gets traced automatically:
# - HTTP requests (method, route, status code, duration)
# - SQL queries (statement, duration, table names)
# - Exceptions (stack traces)
#
# What you should trace manually:
# - Business logic operations (create_order, process_payment)
# - External API calls
# - Complex algorithms
# - Domain-specific operations
#
# Why BatchSpanProcessor?
# - Reduces network overhead (batches spans)
# - Handles backpressure (queues spans)
# - Production-ready (handles failures gracefully)
#
# Alternative: SimpleSpanProcessor
# - Sends each span immediately (for debugging)
# - Higher overhead (one request per span)
# - Use only in development
#
# Tuning tips:
# - High throughput: Increase max_export_batch_size (1024+)
# - Low memory: Decrease max_queue_size (512)
# - Real-time debugging: Decrease schedule_delay_millis (1000)
