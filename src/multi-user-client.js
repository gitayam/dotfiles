#!/usr/bin/env node

/**
 * Multi-User Tunnel Client
 * Creates tunnels with multiple users, permissions, and admin controls
 */

const http = require('http');
const crypto = require('crypto');

// Configuration
const WORKER_URL = 'https://secure-tunnel.wemea-5ahhf.workers.dev';

async function createMultiUserTunnel(port, adminPassword, users, description, maxUsers = 10) {
  const tunnelId = generateTunnelId();
  
  try {
    const response = await fetch(`${WORKER_URL}/api/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        tunnelId,
        adminPassword,
        users,
        port: parseInt(port),
        description: description || `Multi-user service on port ${port}`,
        maxUsers: parseInt(maxUsers)
      })
    });
    
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }
    
    const result = await response.json();
    
    console.log('\n🎉 Multi-user tunnel created successfully!');
    console.log(`\n🔗 Tunnel URL: ${result.tunnelUrl}`);
    console.log(`🔧 Admin URL: ${result.adminUrl}`);
    console.log(`🆔 Tunnel ID: ${tunnelId}`);
    console.log(`🔑 Admin Password: ${adminPassword}`);
    console.log(`🎯 Local Port: ${port}`);
    console.log(`👥 Users: ${result.userCount}`);
    
    console.log('\n👥 User Credentials:');
    users.forEach((user, index) => {
      console.log(`   ${index + 1}. Username: ${user.username}, Password: ${user.password}, Permissions: [${user.permissions?.join(', ') || 'read'}]`);
    });
    
    // Copy URL to clipboard if pbcopy is available
    try {
      const { exec } = require('child_process');
      exec(`echo "${result.tunnelUrl}" | pbcopy`, (error) => {
        if (!error) {
          console.log(`\n📋 Tunnel URL copied to clipboard`);
        }
      });
    } catch (e) {
      // Ignore clipboard errors
    }
    
    console.log('\n💡 Share individual credentials with each user');
    console.log('🛡️  All access is authenticated with user-level permissions');
    console.log('🔧 Use the Admin URL to manage users and monitor activity');
    
    return { tunnelId, tunnelUrl: result.tunnelUrl, adminUrl: result.adminUrl };
    
  } catch (error) {
    console.error(`❌ Failed to create multi-user tunnel: ${error.message}`);
    process.exit(1);
  }
}

async function addUserToTunnel(tunnelId, adminPassword, username, password, permissions = ['read']) {
  try {
    const response = await fetch(`${WORKER_URL}/api/users?tunnelId=${tunnelId}&adminPassword=${encodeURIComponent(adminPassword)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        username,
        password,
        permissions
      })
    });
    
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }
    
    const result = await response.json();
    
    console.log(`✅ User '${username}' added successfully to tunnel ${tunnelId}`);
    console.log(`🔑 Credentials: ${username} / ${password}`);
    console.log(`🛡️  Permissions: [${permissions.join(', ')}]`);
    
    return result;
    
  } catch (error) {
    console.error(`❌ Failed to add user: ${error.message}`);
    process.exit(1);
  }
}

async function listUsers(tunnelId, adminPassword) {
  try {
    const response = await fetch(`${WORKER_URL}/api/users?tunnelId=${tunnelId}&adminPassword=${encodeURIComponent(adminPassword)}`);
    
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }
    
    const result = await response.json();
    
    console.log(`\n👥 Users for tunnel ${tunnelId}:`);
    console.log(`📊 Total: ${result.totalUsers} / ${result.maxUsers} users`);
    console.log(`🔗 Active Sessions: ${result.currentSessions}`);
    console.log('');
    
    result.users.forEach((user, index) => {
      console.log(`${index + 1}. 👤 ${user.username}`);
      console.log(`   🛡️  Permissions: [${user.permissions.join(', ')}]`);
      console.log(`   📅 Created: ${new Date(user.createdAt).toLocaleString()}`);
      console.log(`   👀 Last Access: ${user.lastAccess ? new Date(user.lastAccess).toLocaleString() : 'Never'}`);
      console.log(`   📊 Access Count: ${user.accessCount} times`);
      console.log('');
    });
    
    return result;
    
  } catch (error) {
    console.error(`❌ Failed to list users: ${error.message}`);
    process.exit(1);
  }
}

