#!/usr/bin/env node

/**
 * Password-protected proxy server for Cloudflare tunnels
 * Creates an HTTP Basic Auth layer in front of local services
 */

const http = require('http');
const httpProxy = require('http-proxy');
const crypto = require('crypto');

// Get arguments
const args = process.argv.slice(2);
const proxyPort = parseInt(args[0]) || 3001;
const targetPort = parseInt(args[1]) || 8080;
const password = args[2] || 'password';
const username = args[3] || 'user';

// Create proxy server
const proxy = httpProxy.createProxyServer({});

// Create HTTP server with Basic Auth
const server = http.createServer((req, res) => {
  // Parse Authorization header
  const auth = req.headers.authorization;
  
  if (!auth || !auth.startsWith('Basic ')) {
    // No auth provided - send 401 with WWW-Authenticate header
    res.writeHead(401, {
      'WWW-Authenticate': 'Basic realm="Protected Tunnel"',
      'Content-Type': 'text/html'
    });
    res.end(`
<!DOCTYPE html>
<html>
<head>
  <title>Authentication Required</title>
  <style>
    body { 
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      max-width: 400px; 
      margin: 100px auto; 
      padding: 20px; 
      text-align: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
    }
    .container {
      background: white;
      border-radius: 12px;
      padding: 30px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    h1 { color: #333; margin-bottom: 10px; }
    p { color: #666; line-height: 1.6; }
    .icon { font-size: 48px; margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">🔐</div>
    <h1>Authentication Required</h1>
    <p>This tunnel is password protected.</p>
    <p>Please enter your credentials to continue.</p>
    <p><strong>Username:</strong> ${username}</p>
  </div>
</body>
</html>
    `);
    return;
  }

  // Decode Basic Auth
  const credentials = Buffer.from(auth.slice(6), 'base64').toString('utf-8');
  const [providedUsername, providedPassword] = credentials.split(':');

  // Check credentials
  if (providedUsername === username && providedPassword === password) {
    // Auth successful - proxy the request
    proxy.web(req, res, {
      target: `http://localhost:${targetPort}`,
      changeOrigin: true
    });
  } else {
    // Auth failed - send 401
    res.writeHead(401, {
      'WWW-Authenticate': 'Basic realm="Protected Tunnel"',
      'Content-Type': 'text/html'
    });
    res.end(`
<!DOCTYPE html>
<html>
<head>
  <title>Authentication Failed</title>
  <style>
    body { 
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      max-width: 400px; 
      margin: 100px auto; 
      padding: 20px; 
      text-align: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
    }
    .container {
      background: white;
      border-radius: 12px;
      padding: 30px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    h1 { color: #e53e3e; margin-bottom: 10px; }
    p { color: #666; line-height: 1.6; }
    .icon { font-size: 48px; margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">❌</div>
    <h1>Authentication Failed</h1>
    <p>Invalid username or password.</p>
    <p>Please try again.</p>
  </div>
</body>
</html>
    `);
  }
});

// Handle proxy errors
proxy.on('error', (err, req, res) => {
  console.error('Proxy error:', err.message);
  if (!res.headersSent) {
    res.writeHead(502, { 'Content-Type': 'text/html' });
    res.end(`
<!DOCTYPE html>
<html>
<head>
  <title>Service Unavailable</title>
  <style>
    body { 
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      max-width: 400px; 
      margin: 100px auto; 
      padding: 20px; 
      text-align: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
    }
    .container {
      background: white;
      border-radius: 12px;
      padding: 30px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    h1 { color: #e53e3e; margin-bottom: 10px; }
    p { color: #666; line-height: 1.6; }
    .icon { font-size: 48px; margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">🚫</div>
    <h1>Service Unavailable</h1>
    <p>Cannot connect to localhost:${targetPort}</p>
    <p>Make sure your service is running on port ${targetPort}</p>
  </div>
</body>
</html>
    `);
  }
});

// Start server
server.listen(proxyPort, () => {
  console.log(`🔐 Password-protected proxy server running on port ${proxyPort}`);
  console.log(`🎯 Forwarding to localhost:${targetPort}`);
  console.log(`👤 Username: ${username}`);
  console.log(`🔑 Password: ${password}`);
  console.log(`\n💡 Connect your tunnel to localhost:${proxyPort}`);
});

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down proxy server...');
  server.close(() => {
    console.log('✅ Proxy server stopped');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('\n🛑 Shutting down proxy server...');
  server.close(() => {
    console.log('✅ Proxy server stopped');  
    process.exit(0);
  });
});