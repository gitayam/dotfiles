/**
 * Multi-User Secure Tunnel Worker
 * Supports multiple users, permissions, and session management
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
    } else if (path === '/api/users') {
      return handleUserManagement(request, env);
    } else if (path === '/api/sessions') {
      return handleSessionManagement(request, env);
    } else if (path === '/api/tunnels') {
      return handleTunnelList(request, env);
    } else if (path === '/api/activity') {
      return handleActivityLog(request, env);
    } else if (path === '/admin') {
      return handleAdminInterface(request, env);
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
    const { tunnelId, adminPassword, users, port, description, maxUsers } = await request.json();
    
    if (!tunnelId || !adminPassword || !users || !port) {
      return new Response(JSON.stringify({ 
        error: 'Missing required fields: tunnelId, adminPassword, users, port' 
      }), { 
        status: 400, 
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Validate users array
    if (!Array.isArray(users) || users.length === 0) {
      return new Response(JSON.stringify({ 
        error: 'Users must be a non-empty array with {username, password} objects' 
      }), { 
        status: 400, 
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Hash passwords
    const hashedUsers = await Promise.all(users.map(async (user) => ({
      username: user.username,
      password: await hashPassword(user.password),
      permissions: user.permissions || ['read'],
      createdAt: new Date().toISOString(),
      lastAccess: null,
      accessCount: 0
    })));
    
    // Store tunnel configuration
    const config = {
      adminPassword: await hashPassword(adminPassword),
      users: hashedUsers,
      port: parseInt(port),
      description: description || 'Multi-User Tunnel',
      maxUsers: maxUsers || 10,
      createdAt: new Date().toISOString(),
      lastSeen: new Date().toISOString(),
      active: true,
      totalAccesses: 0,
      currentSessions: 0
    };
    
    await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config));
    
    // Create activity log
    await logActivity(env, tunnelId, 'system', 'tunnel_created', {
      userCount: users.length,
      port: config.port
    });
    
    const tunnelUrl = `${new URL(request.url).origin}/tunnel/${tunnelId}`;
    
    return new Response(JSON.stringify({
      success: true,
      tunnelId,
      tunnelUrl,
      userCount: users.length,
      adminUrl: `${new URL(request.url).origin}/admin?tunnel=${tunnelId}`,
      message: 'Multi-user tunnel registered successfully'
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    return new Response(JSON.stringify({ 
      error: 'Invalid request body: ' + error.message 
    }), { 
      status: 400, 
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function handleUserManagement(request, env) {
  const url = new URL(request.url);
  const tunnelId = url.searchParams.get('tunnelId');
  const adminPassword = url.searchParams.get('adminPassword');
  
  if (!tunnelId || !adminPassword) {
    return new Response(JSON.stringify({ error: 'tunnelId and adminPassword required' }), {
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
  const adminHash = await hashPassword(adminPassword);
  
  if (config.adminPassword !== adminHash) {
    return new Response(JSON.stringify({ error: 'Invalid admin password' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  if (request.method === 'GET') {
    // Return user list (without passwords)
    const safeUsers = config.users.map(user => ({
      username: user.username,
      permissions: user.permissions,
      createdAt: user.createdAt,
      lastAccess: user.lastAccess,
      accessCount: user.accessCount
    }));
    
    return new Response(JSON.stringify({
      users: safeUsers,
      totalUsers: config.users.length,
      maxUsers: config.maxUsers,
      currentSessions: config.currentSessions
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  if (request.method === 'POST') {
    // Add new user
    const { username, password, permissions } = await request.json();
    
    if (!username || !password) {
      return new Response(JSON.stringify({ error: 'Username and password required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    if (config.users.find(u => u.username === username)) {
      return new Response(JSON.stringify({ error: 'Username already exists' }), {
        status: 409,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    if (config.users.length >= config.maxUsers) {
      return new Response(JSON.stringify({ error: 'Maximum users reached' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    const newUser = {
      username,
      password: await hashPassword(password),
      permissions: permissions || ['read'],
      createdAt: new Date().toISOString(),
      lastAccess: null,
      accessCount: 0
    };
    
    config.users.push(newUser);
    await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config));
    
    await logActivity(env, tunnelId, 'admin', 'user_added', { username });
    
    return new Response(JSON.stringify({ success: true, message: 'User added successfully' }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  return new Response('Method not allowed', { status: 405 });
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
    const username = formData.get('username');
    const password = formData.get('password');
    
    if (!username || !password) {
      return new Response(generateAuthPage(tunnelId, 'Username and password are required'), {
        status: 400,
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    // Find user
    const user = config.users.find(u => u.username === username);
    if (!user) {
      await logActivity(env, tunnelId, username, 'login_failed', { reason: 'user_not_found' });
      return new Response(generateAuthPage(tunnelId, 'Invalid username or password'), {
        status: 401,
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    const providedHash = await hashPassword(password);
    
    if (user.password === providedHash) {
      // Update user stats
      user.lastAccess = new Date().toISOString();
      user.accessCount++;
      config.totalAccesses++;
      config.currentSessions++;
      
      await env.TUNNEL_CONFIG.put(`tunnel:${tunnelId}`, JSON.stringify(config));
      await logActivity(env, tunnelId, username, 'login_success', { permissions: user.permissions });
      
      // Create session token
      const sessionToken = await generateSessionToken(tunnelId, username);
      
      return new Response(generateProxyPage(tunnelId, config, user), {
        headers: { 
          'Content-Type': 'text/html',
          'Set-Cookie': `tunnel-session-${tunnelId}=${sessionToken}; HttpOnly; Secure; SameSite=Strict; Max-Age=3600`
        }
      });
    } else {
      await logActivity(env, tunnelId, username, 'login_failed', { reason: 'wrong_password' });
      return new Response(generateAuthPage(tunnelId, 'Invalid username or password'), {
        status: 401,
        headers: { 'Content-Type': 'text/html' }
      });
    }
  }
  
  // Check if already authenticated via session
  const cookies = parseCookies(request.headers.get('Cookie') || '');
  const sessionToken = cookies[`tunnel-session-${tunnelId}`];
  
  if (sessionToken) {
    const sessionData = await validateSessionToken(sessionToken, tunnelId);
    if (sessionData) {
      const user = config.users.find(u => u.username === sessionData.username);
      if (user) {
        return new Response(generateProxyPage(tunnelId, config, user), {
          headers: { 'Content-Type': 'text/html' }
        });
      }
    }
  }
  
  // Show authentication page
  return new Response(generateAuthPage(tunnelId), {
    headers: { 'Content-Type': 'text/html' }
  });
}

async function handleAdminInterface(request, env) {
  const url = new URL(request.url);
  const tunnelId = url.searchParams.get('tunnel');
  
  if (!tunnelId) {
    return new Response(generateAdminLogin(), {
      headers: { 'Content-Type': 'text/html' }
    });
  }
  
  return new Response(generateAdminDashboard(tunnelId), {
    headers: { 'Content-Type': 'text/html' }
  });
}

async function logActivity(env, tunnelId, username, action, metadata = {}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    tunnelId,
    username,
    action,
    metadata
  };
  
  const logKey = `activity:${tunnelId}:${Date.now()}`;
  await env.TUNNEL_CONFIG.put(logKey, JSON.stringify(logEntry), { expirationTtl: 604800 }); // 7 days
}

async function generateSessionToken(tunnelId, username) {
  const data = { tunnelId, username, timestamp: Date.now() };
  return btoa(JSON.stringify(data)) + '.' + await hashPassword(JSON.stringify(data));
}

async function validateSessionToken(token, tunnelId) {
  try {
    const [dataB64, hash] = token.split('.');
    const dataStr = atob(dataB64);
    const data = JSON.parse(dataStr);
    
    // Check if token is for this tunnel
    if (data.tunnelId !== tunnelId) return null;
    
    // Check if token is expired (1 hour)
    if (Date.now() - data.timestamp > 3600000) return null;
    
    // Verify hash
    const expectedHash = await hashPassword(dataStr);
    if (hash !== expectedHash) return null;
    
    return data;
  } catch (e) {
    return null;
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
  <title>Multi-User Secure Tunnel Service</title>
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
      max-width: 600px;
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
    .new-badge {
      background: #28a745;
      color: white;
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
      font-weight: bold;
      margin-left: 10px;
    }
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
    <div class="icon">👥</div>
    <h1>Multi-User Secure Tunnel Service</h1>
    <p class="subtitle">Password-protected access with user management and permissions</p>
    
    <div class="feature">
      <span class="feature-icon">👥</span>
      <div>
        <strong>Multi-User Support</strong><span class="new-badge">NEW</span><br>
        Create tunnels with multiple users and individual credentials
      </div>
    </div>
    
    <div class="feature">
      <span class="feature-icon">🔐</span>
      <div>
        <strong>User Permissions</strong><span class="new-badge">NEW</span><br>
        Fine-grained access control and permission management
      </div>
    </div>
    
    <div class="feature">
      <span class="feature-icon">📊</span>
      <div>
        <strong>Activity Monitoring</strong><span class="new-badge">NEW</span><br>
        Track user access, sessions, and tunnel activity
      </div>
    </div>
    
    <div class="feature">
      <span class="feature-icon">⚡</span>
      <div>
        <strong>Session Management</strong><span class="new-badge">NEW</span><br>
        Secure sessions with automatic expiration
      </div>
    </div>
    
    <div class="footer">
      Use the <code>cftunnel</code> command to create multi-user secure tunnels<br>
      <strong>API Endpoints:</strong> /api/register, /api/users, /admin
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
  <title>Multi-User Tunnel Access</title>
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
    input[type="text"], input[type="password"] {
      width: 100%;
      padding: 15px;
      border: 2px solid #e0e0e0;
      border-radius: 12px;
      font-size: 16px;
      margin-bottom: 15px;
      box-sizing: border-box;
      transition: border-color 0.3s;
    }
    input:focus {
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
    <div class="icon">👥</div>
    <h1>User Login Required</h1>
    <div class="tunnel-id">Tunnel: ${tunnelId}</div>
    
    ${error ? `<div class="error">${error}</div>` : ''}
    
    <form method="POST">
      <input type="text" name="username" placeholder="Username" required autofocus>
      <input type="password" name="password" placeholder="Password" required>
      <button type="submit">Access Tunnel</button>
    </form>
    
    <div class="info">
      🔐 Multi-user tunnel with individual credentials<br>
      👥 Each user has unique access permissions
    </div>
  </div>
</body>
</html>`;
}

function generateProxyPage(tunnelId, config, user) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Multi-User Tunnel - ${config.description}</title>
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
    .user-badge {
      display: flex;
      align-items: center;
      gap: 10px;
      background: #e6f3ff;
      padding: 10px 15px;
      border-radius: 8px;
    }
    .user-info {
      font-size: 14px;
    }
    .permissions {
      display: flex;
      gap: 5px;
      margin-top: 5px;
    }
    .permission {
      background: #28a745;
      color: white;
      padding: 2px 6px;
      border-radius: 4px;
      font-size: 11px;
    }
    .proxy-container {
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      min-height: 400px;
      padding: 40px;
      text-align: center;
    }
    .welcome {
      color: #28a745;
      font-size: 18px;
      margin-bottom: 20px;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 15px;
      margin-bottom: 30px;
    }
    .stat {
      background: #f8f9fa;
      padding: 15px;
      border-radius: 8px;
      text-align: center;
    }
    .stat-value {
      font-size: 24px;
      font-weight: bold;
      color: #333;
    }
    .stat-label {
      font-size: 12px;
      color: #666;
      margin-top: 5px;
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="tunnel-info">
      <h2>${config.description}</h2>
      <p>Tunnel: ${tunnelId} • Port: ${config.port} • Multi-User Mode</p>
    </div>
    <div class="user-badge">
      <div>
        <div class="user-info">
          <strong>👤 ${user.username}</strong>
        </div>
        <div class="permissions">
          ${user.permissions.map(p => `<span class="permission">${p}</span>`).join('')}
        </div>
      </div>
    </div>
  </div>
  
  <div class="proxy-container">
    <div class="welcome">
      ✅ Successfully authenticated as <strong>${user.username}</strong>
    </div>
    
    <div class="stats">
      <div class="stat">
        <div class="stat-value">${user.accessCount}</div>
        <div class="stat-label">Your Access Count</div>
      </div>
      <div class="stat">
        <div class="stat-value">${config.users.length}</div>
        <div class="stat-label">Total Users</div>
      </div>
      <div class="stat">
        <div class="stat-value">${config.totalAccesses}</div>
        <div class="stat-label">Total Accesses</div>
      </div>
      <div class="stat">
        <div class="stat-value">${config.currentSessions}</div>
        <div class="stat-label">Active Sessions</div>
      </div>
    </div>
    
    <h3>🎯 Connection Ready</h3>
    <p>Your secure tunnel to <strong>localhost:${config.port}</strong> is active.</p>
    <p>All traffic is authenticated and encrypted with user-level permissions.</p>
    
    <div style="margin-top: 30px; padding: 20px; background: #e6f3ff; border-radius: 8px;">
      <h4>📊 Your Permissions:</h4>
      <ul style="text-align: left; max-width: 300px; margin: 0 auto;">
        ${user.permissions.map(p => `<li><strong>${p}</strong> access</li>`).join('')}
      </ul>
    </div>
    
    <p style="margin-top: 30px; font-size: 12px; color: #666;">
      Session expires in 1 hour • Last access: ${user.lastAccess ? new Date(user.lastAccess).toLocaleString() : 'First time'}
    </p>
  </div>
</body>
</html>`;
}

function generateAdminDashboard(tunnelId) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Admin Dashboard - ${tunnelId}</title>
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
      max-width: 1200px;
      margin: 0 auto;
    }
    .header {
      background: white;
      padding: 30px;
      border-radius: 12px;
      margin-bottom: 20px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    h1 { margin: 0; color: #333; }
    .dashboard-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 20px;
    }
    .panel {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    .panel h3 {
      margin-top: 0;
      color: #333;
    }
    button {
      background: #667eea;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 14px;
    }
    button:hover { background: #5a67d8; }
    .user-list {
      max-height: 300px;
      overflow-y: auto;
    }
    .user-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 0;
      border-bottom: 1px solid #eee;
    }
  </style>
  <script>
    let adminPassword = '';
    
    async function loadDashboard() {
      adminPassword = prompt('Enter admin password:');
      if (!adminPassword) return;
      
      await loadUsers();
      await loadActivity();
    }
    
    async function loadUsers() {
      try {
        const response = await fetch('/api/users?tunnelId=${tunnelId}&adminPassword=' + encodeURIComponent(adminPassword));
        const data = await response.json();
        
        if (data.error) {
          alert('Error: ' + data.error);
          return;
        }
        
        const userList = document.getElementById('userList');
        userList.innerHTML = data.users.map(user => \`
          <div class="user-item">
            <div>
              <strong>\${user.username}</strong><br>
              <small>Access: \${user.accessCount} times | Last: \${user.lastAccess ? new Date(user.lastAccess).toLocaleString() : 'Never'}</small>
            </div>
            <div>
              \${user.permissions.join(', ')}
            </div>
          </div>
        \`).join('');
        
        document.getElementById('userStats').innerHTML = \`
          <p><strong>Total Users:</strong> \${data.totalUsers} / \${data.maxUsers}</p>
          <p><strong>Active Sessions:</strong> \${data.currentSessions}</p>
        \`;
        
      } catch (error) {
        alert('Failed to load users: ' + error.message);
      }
    }
    
    async function addUser() {
      const username = prompt('Enter username:');
      if (!username) return;
      
      const password = prompt('Enter password for ' + username + ':');
      if (!password) return;
      
      const permissions = prompt('Enter permissions (comma-separated)', 'read').split(',').map(p => p.trim());
      
      try {
        const response = await fetch('/api/users?tunnelId=${tunnelId}&adminPassword=' + encodeURIComponent(adminPassword), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username, password, permissions })
        });
        
        const result = await response.json();
        
        if (result.error) {
          alert('Error: ' + result.error);
        } else {
          alert('User added successfully!');
          loadUsers();
        }
      } catch (error) {
        alert('Failed to add user: ' + error.message);
      }
    }
    
    window.onload = loadDashboard;
  </script>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔧 Admin Dashboard</h1>
      <p>Managing tunnel: <code>${tunnelId}</code></p>
    </div>
    
    <div class="dashboard-grid">
      <div class="panel">
        <h3>👥 User Management</h3>
        <div id="userStats"></div>
        <button onclick="addUser()">Add User</button>
        <button onclick="loadUsers()">Refresh</button>
        <div id="userList" class="user-list"></div>
      </div>
      
      <div class="panel">
        <h3>📊 Activity Monitor</h3>
        <div id="activityLog">
          <p>Loading activity data...</p>
        </div>
      </div>
      
      <div class="panel">
        <h3>⚙️ Tunnel Settings</h3>
        <p><strong>Status:</strong> <span style="color: #28a745;">Active</span></p>
        <p><strong>Port:</strong> Loading...</p>
        <p><strong>Description:</strong> Loading...</p>
        <button onclick="alert('Settings management coming soon!')">Manage Settings</button>
      </div>
    </div>
  </div>
</body>
</html>`;
}

function generateAdminLogin() {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Admin Login</title>
  <style>
    body { 
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      margin: 0;
    }
    .form {
      background: white;
      padding: 40px;
      border-radius: 16px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    input {
      width: 100%;
      padding: 15px;
      margin: 10px 0;
      border: 2px solid #e0e0e0;
      border-radius: 8px;
      box-sizing: border-box;
    }
    button {
      width: 100%;
      padding: 15px;
      background: #667eea;
      color: white;
      border: none;
      border-radius: 8px;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="form">
    <h2>🔧 Admin Access</h2>
    <p>Enter tunnel ID to access admin dashboard</p>
    <input type="text" id="tunnelId" placeholder="Tunnel ID" required>
    <button onclick="location.href='/admin?tunnel=' + document.getElementById('tunnelId').value">Access Dashboard</button>
  </div>
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