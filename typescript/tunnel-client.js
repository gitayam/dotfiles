#!/usr/bin/env node

/**
 * Tunnel Client for Cloudflare Worker Integration
 * Registers local services with the secure tunnel Worker
 */

const http = require('http');
const crypto = require('crypto');

// Configuration
const WORKER_URL = 'https://secure-tunnel.wemea-5ahhf.workers.dev';

async function registerTunnel(port, password, description) {
  const tunnelId = generateTunnelId();
  
  try {
    const response = await fetch(`${WORKER_URL}/api/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        tunnelId,
        password,
        port: parseInt(port),
        description: description || `Local service on port ${port}`
      })
    });
    
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }
    
    const result = await response.json();
    
    console.log('\n🎉 Tunnel registered successfully!');
    console.log(`\n🔗 Tunnel URL: ${result.tunnelUrl}`);
    console.log(`🆔 Tunnel ID: ${tunnelId}`);
    console.log(`🔑 Password: ${password}`);
    console.log(`🎯 Local Port: ${port}`);
    
    // Copy URL to clipboard if pbcopy is available
    try {
      const { exec } = require('child_process');
      exec(`echo "${result.tunnelUrl}" | pbcopy`, (error) => {
        if (!error) {
          console.log(`📋 URL copied to clipboard`);
        }
      });
    } catch (e) {
      // Ignore clipboard errors
    }
    
    console.log('\n💡 Share the URL and password to give others secure access');
    console.log('🛡️  All access is authenticated and encrypted');
    
    return { tunnelId, tunnelUrl: result.tunnelUrl };
    
  } catch (error) {
    console.error(`❌ Failed to register tunnel: ${error.message}`);
    process.exit(1);
  }
}

async function checkTunnelStatus(tunnelId) {
  try {
    const response = await fetch(`${WORKER_URL}/api/status?tunnelId=${tunnelId}`);
    
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }
    
    const status = await response.json();
    
    console.log(`\n📊 Tunnel Status: ${tunnelId}`);
    console.log(`🟢 Active: ${status.active ? 'Yes' : 'No'}`);
    console.log(`🎯 Port: ${status.port}`);
    console.log(`📝 Description: ${status.description}`);
    console.log(`📅 Created: ${new Date(status.createdAt).toLocaleString()}`);
    console.log(`👀 Last Seen: ${new Date(status.lastSeen).toLocaleString()}`);
    
    return status;
    
  } catch (error) {
    console.error(`❌ Failed to check tunnel status: ${error.message}`);
    process.exit(1);
  }
}

function generateTunnelId() {
  // Generate a random tunnel ID
  const words = [
    'swift', 'bright', 'clever', 'gentle', 'mighty', 'serene', 'bold', 'calm',
    'eagle', 'river', 'mountain', 'forest', 'ocean', 'thunder', 'lightning', 'breeze',
    'alpha', 'beta', 'gamma', 'delta', 'omega', 'sigma', 'phoenix', 'dragon'
  ];
  
  const word1 = words[Math.floor(Math.random() * words.length)];
  const word2 = words[Math.floor(Math.random() * words.length)];
  const number = Math.floor(Math.random() * 1000);
  
  return `${word1}-${word2}-${number}`;
}

function startKeepAlive(port, tunnelId) {
  console.log('\n🔄 Starting keep-alive service...');
  console.log('🛑 Press Ctrl+C to stop the tunnel');
  
  // Simple HTTP server to keep the process alive and monitor local service
  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'active',
        tunnelId,
        port,
        timestamp: new Date().toISOString()
      }));
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(`
        <!DOCTYPE html>
        <html>
        <head><title>Tunnel Keep-Alive</title></head>
        <body>
          <h1>🔐 Secure Tunnel Active</h1>
          <p><strong>Tunnel ID:</strong> ${tunnelId}</p>
          <p><strong>Local Port:</strong> ${port}</p>
          <p><strong>Status:</strong> Running</p>
          <p><strong>Time:</strong> ${new Date().toISOString()}</p>
        </body>
        </html>
      `);
    }
  });
  
  // Find available port for keep-alive server
  let keepAlivePort = 3100;
  const tryListen = () => {
    server.listen(keepAlivePort, () => {
      console.log(`📡 Keep-alive server running on http://localhost:${keepAlivePort}`);
    });
  };
  
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      keepAlivePort++;
      tryListen();
    } else {
      console.error('Keep-alive server error:', err.message);
    }
  });
  
  tryListen();
  
  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n\n🛑 Shutting down tunnel...');
    server.close(() => {
      console.log('✅ Tunnel stopped');
      process.exit(0);
    });
  });
  
  process.on('SIGTERM', () => {
    console.log('\n\n🛑 Shutting down tunnel...');
    server.close(() => {
      console.log('✅ Tunnel stopped');
      process.exit(0);
    });
  });
}

// Main execution
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length < 2) {
    console.log(`
Usage: node tunnel-client.js <port> <password> [description]
       node tunnel-client.js status <tunnelId>

Examples:
  node tunnel-client.js 8080 mypassword "My Web App"
  node tunnel-client.js status swift-eagle-123
`);
    process.exit(1);
  }
  
  if (args[0] === 'status') {
    const tunnelId = args[1];
    if (!tunnelId) {
      console.error('❌ Tunnel ID required for status check');
      process.exit(1);
    }
    await checkTunnelStatus(tunnelId);
    return;
  }
  
  const port = args[0];
  const password = args[1];
  const description = args[2];
  
  if (!port || !password) {
    console.error('❌ Port and password are required');
    process.exit(1);
  }
  
  // Validate port number
  const portNum = parseInt(port);
  if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
    console.error('❌ Invalid port number');
    process.exit(1);
  }
  
  // Check if local service is running
  const testServer = http.request({
    hostname: 'localhost',
    port: portNum,
    method: 'GET',
    timeout: 2000
  }, (res) => {
    console.log(`✅ Local service detected on port ${portNum}`);
    testServer.destroy();
  });
  
  testServer.on('error', () => {
    console.log(`⚠️  Warning: No service detected on port ${portNum}`);
    console.log('   Make sure your service is running before sharing the tunnel');
  });
  
  testServer.end();
  
  // Register tunnel
  const result = await registerTunnel(port, password, description);
  
  // Start keep-alive
  startKeepAlive(port, result.tunnelId);
}

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('❌ Unexpected error:', error.message);
  process.exit(1);
});

if (require.main === module) {
  main();
}