function parseUsersFromString(usersStr) {
  try {
    // Support multiple formats:
    // 1. JSON: [{"username":"user1","password":"pass1","permissions":["read"]}]
    // 2. Simple: user1:pass1,user2:pass2
    // 3. With permissions: user1:pass1:read,write;user2:pass2:admin
    
    if (usersStr.startsWith('[')) {
      // JSON format
      return JSON.parse(usersStr);
    }
    
    // Parse simple formats
    const users = [];
    const userEntries = usersStr.split(';');
    
    for (const entry of userEntries) {
      const parts = entry.split(':');
      if (parts.length < 2) {
        throw new Error(`Invalid user format: ${entry}. Expected username:password[:permissions]`);
      }
      
      const username = parts[0].trim();
      const password = parts[1].trim();
      const permissions = parts[2] ? parts[2].split(',').map(p => p.trim()) : ['read'];
      
      users.push({ username, password, permissions });
    }
    
    return users;
    
  } catch (error) {
    throw new Error(`Failed to parse users: ${error.message}`);
  }
}

function generateTunnelId() {
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

function startKeepAlive(port, tunnelId, adminPassword) {
  console.log('\n🔄 Starting keep-alive service...');
  console.log('🛑 Press Ctrl+C to stop the tunnel');
  
  // Enhanced HTTP server with admin status
  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'active',
        type: 'multi-user',
        tunnelId,
        port,
        timestamp: new Date().toISOString()
      }));
    } else if (req.url === '/admin') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(`
        <!DOCTYPE html>
        <html>
        <head><title>Multi-User Tunnel Admin</title></head>
        <body>
          <h1>🔧 Multi-User Tunnel Control</h1>
          <p><strong>Tunnel ID:</strong> ${tunnelId}</p>
          <p><strong>Local Port:</strong> ${port}</p>
          <p><strong>Type:</strong> Multi-User Secure Tunnel</p>
          <p><strong>Status:</strong> Running</p>
          <p><strong>Time:</strong> ${new Date().toISOString()}</p>
          
          <h2>🔗 Links</h2>
          <p><a href="${WORKER_URL}/tunnel/${tunnelId}" target="_blank">Tunnel Access URL</a></p>
          <p><a href="${WORKER_URL}/admin?tunnel=${tunnelId}" target="_blank">Admin Dashboard</a></p>
          
          <h2>📋 Quick Commands</h2>
          <pre>
# Add user
node multi-user-client.js adduser ${tunnelId} [admin-password] [username] [password] [permissions]

# List users  
node multi-user-client.js users ${tunnelId} [admin-password]
          </pre>
        </body>
        </html>
      `);
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(`
        <!DOCTYPE html>
        <html>
        <head><title>Multi-User Tunnel Active</title></head>
        <body>
          <h1>👥 Multi-User Secure Tunnel Active</h1>
          <p><strong>Tunnel ID:</strong> ${tunnelId}</p>
          <p><strong>Local Port:</strong> ${port}</p>
          <p><strong>Type:</strong> Multi-User with Individual Credentials</p>
          <p><strong>Status:</strong> Running</p>
          <p><strong>Time:</strong> ${new Date().toISOString()}</p>
          
          <h2>🎯 Access Information</h2>
          <p><strong>Tunnel URL:</strong> <a href="${WORKER_URL}/tunnel/${tunnelId}">${WORKER_URL}/tunnel/${tunnelId}</a></p>
          <p><strong>Admin Dashboard:</strong> <a href="${WORKER_URL}/admin?tunnel=${tunnelId}">Admin Panel</a></p>
          
          <p><em>Each user needs individual credentials to access the tunnel.</em></p>
        </body>
        </html>
      `);
    }
  });
  
  // Find available port for keep-alive server
  let keepAlivePort = 3200;
  const tryListen = () => {
    server.listen(keepAlivePort, () => {
      console.log(`📡 Keep-alive server running on http://localhost:${keepAlivePort}`);
      console.log(`🔧 Local admin interface: http://localhost:${keepAlivePort}/admin`);
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
    console.log('\n\n🛑 Shutting down multi-user tunnel...');
    server.close(() => {
      console.log('✅ Multi-user tunnel stopped');
      process.exit(0);
    });
  });
  
  process.on('SIGTERM', () => {
    console.log('\n\n🛑 Shutting down multi-user tunnel...');
    server.close(() => {
      console.log('✅ Multi-user tunnel stopped');
      process.exit(0);
    });
  });
}

