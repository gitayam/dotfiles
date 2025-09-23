/**
 * Hybrid Tunnel Worker
 * Provides authentication layer for cloudflared tunnels
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
    const { tunnelId, password, port, description, cloudflaredUrl } = await request.json();
    
    if (!tunnelId || !password || !port || !cloudflaredUrl) {
      return new Response(JSON.stringify({ 
        error: 'Missing required fields: tunnelId, password, port, cloudflaredUrl' 
      }), { 
        status: 400, 
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Store tunnel configuration with cloudflared URL
    const config = {
      password: await hashPassword(password),
      port: parseInt(port),
      cloudflaredUrl: cloudflaredUrl, // The actual cloudflared tunnel URL
      description: description || 'Secure Tunnel',
      createdAt: new Date().toISOString(),
      lastSeen: new Date().toISOString(),
      active: true
    };
    
    await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config), {
      expirationTtl: 3600 // Expire after 1 hour
    });
    
    return new Response(JSON.stringify({
      success: true,
      authUrl: `${url.origin}/tunnel/${tunnelId}`,
      tunnelId: tunnelId
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
  
  // Update last seen
  config.lastSeen = new Date().toISOString();
  await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config), {
    expirationTtl: 3600
  });
  
  return new Response(JSON.stringify({
    tunnelId,
    active: config.active,
    port: config.port,
    description: config.description,
    createdAt: config.createdAt,
    lastSeen: config.lastSeen,
    hasCloudflared: !!config.cloudflaredUrl
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
  if (request.method === 'POST') {
    const formData = await request.formData();
    const password = formData.get('password');
    const returnPath = formData.get('returnPath') || proxyPath || '/';
    
    if (!password) {
      return new Response(generateAuthPage(tunnelId, config, 'Password is required', returnPath), {
        status: 400,
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    const providedHash = await hashPassword(password);
    
    if (config.password === providedHash) {
      // Password correct - set cookie and redirect to cloudflared URL with original path
      const redirectUrl = config.cloudflaredUrl + returnPath;
      return new Response(null, {
        status: 302,
        headers: { 
          'Location': redirectUrl,
          'Set-Cookie': `tunnel-auth-${tunnelId}=${providedHash}; HttpOnly; Secure; SameSite=Strict; Max-Age=3600`
        }
      });
    } else {
      return new Response(generateAuthPage(tunnelId, config, 'Incorrect password', returnPath), {
        status: 401,
        headers: { 'Content-Type': 'text/html' }
      });
    }
  }
  
  // Check if authenticated
  if (!authCookie || authCookie !== config.password) {
    // Show authentication page with current path
    return new Response(generateAuthPage(tunnelId, config, '', proxyPath), {
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  // User is authenticated - redirect directly to cloudflared URL with the requested path
  const redirectUrl = config.cloudflaredUrl + proxyPath + url.search;
  return Response.redirect(redirectUrl, 302);
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
  <title>Hybrid Tunnel Service</title>
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
    .feature {
      margin: 20px 0;
      padding: 15px;
      background: #f8f9fa;
      border-radius: 8px;
      text-align: left;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔐 Hybrid Tunnel Service</h1>
    <p>Authentication layer for cloudflared tunnels</p>
    <div class="feature">
      <strong>✨ How it works:</strong>
      <ol style="margin: 10px 0;">
        <li>cloudflared creates the actual tunnel</li>
        <li>This service adds password protection</li>
        <li>Users authenticate here first</li>
        <li>Then get redirected to the tunnel</li>
      </ol>
    </div>
  </div>
</body>
</html>
  `;
}

function generateAuthPage(tunnelId, config, error = '', returnPath = '/') {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Tunnel Authentication - ${config.description}</title>
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
    h1 { color: #333; margin: 0 0 10px 0; }
    .description { color: #666; margin-bottom: 20px; }
    .tunnel-id {
      font-family: monospace;
      background: #f0f0f0;
      padding: 8px 12px;
      border-radius: 6px;
      margin-bottom: 20px;
      font-size: 14px;
    }
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
    input[type="password"]:focus {
      outline: none;
      border-color: #667eea;
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
      transition: transform 0.2s;
    }
    button:hover {
      transform: translateY(-2px);
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔐 Authentication Required</h1>
    <div class="description">${config.description}</div>
    <div class="tunnel-id">Tunnel ID: ${tunnelId}</div>
    ${error ? `<div class="error">${error}</div>` : ''}
    <form method="POST">
      <input type="hidden" name="returnPath" value="${returnPath}">
      <input type="password" name="password" placeholder="Enter password" required autofocus>
      <button type="submit">Access Files</button>
    </form>
  </div>
</body>
</html>
  `;
}

function generateRedirectPage(tunnelId, config) {
  const cloudflaredUrl = config.cloudflaredUrl;
  
  return `
<!DOCTYPE html>
<html>
<head>
  <title>${config.description} - Authenticated</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="3;url=${cloudflaredUrl}">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
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
      width: 100%;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      text-align: center;
    }
    h1 { color: #28a745; margin: 0 0 20px 0; }
    .success-icon {
      font-size: 64px;
      margin-bottom: 20px;
    }
    .url-box {
      background: #f0f0f0;
      padding: 15px;
      border-radius: 8px;
      margin: 20px 0;
      word-break: break-all;
      font-family: monospace;
      font-size: 14px;
    }
    a {
      color: #667eea;
      text-decoration: none;
      font-weight: 600;
    }
    a:hover {
      text-decoration: underline;
    }
    .redirect-notice {
      color: #666;
      margin-top: 20px;
      font-size: 14px;
    }
    .spinner {
      display: inline-block;
      width: 20px;
      height: 20px;
      border: 3px solid #f0f0f0;
      border-top: 3px solid #667eea;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin-left: 10px;
      vertical-align: middle;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="success-icon">✅</div>
    <h1>Authentication Successful!</h1>
    <p>You now have access to the files.</p>
    
    <div class="url-box">
      <strong>Direct Access URL:</strong><br>
      <a href="${cloudflaredUrl}" target="_self">${cloudflaredUrl}</a>
    </div>
    
    <div class="redirect-notice">
      Redirecting to your files in 3 seconds...
      <span class="spinner"></span>
    </div>
    
    <p style="margin-top: 30px;">
      <a href="${cloudflaredUrl}">Click here if not redirected automatically</a>
    </p>
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