// OpenTelemetry Browser Instrumentation
import { WebTracerProvider } from 'https://unpkg.com/@opentelemetry/sdk-trace-web@1.19.0/build/esm/index.js';
import { Resource } from 'https://unpkg.com/@opentelemetry/resources@1.19.0/build/esm/index.js';
import { SimpleSpanProcessor } from 'https://unpkg.com/@opentelemetry/sdk-trace-base@1.19.0/build/esm/index.js';
import { OTLPTraceExporter } from 'https://unpkg.com/@opentelemetry/exporter-trace-otlp-http@0.46.0/build/esm/index.js';
import { ZoneContextManager } from 'https://unpkg.com/@opentelemetry/context-zone@1.19.0/build/esm/index.js';
import { FetchInstrumentation } from 'https://unpkg.com/@opentelemetry/instrumentation-fetch@0.46.0/build/esm/index.js';
import { XMLHttpRequestInstrumentation } from 'https://unpkg.com/@opentelemetry/instrumentation-xml-http-request@0.46.0/build/esm/index.js';
import { registerInstrumentations } from 'https://unpkg.com/@opentelemetry/instrumentation@0.46.0/build/esm/index.js';
import { SEMRESATTRS_SERVICE_NAME, SEMRESATTRS_SERVICE_VERSION } from 'https://unpkg.com/@opentelemetry/semantic-conventions@1.19.0/build/esm/index.js';

// Create resource with service information
const resource = Resource.default().merge(
  new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'frontend-browser',
    [SEMRESATTRS_SERVICE_VERSION]: '1.0.0',
    'deployment.environment': 'lab',
  })
);

// Create tracer provider
const provider = new WebTracerProvider({
  resource: resource,
});

// Configure OTLP exporter - Dynamic URL based on current hostname
// This makes the config work across all environments (localhost, VM, cloud)
const collectorUrl = `http://${window.location.hostname}:4318/v1/traces`;
const exporter = new OTLPTraceExporter({
  url: collectorUrl,
});

// Add span processor
provider.addSpanProcessor(new SimpleSpanProcessor(exporter));

// Register the provider
provider.register({
  contextManager: new ZoneContextManager(),
});

// Register instrumentations for automatic tracing
// Dynamic CORS URLs based on current hostname for environment portability
const backendUrl = `http://${window.location.hostname}:5000`;
const backendUrlPattern = new RegExp(`http://${window.location.hostname}:5000/.*`);

registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: [
        backendUrl,
        backendUrlPattern,
      ],
      clearTimingResources: true,
    }),
    new XMLHttpRequestInstrumentation({
      propagateTraceHeaderCorsUrls: [
        backendUrl,
        backendUrlPattern,
      ],
    }),
  ],
});

console.log('OpenTelemetry Browser SDK initialized');

// Export tracer for manual instrumentation
export const tracer = provider.getTracer('frontend-browser');