// Main execution
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];
  
  if (!command) {
    console.log(`
Multi-User Secure Tunnel Client

Usage:
  node multi-user-client.js create <port> <admin-password> <users> [description] [max-users]
  node multi-user-client.js adduser <tunnel-id> <admin-password> <username> <password> [permissions]
  node multi-user-client.js users <tunnel-id> <admin-password>

Examples:
  # Create tunnel with 2 users
  node multi-user-client.js create 8080 admin123 "user1:pass1;user2:pass2" "My Web App"
  
  # Create with permissions  
  node multi-user-client.js create 8080 admin123 "alice:secret:read,write;bob:pass:read" "Team App" 5
  
  # Add user to existing tunnel
  node multi-user-client.js adduser swift-eagle-123 admin123 charlie newpass "read,write"
  
  # List all users
  node multi-user-client.js users swift-eagle-123 admin123

User Format:
  Simple: username:password
  With permissions: username:password:permission1,permission2
  Multiple users: user1:pass1;user2:pass2:read,write
`);
    process.exit(1);
  }
  
  if (command === 'create') {
    const port = args[1];
    const adminPassword = args[2];
    const usersStr = args[3];
    const description = args[4];
    const maxUsers = args[5];
    
    if (!port || !adminPassword || !usersStr) {
      console.error('❌ Missing required arguments: port, admin-password, users');
      process.exit(1);
    }
    
    // Validate port number
    const portNum = parseInt(port);
    if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
      console.error('❌ Invalid port number');
      process.exit(1);
    }
    
    // Parse users
    let users;
    try {
      users = parseUsersFromString(usersStr);
    } catch (error) {
      console.error(`❌ ${error.message}`);
      process.exit(1);
    }
    
    if (users.length === 0) {
      console.error('❌ At least one user is required');
      process.exit(1);
    }
    
    console.log(`🚀 Creating multi-user tunnel for port ${port}...`);
    console.log(`👥 Users: ${users.length}`);
    console.log(`🔑 Admin password: ${adminPassword}`);
    
    // Create tunnel
    const result = await createMultiUserTunnel(port, adminPassword, users, description, maxUsers);
    
    // Start keep-alive
    startKeepAlive(port, result.tunnelId, adminPassword);
    
  } else if (command === 'adduser') {
    const tunnelId = args[1];
    const adminPassword = args[2];
    const username = args[3];
    const password = args[4];
    const permissionsStr = args[5] || 'read';
    
    if (!tunnelId || !adminPassword || !username || !password) {
      console.error('❌ Missing required arguments: tunnel-id, admin-password, username, password');
      process.exit(1);
    }
    
    const permissions = permissionsStr.split(',').map(p => p.trim());
    
    await addUserToTunnel(tunnelId, adminPassword, username, password, permissions);
    
  } else if (command === 'users') {
    const tunnelId = args[1];
    const adminPassword = args[2];
    
    if (!tunnelId || !adminPassword) {
      console.error('❌ Missing required arguments: tunnel-id, admin-password');
      process.exit(1);
    }
    
    await listUsers(tunnelId, adminPassword);
    
  } else {
    console.error(`❌ Unknown command: ${command}`);
    process.exit(1);
  }
}

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('❌ Unexpected error:', error.message);
  process.exit(1);
});

if (require.main === module) {
  main();
}