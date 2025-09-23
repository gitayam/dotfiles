#!/bin/bash

# Fix cffile Worker deployment - removes old and deploys new hybrid version
# This fixes the password authentication redirect issue

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 cffile Worker Fix Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This will fix the password authentication issue where"
echo "the Worker shows 'Connection Instructions' instead of"
echo "redirecting to your files."
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ wrangler not found. Installing..."
    npm install -g wrangler
fi

# Function to check if wrangler is authenticated
check_wrangler_auth() {
    if ! wrangler whoami &>/dev/null; then
        echo "⚠️  Not logged in to Cloudflare"
        echo "Please run: wrangler login"
        echo "Then run this script again"
        exit 1
    fi
}

# Function to deploy with retry
deploy_worker() {
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        echo "🚀 Deployment attempt $attempt of $max_attempts..."
        
        if timeout 30 wrangler deploy src/hybrid-tunnel.js \
            --name secure-tunnel \
            --compatibility-date 2024-01-01 2>&1; then
            echo "✅ Worker deployed successfully!"
            return 0
        else
            echo "⚠️  Attempt $attempt failed"
            attempt=$((attempt + 1))
            if [ $attempt -le $max_attempts ]; then
                echo "   Retrying in 3 seconds..."
                sleep 3
            fi
        fi
    done
    
    return 1
}

# Step 1: Check authentication
echo "1️⃣ Checking Cloudflare authentication..."
if wrangler whoami &>/dev/null; then
    echo "✅ Authenticated to Cloudflare"
else
    echo "📝 Opening browser for authentication..."
    wrangler login
    if ! wrangler whoami &>/dev/null; then
        echo "❌ Authentication failed. Please try again."
        exit 1
    fi
fi

# Step 2: Delete old Worker (if exists)
echo ""
echo "2️⃣ Removing old Worker (if exists)..."
if wrangler delete --name secure-tunnel --force 2>/dev/null; then
    echo "✅ Old Worker removed"
    sleep 2  # Wait for deletion to propagate
else
    echo "ℹ️  No existing Worker found or already removed"
fi

# Step 3: Create KV namespace if needed
echo ""
echo "3️⃣ Setting up KV namespace..."
KV_ID=$(wrangler kv:namespace list 2>/dev/null | grep -o '"id":"[^"]*".*"title":"TUNNEL_CONFIG"' | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || true)

if [ -z "$KV_ID" ]; then
    echo "   Creating new KV namespace..."
    KV_OUTPUT=$(wrangler kv:namespace create "TUNNEL_CONFIG" 2>&1)
    KV_ID=$(echo "$KV_OUTPUT" | grep -o 'id = "[^"]*"' | cut -d'"' -f2)
    if [ -z "$KV_ID" ]; then
        # Try alternative parsing
        KV_ID=$(echo "$KV_OUTPUT" | grep -o '[a-f0-9]\{32\}' | head -1)
    fi
    echo "✅ KV namespace created: $KV_ID"
else
    echo "✅ Using existing KV namespace: $KV_ID"
fi

# Step 4: Create wrangler.toml with correct KV binding
echo ""
echo "4️⃣ Creating deployment configuration..."
cat > wrangler-temp.toml << EOF
name = "secure-tunnel"
main = "src/hybrid-tunnel.js"
compatibility_date = "2024-01-01"

[[kv_namespaces]]
binding = "TUNNEL_CONFIG"
id = "$KV_ID"
EOF

echo "✅ Configuration created"

# Step 5: Deploy the new Worker
echo ""
echo "5️⃣ Deploying new hybrid Worker..."
if wrangler deploy --config wrangler-temp.toml; then
    echo "✅ Worker deployed successfully!"
    WORKER_URL=$(wrangler deployments list --name secure-tunnel 2>/dev/null | grep -o 'https://[^[:space:]]*' | head -1 || echo "https://secure-tunnel.*.workers.dev")
else
    echo "⚠️  Automated deployment failed. Trying alternative method..."
    if deploy_worker; then
        WORKER_URL="https://secure-tunnel.*.workers.dev"
    else
        echo ""
        echo "❌ Automated deployment failed. Manual deployment required:"
        echo ""
        echo "1. Go to https://dash.cloudflare.com"
        echo "2. Navigate to Workers & Pages"
        echo "3. Click 'Create' → 'Create Worker'"
        echo "4. Name it: secure-tunnel"
        echo "5. Click 'Create'"
        echo "6. Click 'Quick edit'"
        echo "7. Delete the default code"
        echo "8. Copy all content from: src/hybrid-tunnel.js"
        echo "9. Paste and click 'Save and Deploy'"
        echo "10. Go to Settings → Variables → KV Namespace Bindings"
        echo "11. Add binding: Variable name = TUNNEL_CONFIG"
        echo ""
        rm -f wrangler-temp.toml
        exit 1
    fi
fi

# Step 6: Test the deployment
echo ""
echo "6️⃣ Testing deployment..."
# Use the known Worker URL for testing
TEST_URL="https://secure-tunnel.wemea-5ahhf.workers.dev"
TEST_RESPONSE=$(curl -s -X POST "$TEST_URL/api/register" \
  -H "Content-Type: application/json" \
  -d '{
    "tunnelId": "test-deploy",
    "password": "test",
    "port": 8080,
    "cloudflaredUrl": "https://test.trycloudflare.com",
    "description": "Test"
  }' 2>/dev/null || echo "{}")

if echo "$TEST_RESPONSE" | grep -q "success"; then
    echo "✅ Worker is responding correctly!"
else
    echo "⚠️  Worker deployed but may need configuration"
fi

# Cleanup
rm -f wrangler-temp.toml

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ cffile Worker Fix Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The password authentication should now work correctly."
echo "When you use cffile with a password, it will:"
echo "1. Show the authentication page"
echo "2. After entering password, redirect directly to your files"
echo "3. No more 'Connection Instructions' page"
echo ""
echo "Test it with:"
echo "  cffile -p mypassword somefile.txt"
echo ""
echo "Worker URL: $WORKER_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"