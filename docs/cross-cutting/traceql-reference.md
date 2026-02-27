# TraceQL Query Reference

## Overview

**TraceQL** is Grafana Tempo's query language for searching and filtering distributed traces.

**Version:** Tempo 2.3.1+
**Related:** [Observability Fundamentals](observability-fundamentals.md)

---

## Basic Syntax

### Simple Selector

```traceql
{ attribute = "value" }
```

**Examples:**
```traceql
# All traces from flask-backend
{ resource.service.name = "flask-backend" }

# All HTTP POST requests
{ span.http.method = "POST" }

# All database operations
{ span.db.system != "" }
```

---

## Attribute Types

### Resource Attributes
**Set at service level, same for all spans in a trace**

```traceql
{ resource.service.name = "flask-backend" }
{ resource.service.version = "1.0.0" }
{ resource.deployment.environment = "production" }
```

### Span Attributes
**Set per operation, can differ within a trace**

```traceql
{ span.http.method = "GET" }
{ span.http.target = "/api/tasks" }
{ span.db.system = "postgresql" }
{ span.db.statement = "SELECT * FROM tasks" }
```

---

## Operators

### Equality

```traceql
{ attribute = "value" }    # Exact match
{ attribute != "value" }   # Not equal
```

### Comparison

```traceql
{ duration > 100ms }       # Greater than
{ duration >= 100ms }      # Greater than or equal
{ duration < 500ms }       # Less than
{ duration <= 500ms }      # Less than or equal
```

### Existence

```traceql
{ span.db.system != "" }   # Attribute exists
```

---

## Logical Operators

### AND

```traceql
{ resource.service.name = "flask-backend" && span.http.method = "POST" }
```

### OR

```traceql
{ span.http.status_code = 500 || span.http.status_code = 503 }
```

### Combined

```traceql
{
  resource.service.name = "flask-backend" &&
  (span.http.status_code = 500 || span.http.status_code = 503) &&
  duration > 100ms
}
```

---

## Duration Filters

### Supported Units
- `ns` - nanoseconds
- `us` - microseconds
- `ms` - milliseconds
- `s` - seconds
- `m` - minutes
- `h` - hours

### Examples

```traceql
# Slow requests (> 500ms)
{ duration > 500ms }

# Very slow requests (> 5 seconds)
{ duration > 5s }

# Fast requests (< 100ms)
{ duration < 100ms }

# Duration range
{ duration > 100ms && duration < 500ms }
```

---

## Common Query Patterns

### Service-Specific Queries

```traceql
# All traces from a service
{ resource.service.name = "flask-backend" }

# Multiple services
{ resource.service.name = "flask-backend" || resource.service.name = "frontend" }
```

### HTTP Queries

```traceql
# All GET requests
{ span.http.method = "GET" }

# Specific endpoint
{ span.http.target = "/api/tasks" }

# HTTP errors (4xx, 5xx)
{ span.http.status_code >= 400 }

# Slow HTTP requests
{ span.http.method != "" && duration > 500ms }
```

### Database Queries

```traceql
# All database operations
{ span.db.system != "" }

# Specific database
{ span.db.system = "postgresql" }

# Slow queries
{ span.db.system != "" && duration > 50ms }

# Specific operation
{ span.db.operation = "SELECT" }
```

### Error Queries

```traceql
# Any error
{ status = error }

# HTTP 500 errors
{ span.http.status_code = 500 }

# Database errors
{ span.db.system != "" && status = error }
```

---

## Tempo 2.3.1 Limitations

### NOT Supported (as of 2.3.1)

❌ **Pipeline operators**
```traceql
# This FAILS in Tempo 2.3.1
{ resource.service.name = "flask-backend" } | limit 50
```

✅ **Use limit parameter instead:**
```json
{
  "query": "{ resource.service.name = \"flask-backend\" }",
  "limit": 50
}
```

❌ **Advanced filtering**
```traceql
# These may not work in 2.3.1
{ resource.service.name =~ "flask.*" }  # Regex
{ span.name | select }                  # Select operator
```

---

## Grafana Integration

### In Grafana Explore

1. Select **Tempo** datasource
2. Switch to **TraceQL** tab
3. Enter query: `{ resource.service.name = "flask-backend" }`
4. Click **Run query**

### In Dashboard Panel

**Panel type:** `table` (recommended for Tempo 2.3.1)

**Query configuration:**
```json
{
  "datasource": {
    "type": "tempo",
    "uid": "tempo"
  },
  "queryType": "traceql",
  "query": "{ resource.service.name = \"flask-backend\" }",
  "limit": 50
}
```

