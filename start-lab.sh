#!/bin/bash

echo "=================================="
echo "OpenTelemetry Observability Lab"
echo "=================================="
echo ""

PROJECT="${PROJECT:-lab}"
LAB_HOST="${LAB_HOST:-localhost}"

echo "📦 Using project name: ${PROJECT}"
echo "🌐 Using access host: ${LAB_HOST}"
echo ""

if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "✅ Docker is running"
echo ""

if ! docker compose version &> /dev/null; then
    echo "❌ Error: docker compose is not installed. Please install it and try again."
    exit 1
fi

echo "✅ docker compose is available"
echo ""

echo "🧹 Cleaning up existing containers..."
docker compose -p ${PROJECT} down -v 2>/dev/null

echo ""
echo "🚀 Starting services with project name: ${PROJECT}"
echo "   (This matches the Jenkins pipeline deployment pattern)"
echo ""
export DOCKER_BUILDKIT=1
docker compose -p ${PROJECT} up -d --build

echo ""
echo "⏳ Waiting for services to start..."
sleep 10

echo ""
echo "📋 Container Status:"
docker compose -p ${PROJECT} ps

echo ""
echo "🔍 Checking service health..."
echo ""

if curl -s http://localhost:13133 > /dev/null 2>&1; then
    echo "✅ OpenTelemetry Collector: Healthy"
else
    echo "⚠️  OpenTelemetry Collector: Starting..."
fi

if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    echo "✅ Flask Backend: Healthy"
else
    echo "⚠️  Flask Backend: Starting..."
fi

if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Grafana: Healthy"
else
    echo "⚠️  Grafana: Starting..."
fi

if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo "✅ Prometheus: Healthy"
else
    echo "⚠️  Prometheus: Starting..."
fi

if curl -s http://localhost:3200/ready > /dev/null 2>&1; then
    echo "✅ Tempo: Healthy"
else
    echo "⚠️  Tempo: Starting..."
fi

if curl -s http://localhost:3100/ready > /dev/null 2>&1; then
    echo "✅ Loki: Healthy"
else
    echo "⚠️  Loki: Starting..."
fi

echo ""
echo "=================================="
echo "🎉 Lab is ready!"
echo "=================================="
echo ""
echo "📊 Access Points:"
echo "   Frontend:    http://${LAB_HOST}:8080"
echo "   Grafana:     http://${LAB_HOST}:3000"
echo "   Prometheus:  http://${LAB_HOST}:9090"
echo "   Tempo:       http://${LAB_HOST}:3200"
echo ""
echo "📚 Next Steps:"
echo "   1. Open the frontend: http://${LAB_HOST}:8080"
echo "   2. Create some tasks to generate telemetry"
echo "   3. View traces in Grafana: http://${LAB_HOST}:3000"
echo "   4. Check the SLI/SLO Dashboard"
echo ""
echo "💡 Tips:"
echo "   - View logs:    docker compose -p ${PROJECT} logs -f [service-name]"
echo "   - Stop lab:     docker compose -p ${PROJECT} down"
echo "   - Restart:      docker compose -p ${PROJECT} restart [service-name]"
echo "   - List status:  docker compose -p ${PROJECT} ps"
echo ""
echo "⚠️  Note: When using project name '${PROJECT}', always include '-p ${PROJECT}'"
echo "   in your docker compose commands for proper container management."
echo ""
echo "=================================="
