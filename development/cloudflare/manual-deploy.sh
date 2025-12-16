#!/bin/bash

echo "🚀 Alternative Deployment Method"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Since wrangler is having issues, here's what we'll do:"
echo ""

# Step 1: Create a minified version of the worker
echo "1️⃣ Creating deployment bundle..."
cat src/hybrid-tunnel.js > /tmp/secure-tunnel-deploy.js

echo "✅ Bundle created at /tmp/secure-tunnel-deploy.js"
echo ""

# Step 2: Try using miniflare for local testing
echo "2️⃣ Checking for alternative tools..."
if command -v miniflare &> /dev/null; then
    echo "Found miniflare - testing locally..."
    miniflare /tmp/secure-tunnel-deploy.js --kv TUNNEL_CONFIG --port 8787 &
    MINIFLARE_PID=$!
    sleep 2
    curl -s http://localhost:8787/ | head -5
    kill $MINIFLARE_PID 2>/dev/null
else
    echo "Miniflare not found. To install: npm install -g miniflare"
fi

echo ""
echo "3️⃣ Quick Deploy Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Option A: Use wrangler when it's working again:"
echo "  wrangler deploy /tmp/secure-tunnel-deploy.js --name secure-tunnel"
echo ""
echo "Option B: Manual Dashboard Deploy:"
echo "  1. Open https://dash.cloudflare.com"
echo "  2. Go to Workers & Pages"
echo "  3. Find 'secure-tunnel' worker"
echo "  4. Click 'Quick edit'"
echo "  5. Select all (Cmd+A) and delete"
echo "  6. Open /tmp/secure-tunnel-deploy.js"
echo "  7. Copy all content (Cmd+A, Cmd+C)"
echo "  8. Paste in Cloudflare editor"
echo "  9. Click 'Save and Deploy'"
echo ""
echo "Option C: Create new worker:"
echo "  1. Open https://dash.cloudflare.com"
echo "  2. Workers & Pages → Create → Create Worker"
echo "  3. Name it 'secure-tunnel-v2'"
echo "  4. Paste code from /tmp/secure-tunnel-deploy.js"
echo "  5. Update cffile-hybrid.sh line 10:"
echo "     WORKER_URL=\"https://secure-tunnel-v2.<your-subdomain>.workers.dev\""
echo ""
echo "📋 Code has been prepared at: /tmp/secure-tunnel-deploy.js"
echo "   You can open it with: open -a TextEdit /tmp/secure-tunnel-deploy.js"
echo ""

# Open the file in default text editor for easy copying
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Opening file in TextEdit for easy copying..."
    open -a TextEdit /tmp/secure-tunnel-deploy.js
fi