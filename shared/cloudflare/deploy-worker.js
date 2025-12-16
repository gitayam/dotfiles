#!/usr/bin/env node

const fs = require('fs');
const { exec } = require('child_process');
const path = require('path');

console.log('🚀 Deploying Worker using Node.js...');

// Read the hybrid-tunnel.js file
const workerCode = fs.readFileSync(path.join(__dirname, 'src/hybrid-tunnel.js'), 'utf8');

// Create a minimal wrangler.toml
const wranglerConfig = `
name = "secure-tunnel"
main = "worker.js"
compatibility_date = "2024-01-01"

[[kv_namespaces]]
binding = "TUNNEL_CONFIG"
id = "placeholder"
`;

// Write temporary files
fs.writeFileSync('/tmp/worker.js', workerCode);
fs.writeFileSync('/tmp/wrangler.toml', wranglerConfig);

// Try to deploy
console.log('📦 Attempting deployment...');
exec('cd /tmp && wrangler deploy --compatibility-date 2024-01-01', {
  timeout: 30000,
  env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }
}, (error, stdout, stderr) => {
  if (error) {
    console.error('❌ Deployment failed:', error.message);
    console.log('\n🔧 Alternative: Manual deployment required');
    console.log('1. Go to https://dash.cloudflare.com');
    console.log('2. Navigate to Workers & Pages → secure-tunnel');
    console.log('3. Click "Quick edit"');
    console.log('4. Copy content from src/hybrid-tunnel.js');
    console.log('5. Paste and Save');
  } else {
    console.log('✅ Deployment successful!');
    console.log(stdout);
  }
  
  // Cleanup
  try {
    fs.unlinkSync('/tmp/worker.js');
    fs.unlinkSync('/tmp/wrangler.toml');
  } catch (e) {
    // Ignore cleanup errors
  }
});