---

## Examples by Use Case

### Performance Analysis

```traceql
# Find slow traces
{ duration > 500ms }

# Slow database queries
{ span.db.system != "" && duration > 100ms }

# Slow HTTP endpoints
{ span.http.target != "" && duration > 1s }
```

### Error Investigation

```traceql
# All errors
{ status = error }

# Errors on specific endpoint
{ span.http.target = "/api/tasks" && status = error }

# HTTP 5xx errors
{ span.http.status_code >= 500 }
```

### Service Health

```traceql
# Check service is generating traces
{ resource.service.name = "flask-backend" }

# Verify endpoint is being called
{ span.http.target = "/health" }
```

### Dependency Tracking

```traceql
# Traces involving database
{ span.db.system = "postgresql" }

# Traces with external API calls
{ span.http.host = "api.external.com" }
```

---

## Troubleshooting Queries

### Query Returns No Results

**Check:**
1. **Time range:** Widen to "Last 6 hours"
2. **Service name:** Verify exact match (case-sensitive)
3. **Attribute exists:** Use `!= ""` to check existence
4. **Tempo has data:** Run simple query `{ duration > 0ms }`

**Debug:**
```bash
# Test Tempo API directly
curl "http://localhost:3200/api/search?limit=5"

# Verify service name
curl "http://localhost:3200/api/search?limit=1" | jq '.traces[0].rootServiceName'
```

### Parse Errors

**Common causes:**

❌ **Missing quotes around values**
```traceql
{ resource.service.name = flask-backend }  # Wrong
{ resource.service.name = "flask-backend" }  # Correct
```

❌ **Using pipeline operators (not supported in 2.3.1)**
```traceql
{ resource.service.name = "flask-backend" } | limit 50  # Wrong
```

❌ **Wrong attribute prefix**
```traceql
{ service.name = "flask-backend" }          # Wrong
{ resource.service.name = "flask-backend" }  # Correct
```

---

## Best Practices

### Performance

✅ **DO:**
- Start with service/resource filters (most selective)
- Use duration filters to reduce result set
- Set appropriate limit (20-50 for dashboards)

❌ **DON'T:**
- Query for all traces (no filters)
- Use very large limits (> 100)
- Run queries over long time ranges (> 24h)

### Maintainability

✅ **DO:**
- Use variables for service names in dashboards
- Document complex queries
- Test queries in Explore first

❌ **DON'T:**
- Hard-code values in production queries
- Create overly complex boolean logic
- Assume case-insensitive matching

---

## Common Span Attributes

### HTTP Spans

| Attribute | Example | Description |
|-----------|---------|-------------|
| `span.http.method` | `"GET"` | HTTP method |
| `span.http.target` | `"/api/tasks"` | URL path |
| `span.http.status_code` | `200` | HTTP status |
| `span.http.host` | `"localhost:5000"` | Host header |
| `span.http.scheme` | `"http"` | Protocol |

### Database Spans

| Attribute | Example | Description |
|-----------|---------|-------------|
| `span.db.system` | `"postgresql"` | Database type |
| `span.db.statement` | `"SELECT * FROM tasks"` | SQL query |
| `span.db.operation` | `"SELECT"` | Operation type |
| `span.db.name` | `"myapp"` | Database name |

### Resource Attributes

| Attribute | Example | Description |
|-----------|---------|-------------|
| `resource.service.name` | `"flask-backend"` | Service identifier |
| `resource.service.version` | `"1.0.0"` | Service version |
| `resource.deployment.environment` | `"production"` | Environment |

---

## Version Differences

### Tempo 2.3.1 (Current)
- ✅ Basic selectors
- ✅ Duration filters
- ✅ Boolean operators
- ❌ Pipeline operators (`| limit`, `| select`)
- ❌ Regex matching
- ❌ Advanced aggregations

### Tempo 2.4+ (Future)
- ✅ Everything in 2.3.1
- ✅ Pipeline operators
- ✅ Span set operations
- ✅ More complex queries

**Migration note:** Queries without pipelines work across versions

---

## References

### Official Documentation
- [TraceQL Documentation](https://grafana.com/docs/tempo/latest/traceql/)
- [Tempo 2.3.x Reference](https://grafana.com/docs/tempo/v2.3/)

### Related Docs
- [Observability Fundamentals](observability-fundamentals.md)
- [Phase 1 Troubleshooting](../phase-1-docker-compose/troubleshooting/)

### Testing Queries
- Grafana Explore: `http://localhost:3000/explore`
- Tempo API: `http://localhost:3200/api/search`

---
