#!/bin/bash

echo "🧪 Testing Worker Deployment Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create a test tunnel registration
TUNNEL_ID="test-$(date +%s)"
RESPONSE=$(curl -s -X POST "https://secure-tunnel.wemea-5ahhf.workers.dev/api/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"tunnelId\": \"$TUNNEL_ID\",
    \"password\": \"test123\",
    \"port\": 8080,
    \"cloudflaredUrl\": \"https://test.trycloudflare.com\",
    \"description\": \"Test deployment\"
  }")

echo "Registration response: $RESPONSE"

if echo "$RESPONSE" | grep -q "cloudflaredUrl"; then
    echo "✅ Worker supports hybrid mode (GOOD - deployment successful)"
else
    echo "❌ Worker doesn't support hybrid mode (deployment needed)"
    echo ""
    echo "To fix:"
    echo "1. Go to https://dash.cloudflare.com"
    echo "2. Navigate to Workers & Pages → secure-tunnel"
    echo "3. Click 'Quick edit'"
    echo "4. Copy all content from src/hybrid-tunnel.js"
    echo "5. Paste and click 'Save and Deploy'"
fi