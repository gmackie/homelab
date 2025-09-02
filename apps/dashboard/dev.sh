#!/bin/bash

# Development script to run both API and UI locally

echo "🚀 Starting Homelab Dashboard in Development Mode"

# Start API in background
echo "📡 Starting API server..."
cd api
go run cmd/server/main.go &
API_PID=$!

# Wait a moment for API to start
sleep 3

# Start UI development server
echo "🎨 Starting UI development server..."
cd ../ui
npm run dev &
UI_PID=$!

echo "✅ Dashboard running!"
echo "  - API: http://localhost:8080"
echo "  - UI: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop all services"

# Wait for interrupt signal
trap "kill $API_PID $UI_PID; exit" INT
wait