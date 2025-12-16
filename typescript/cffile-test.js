#!/usr/bin/env node

/**
 * Simple cffile test - combines Python HTTP server with tunnel
 */

const { spawn } = require('child_process');
const path = require('path');

async function testCffile(files = []) {
  console.log('🧪 Testing cffile functionality...');
  
  const port = 8001;
  const password = 'test123';
  
  // Start Python server
  console.log('🚀 Starting Python HTTP server...');
  const pythonServer = spawn('python3', ['-m', 'http.server', port.toString()], {
    stdio: 'inherit'
  });
  
  // Wait a moment for server to start
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  console.log('✅ Server started on port', port);
  console.log('🌐 Starting tunnel...');
  
  // Start tunnel
  const tunnelClient = spawn('node', ['src/tunnel-client.js', port.toString(), password, 'cffile test'], {
    stdio: 'inherit'
  });
  
  // Cleanup function
  const cleanup = () => {
    console.log('\n🛑 Stopping cffile test...');
    pythonServer.kill();
    tunnelClient.kill();
    process.exit(0);
  };
  
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
  
  // Wait for tunnel
  tunnelClient.on('close', cleanup);
}

// Run test
testCffile().catch(console.error);