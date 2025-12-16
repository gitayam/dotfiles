#!/bin/bash

# Manual fix for cffile Worker when wrangler is not working
# This prepares everything for manual deployment via Cloudflare dashboard

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 cffile Worker Manual Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script prepares the Worker code for manual deployment"
echo "when wrangler is having issues."
echo ""

# Step 1: Prepare the Worker code
echo "1️⃣ Preparing Worker code..."
cp src/hybrid-tunnel.js /tmp/secure-tunnel-deploy.js
echo "✅ Worker code ready at: /tmp/secure-tunnel-deploy.js"
echo ""

# Step 2: Open in text editor
echo "2️⃣ Opening code in text editor..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    open -a TextEdit /tmp/secure-tunnel-deploy.js
    echo "✅ Code opened in TextEdit"
else
    echo "📋 Open this file manually: /tmp/secure-tunnel-deploy.js"
fi
echo ""

# Step 3: Provide instructions
echo "3️⃣ Manual Deployment Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "STEP 1: Delete the old Worker"
echo "  1. Go to https://dash.cloudflare.com"
echo "  2. Navigate to Workers & Pages"
echo "  3. Find 'secure-tunnel' Worker"
echo "  4. Click on it, then go to Settings"
echo "  5. Scroll down and click 'Delete' (red button)"
echo "  6. Confirm deletion"
echo ""
echo "STEP 2: Create new Worker with same name"
echo "  1. Click 'Create' → 'Create Worker'"
echo "  2. Name it exactly: secure-tunnel"
echo "  3. Click 'Deploy'"
echo ""
echo "STEP 3: Add the hybrid code"
echo "  1. Click 'Edit code' or 'Quick edit'"
echo "  2. Select all existing code (Cmd+A) and delete it"
echo "  3. Copy ALL content from the TextEdit window"
echo "  4. Paste into the Cloudflare editor"
echo "  5. Click 'Save and deploy'"
echo ""
echo "STEP 4: Add KV namespace (for storing tunnel configs)"
echo "  1. In the Worker, go to 'Settings' tab"
echo "  2. Find 'Variables' → 'KV Namespace Bindings'"
echo "  3. Click 'Add binding'"
echo "  4. Variable name: TUNNEL_CONFIG"
echo "  5. KV namespace: Create new or select existing"
echo "  6. Click 'Save'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "After completing these steps, test with:"
echo "  cffile -p testpass somefile.txt"
echo ""
echo "The password authentication will then work correctly,"
echo "redirecting to your files instead of showing 'Connection Instructions'"
echo ""

# Create a test script
cat > /tmp/test-cffile-fix.sh << 'EOF'
#!/bin/bash
echo "Testing cffile Worker..."
RESPONSE=$(curl -s -X POST "https://secure-tunnel.wemea-5ahhf.workers.dev/api/register" \
  -H "Content-Type: application/json" \
  -d '{"tunnelId":"test","password":"test","port":8080,"cloudflaredUrl":"https://test.trycloudflare.com"}')

if echo "$RESPONSE" | grep -q "success"; then
    echo "✅ Worker is working correctly!"
else
    echo "❌ Worker not yet fixed or deployed"
    echo "Response: $RESPONSE"
fi
EOF

chmod +x /tmp/test-cffile-fix.sh
echo "Test script created: /tmp/test-cffile-fix.sh"
echo "Run it after deployment to verify the fix worked"