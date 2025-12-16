#!/bin/bash

# Deploy the hybrid tunnel Worker to Cloudflare

echo "🚀 Deploying hybrid tunnel Worker..."

# Check if CF_API_TOKEN is set
if [ -z "$CF_API_TOKEN" ]; then
    echo "⚠️  CF_API_TOKEN not set. Trying to use wrangler auth..."
fi

# Deploy the Worker
echo "📦 Deploying to Cloudflare Workers..."
wrangler deploy src/hybrid-tunnel.js \
    --name secure-tunnel \
    --compatibility-date 2024-01-01 \
    --no-bundle

if [ $? -eq 0 ]; then
    echo "✅ Worker deployed successfully!"
    echo "🔗 Worker URL: https://secure-tunnel.wemea-5ahhf.workers.dev"
else
    echo "❌ Deployment failed"
    exit 1
fi