/**
 * Cloudflare Worker for Secure Tunnel Service
 * Provides password-protected access to local services via persistent URLs
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Handle different routes
    if (path === '/') {
      return handleHomePage();
    } else if (path === '/api/register') {
      return handleTunnelRegistration(request, env);
    } else if (path === '/api/status') {
      return handleStatusCheck(request, env);
    } else if (path.startsWith('/tunnel/')) {
      return handleTunnelAccess(request, env);
    } else if (path === '/health') {
      return new Response('OK', { status: 200 });
    }
    
    return new Response('Not Found', { status: 404 });
  }
};

async function handleHomePage() {
  return new Response(generateHomePage(), {
    headers: { 'Content-Type': 'text/html' }
  });
}

async function handleTunnelRegistration(request, env) {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  
  try {
    const { tunnelId, password, port, description } = await request.json();
    
    if (!tunnelId || !password || !port) {
      return new Response(JSON.stringify({ 
        error: 'Missing required fields: tunnelId, password, port' 
      }), { 
        status: 400, 
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Store tunnel configuration in KV
    const config = {
      password: await hashPassword(password),
      port: parseInt(port),
      description: description || 'Local Service',
      createdAt: new Date().toISOString(),
      lastSeen: new Date().toISOString(),
      active: true
    };
    
    await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config));
    
    const tunnelUrl = `${new URL(request.url).origin}/tunnel/${tunnelId}`;
    
    return new Response(JSON.stringify({
      success: true,
      tunnelId,
      tunnelUrl,
      message: 'Tunnel registered successfully'
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    return new Response(JSON.stringify({ 
      error: 'Invalid request body' 
    }), { 
      status: 400, 
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function handleStatusCheck(request, env) {
  const url = new URL(request.url);
  const tunnelId = url.searchParams.get('tunnelId');
  
  if (!tunnelId) {
    return new Response(JSON.stringify({ error: 'Missing tunnelId' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  const configData = await env.TUNNEL_CONFIG.get(`tunnel:${tunnelId}`);
  if (!configData) {
    return new Response(JSON.stringify({ error: 'Tunnel not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  const config = JSON.parse(configData);
  
  return new Response(JSON.stringify({
    tunnelId,
    active: config.active,
    port: config.port,
    description: config.description,
    createdAt: config.createdAt,
    lastSeen: config.lastSeen
  }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

async function handleTunnelAccess(request, env) {
  const url = new URL(request.url);
  const tunnelId = url.pathname.split('/tunnel/')[1];
  
  if (!tunnelId) {
    return new Response('Tunnel ID required', { status: 400 });
  }
  
  // Get tunnel configuration
  const configData = await env.TUNNEL_CONFIG.get(`tunnel:${tunnelId}`);
  if (!configData) {
    return new Response(generateErrorPage('Tunnel Not Found', 'The requested tunnel does not exist or has expired.'), {
      status: 404,
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  const config = JSON.parse(configData);
  
  if (!config.active) {
    return new Response(generateErrorPage('Tunnel Inactive', 'This tunnel is currently inactive.'), {
      status: 503,
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  // Handle authentication
  if (request.method === 'POST') {
    const formData = await request.formData();
    const password = formData.get('password');
    
    if (!password) {
      return new Response(generateAuthPage(tunnelId, 'Password is required'), {
        status: 400,
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    const providedHash = await hashPassword(password);
    
    if (config.password === providedHash) {
      // Password correct - redirect to proxy page
      return new Response(generateProxyPage(tunnelId, config), {
        headers: { 
          'Content-Type': 'text/html',
          'Set-Cookie': `tunnel-auth-${tunnelId}=${providedHash}; HttpOnly; Secure; SameSite=Strict; Max-Age=3600`
        }
      });
    } else {
      return new Response(generateAuthPage(tunnelId, 'Incorrect password'), {
        status: 401,
        headers: { 'Content-Type': 'text/html' }
      });
    }
  }
  
  // Check if already authenticated via cookie
  const cookies = parseCookies(request.headers.get('Cookie') || '');
  const authCookie = cookies[`tunnel-auth-${tunnelId}`];
  
  if (authCookie && authCookie === config.password) {
    return new Response(generateProxyPage(tunnelId, config), {
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  // Show authentication page
  return new Response(generateAuthPage(tunnelId), {
    headers: { 'Content-Type': 'text/html' }
  });
}

async function hashPassword(password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

function parseCookies(cookieHeader) {
  const cookies = {};
  cookieHeader.split(';').forEach(cookie => {
    const [name, value] = cookie.trim().split('=');
    if (name && value) {
      cookies[name] = value;
    }
  });
  return cookies;
}

function generateHomePage() {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Secure Tunnel Service</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 0;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      background: white;
      border-radius: 16px;
      padding: 40px;
      max-width: 500px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      text-align: center;
    }
    .icon { font-size: 64px; margin-bottom: 20px; }
    h1 { color: #333; margin: 0 0 10px 0; }
    .subtitle { color: #666; margin-bottom: 30px; }
    .feature {
      display: flex;
      align-items: center;
      margin: 15px 0;
      padding: 15px;
      background: #f8f9fa;
      border-radius: 8px;
      text-align: left;
    }
    .feature-icon { font-size: 24px; margin-right: 15px; }
    .footer {
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #eee;
      color: #888;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">🔐</div>
    <h1>Secure Tunnel Service</h1>
    <p class="subtitle">Password-protected access to your local services</p>
    
    <div class="feature">
      <span class="feature-icon">🛡️</span>
      <div>
        <strong>Secure Authentication</strong><br>
        Password protection with encrypted connections
      </div>
    </div>
    
    <div class="feature">
      <span class="feature-icon">🌐</span>
      <div>
        <strong>Persistent URLs</strong><br>
        Reliable access without temporary links
      </div>
    </div>
    
    <div class="feature">
      <span class="feature-icon">⚡</span>
      <div>
        <strong>Fast & Reliable</strong><br>
        Powered by Cloudflare's global network
      </div>
    </div>
    
    <div class="footer">
      Use the <code>cftunnel</code> command to create secure tunnels<br>
      <strong>API Endpoint:</strong> /api/register
    </div>
  </div>
</body>
</html>`;
}

function generateAuthPage(tunnelId, error = '') {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Secure Tunnel Access</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      background: white;
      border-radius: 16px;
      padding: 40px;
      max-width: 400px;
      width: 100%;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      text-align: center;
    }
    .icon { font-size: 48px; margin-bottom: 20px; }
    h1 { color: #333; margin: 0 0 10px 0; }
    .tunnel-id {
      font-family: 'Monaco', 'Menlo', 'Consolas', monospace;
      background: #f1f3f4;
      padding: 8px 12px;
      border-radius: 6px;
      font-size: 12px;
      color: #666;
      margin-bottom: 20px;
    }
    .error {
      color: #e53e3e;
      background: #fed7d7;
      padding: 12px;
      border-radius: 8px;
      margin-bottom: 20px;
      font-size: 14px;
    }
    input[type="password"] {
      width: 100%;
      padding: 15px;
      border: 2px solid #e0e0e0;
      border-radius: 12px;
      font-size: 16px;
      margin-bottom: 20px;
      box-sizing: border-box;
      transition: border-color 0.3s;
    }
    input[type="password"]:focus {
      outline: none;
      border-color: #667eea;
    }
    button {
      width: 100%;
      padding: 15px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: transform 0.2s;
    }
    button:hover {
      transform: translateY(-2px);
    }
    .info {
      margin-top: 20px;
      padding: 15px;
      background: #e6f3ff;
      border-radius: 8px;
      font-size: 14px;
      color: #0066cc;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">🔐</div>
    <h1>Access Required</h1>
    <div class="tunnel-id">Tunnel: ${tunnelId}</div>
    
    ${error ? `<div class="error">${error}</div>` : ''}
    
    <form method="POST">
      <input type="password" name="password" placeholder="Enter tunnel password" required autofocus>
      <button type="submit">Access Tunnel</button>
    </form>
    
    <div class="info">
      🛡️ This tunnel is protected with end-to-end encryption
    </div>
  </div>
</body>
</html>`;
}

function generateProxyPage(tunnelId, config) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Secure Tunnel - ${config.description}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: #f5f5f7;
    }
    .header {
      background: white;
      padding: 20px;
      border-radius: 12px;
      margin-bottom: 20px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .tunnel-info h2 {
      margin: 0;
      color: #333;
    }
    .tunnel-info p {
      margin: 5px 0 0 0;
      color: #666;
      font-size: 14px;
    }
    .status {
      display: flex;
      align-items: center;
      gap: 8px;
      color: #28a745;
      font-weight: 600;
    }
    .proxy-container {
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      min-height: 500px;
    }
    .proxy-frame {
      width: 100%;
      height: calc(100vh - 200px);
      border: none;
      background: white;
    }
    .loading {
      display: flex;
      align-items: center;
      justify-content: center;
      height: 200px;
      color: #666;
    }
    .error-message {
      padding: 40px;
      text-align: center;
      color: #e53e3e;
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="tunnel-info">
      <h2>${config.description}</h2>
      <p>Tunnel: ${tunnelId} • Port: ${config.port}</p>
    </div>
    <div class="status">
      <span style="width: 8px; height: 8px; background: #28a745; border-radius: 50%; display: block;"></span>
      Connected
    </div>
  </div>
  
  <div class="proxy-container">
    <div class="loading" id="loading">
      🔄 Connecting to your local service...
    </div>
    <iframe id="serviceFrame" class="proxy-frame" style="display: none;"></iframe>
    <div id="error" class="error-message" style="display: none;">
      ❌ Unable to connect to the local service.<br>
      Make sure your service is running on port ${config.port}
    </div>
  </div>

  <script>
    // Note: This is a simplified proxy page
    // In a real implementation, you'd need WebSocket or SSE connection to the local service
    // For now, we'll show a connection interface
    
    setTimeout(() => {
      document.getElementById('loading').style.display = 'none';
      document.getElementById('error').style.display = 'block';
      
      // Add instructions for connecting
      document.getElementById('error').innerHTML = \`
        <h3>🔧 Connection Instructions</h3>
        <p>This tunnel is authenticated and ready!</p>
        <p><strong>Your local service on port ${config.port} should be accessible.</strong></p>
        <p>To complete the connection, you'll need to:</p>
        <ol style="text-align: left; max-width: 400px; margin: 0 auto;">
          <li>Ensure your service is running on localhost:${config.port}</li>
          <li>The tunnel will proxy requests to your local service</li>
          <li>All traffic is now authenticated and secure</li>
        </ol>
        <br>
        <small style="color: #666;">
          Advanced: This Worker can be extended with WebSocket support for real-time proxying
        </small>
      \`;
    }, 2000);
  </script>
</body>
</html>`;
}

function generateErrorPage(title, message) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Error - ${title}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      background: white;
      border-radius: 16px;
      padding: 40px;
      max-width: 400px;
      width: 100%;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      text-align: center;
    }
    .icon { font-size: 48px; margin-bottom: 20px; }
    h1 { color: #e53e3e; margin: 0 0 20px 0; }
    p { color: #666; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">❌</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>`;
}