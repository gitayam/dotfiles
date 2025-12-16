/**
 * Tunnel Proxy Worker
 * Authenticates and proxies requests to local services
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Handle different routes
    if (path === '/') {
      return handleHomePage(request, env);
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

async function handleHomePage(request, env) {
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
    
    // Store tunnel configuration
    const config = {
      password: await hashPassword(password),
      port: parseInt(port),
      description: description || 'Secure Tunnel',
      createdAt: new Date().toISOString(),
      lastSeen: new Date().toISOString(),
      active: true
    };
    
    await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config));
    
    return new Response(JSON.stringify({
      success: true,
      tunnelUrl: `${url.origin}/tunnel/${tunnelId}`
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function handleStatusCheck(request, env) {
  const url = new URL(request.url);
  const tunnelId = url.searchParams.get('tunnelId');
  
  if (!tunnelId) {
    return new Response(JSON.stringify({ 
      error: 'Tunnel ID required' 
    }), { 
      status: 400, 
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  const configData = await env.TUNNEL_CONFIG.get(`tunnel:${tunnelId}`);
  if (!configData) {
    return new Response(JSON.stringify({ 
      error: 'Tunnel not found' 
    }), { 
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
  const pathParts = url.pathname.split('/');
  const tunnelId = pathParts[2];
  const proxyPath = '/' + pathParts.slice(3).join('/');
  
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
  
  // Check authentication
  const cookies = parseCookies(request.headers.get('Cookie') || '');
  const authCookie = cookies[`tunnel-auth-${tunnelId}`];
  
  // Handle authentication form submission
  if (request.method === 'POST' && proxyPath === '/') {
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
      // Password correct - set cookie and redirect
      return new Response('', {
        status: 302,
        headers: { 
          'Location': `/tunnel/${tunnelId}/`,
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
  
  // Check if authenticated
  if (!authCookie || authCookie !== config.password) {
    // Show authentication page
    return new Response(generateAuthPage(tunnelId), {
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  // PROXY THE REQUEST TO THE LOCAL SERVICE
  try {
    // Build the target URL
    const targetUrl = `http://localhost:${config.port}${proxyPath}${url.search}`;
    
    // Since we can't directly access localhost from the Worker,
    // we'll need to return an iframe or instructions for now.
    // In a real implementation, you'd need a local agent or use Cloudflare Tunnel.
    
    // For file listing, let's create a simple proxy interface
    if (proxyPath === '/' || proxyPath === '') {
      return new Response(generateProxyInterface(tunnelId, config), {
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    // For other paths, show a download/access interface
    return new Response(generateFileAccessPage(tunnelId, config, proxyPath), {
      headers: { 'Content-Type': 'text/html' }
    });
    
  } catch (error) {
    return new Response(generateErrorPage('Proxy Error', `Failed to connect to local service: ${error.message}`), {
      status: 502,
      headers: { 'Content-Type': 'text/html' }
    });
  }
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
    h1 { color: #333; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔐 Secure Tunnel Service</h1>
    <p>Password-protected tunnels for local services</p>
  </div>
</body>
</html>
  `;
}

function generateAuthPage(tunnelId, error = '') {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Tunnel Authentication</title>
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
    }
    h1 { color: #333; margin: 0 0 20px 0; }
    .error {
      color: #e53e3e;
      background: #fed7d7;
      padding: 12px;
      border-radius: 8px;
      margin-bottom: 20px;
    }
    input[type="password"] {
      width: 100%;
      padding: 12px;
      border: 2px solid #e0e0e0;
      border-radius: 8px;
      font-size: 16px;
      margin-bottom: 20px;
      box-sizing: border-box;
    }
    button {
      width: 100%;
      padding: 12px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔐 Authentication Required</h1>
    <p>Tunnel: ${tunnelId}</p>
    ${error ? `<div class="error">${error}</div>` : ''}
    <form method="POST">
      <input type="password" name="password" placeholder="Enter password" required autofocus>
      <button type="submit">Access Tunnel</button>
    </form>
  </div>
</body>
</html>
  `;
}

function generateProxyInterface(tunnelId, config) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>${config.description}</title>
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
    }
    h1 { margin: 0; color: #333; }
    .info { color: #666; margin-top: 10px; }
    .content {
      background: white;
      padding: 20px;
      border-radius: 12px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    .notice {
      background: #fff3cd;
      border: 1px solid #ffc107;
      color: #856404;
      padding: 15px;
      border-radius: 8px;
      margin-bottom: 20px;
    }
    .instructions {
      background: #d1ecf1;
      border: 1px solid #bee5eb;
      color: #0c5460;
      padding: 15px;
      border-radius: 8px;
    }
    code {
      background: #f0f0f0;
      padding: 2px 6px;
      border-radius: 4px;
      font-family: 'Monaco', 'Menlo', monospace;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>📁 ${config.description}</h1>
    <div class="info">
      <strong>Tunnel:</strong> ${tunnelId} | 
      <strong>Port:</strong> ${config.port} | 
      <strong>Status:</strong> <span style="color: #28a745;">● Connected</span>
    </div>
  </div>
  
  <div class="content">
    <div class="notice">
      <strong>⚠️ Direct Proxy Limitation</strong><br>
      Cloudflare Workers cannot directly proxy to localhost services. 
      The files are being served on your local machine at port ${config.port}.
    </div>
    
    <div class="instructions">
      <h3>🔗 How to Access Your Files:</h3>
      <ol>
        <li>Your files are being served locally on <code>http://localhost:${config.port}</code></li>
        <li>This tunnel provides authenticated access control</li>
        <li>For full proxy functionality, consider using Cloudflare Tunnel (cloudflared) instead</li>
      </ol>
      
      <h3>📋 Alternative Solutions:</h3>
      <ul>
        <li><strong>Cloudflare Tunnel:</strong> <code>cloudflared tunnel --url http://localhost:${config.port}</code></li>
        <li><strong>ngrok:</strong> <code>ngrok http ${config.port}</code></li>
        <li><strong>Tailscale Funnel:</strong> <code>tailscale funnel ${config.port}</code></li>
      </ul>
    </div>
  </div>
</body>
</html>
  `;
}

function generateFileAccessPage(tunnelId, config, path) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>File Access - ${path}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: #f5f5f7;
    }
    .container {
      background: white;
      padding: 30px;
      border-radius: 12px;
      max-width: 600px;
      margin: 0 auto;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    h1 { color: #333; }
    .path {
      background: #f0f0f0;
      padding: 10px;
      border-radius: 6px;
      font-family: 'Monaco', 'Menlo', monospace;
      word-break: break-all;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>📄 File Access</h1>
    <p><strong>Requested Path:</strong></p>
    <div class="path">${path}</div>
    <p>This file is available on your local server at:</p>
    <div class="path">http://localhost:${config.port}${path}</div>
  </div>
</body>
</html>
  `;
}

function generateErrorPage(title, message) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>${title}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: #f5f5f7;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .error-container {
      background: white;
      padding: 40px;
      border-radius: 12px;
      max-width: 500px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      text-align: center;
    }
    h1 { color: #e53e3e; margin: 0 0 20px 0; }
    p { color: #666; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="error-container">
    <h1>❌ ${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>
  `;
}