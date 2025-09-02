/**
 * Cloudflare Worker for password-protected file sharing
 * Files are stored in R2 with metadata containing the password hash
 */

import { createHash } from 'crypto';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.slice(1); // Remove leading slash
    
    // Handle root path
    if (!path) {
      return new Response(generateHomePage(), {
        headers: { 'Content-Type': 'text/html' }
      });
    }

    // Handle password verification
    if (request.method === 'POST') {
      const formData = await request.formData();
      const password = formData.get('password');
      const filename = formData.get('filename');
      
      // Get file metadata from R2
      const object = await env.PROTECTED_FILES.head(filename);
      if (!object) {
        return new Response('File not found', { status: 404 });
      }
      
      // Check password
      const storedHash = object.customMetadata?.passwordHash;
      const providedHash = await hashPassword(password);
      
      if (storedHash === providedHash) {
        // Password correct - serve the file
        const file = await env.PROTECTED_FILES.get(filename);
        const headers = new Headers();
        file.writeHttpMetadata(headers);
        headers.set('Content-Disposition', `attachment; filename="${filename}"`);
        
        return new Response(file.body, { headers });
      } else {
        // Wrong password
        return new Response(generatePasswordPage(filename, 'Incorrect password'), {
          status: 401,
          headers: { 'Content-Type': 'text/html' }
        });
      }
    }
    
    // Check if file exists and needs password
    const object = await env.PROTECTED_FILES.head(path);
    if (!object) {
      return new Response('File not found', { status: 404 });
    }
    
    // If file has password, show password form
    if (object.customMetadata?.passwordHash) {
      return new Response(generatePasswordPage(path), {
        headers: { 'Content-Type': 'text/html' }
      });
    }
    
    // No password - serve directly
    const file = await env.PROTECTED_FILES.get(path);
    const headers = new Headers();
    file.writeHttpMetadata(headers);
    
    return new Response(file.body, { headers });
  }
};

async function hashPassword(password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

function generateHomePage() {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <title>Protected Files</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          max-width: 600px;
          margin: 50px auto;
          padding: 20px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
        }
        .container {
          background: white;
          border-radius: 12px;
          padding: 30px;
          box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 { color: #333; }
        p { color: #666; line-height: 1.6; }
        .icon { font-size: 48px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">🔒</div>
        <h1>Protected File Sharing</h1>
        <p>This is a password-protected file sharing service.</p>
        <p>To access a file, use the direct link provided to you.</p>
      </div>
    </body>
    </html>
  `;
}

function generatePasswordPage(filename, error = '') {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <title>Password Required</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          max-width: 400px;
          margin: 100px auto;
          padding: 20px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
        }
        .container {
          background: white;
          border-radius: 12px;
          padding: 30px;
          box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h2 { color: #333; margin-bottom: 10px; }
        .filename {
          color: #666;
          font-size: 14px;
          margin-bottom: 20px;
          word-break: break-all;
        }
        input[type="password"] {
          width: 100%;
          padding: 12px;
          border: 2px solid #e0e0e0;
          border-radius: 8px;
          font-size: 16px;
          margin-bottom: 15px;
          box-sizing: border-box;
        }
        input[type="password"]:focus {
          outline: none;
          border-color: #667eea;
        }
        button {
          width: 100%;
          padding: 12px;
          background: #667eea;
          color: white;
          border: none;
          border-radius: 8px;
          font-size: 16px;
          font-weight: 600;
          cursor: pointer;
        }
        button:hover {
          background: #5a67d8;
        }
        .error {
          color: #e53e3e;
          font-size: 14px;
          margin-bottom: 15px;
        }
        .icon { 
          font-size: 48px; 
          text-align: center;
          margin-bottom: 20px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">🔐</div>
        <h2>Password Required</h2>
        <div class="filename">File: ${filename}</div>
        ${error ? `<div class="error">${error}</div>` : ''}
        <form method="POST">
          <input type="hidden" name="filename" value="${filename}">
          <input type="password" name="password" placeholder="Enter password" required autofocus>
          <button type="submit">Access File</button>
        </form>
      </div>
    </body>
    </html>
  `;
}