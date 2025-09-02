#!/usr/bin/env node

/**
 * Test script to simulate login form submission
 */

async function testLogin(tunnelId, username, password) {
  const url = `https://secure-tunnel.wemea-5ahhf.workers.dev/tunnel/${tunnelId}`;
  
  console.log(`Testing login for tunnel: ${tunnelId}`);
  console.log(`Username: ${username}`);
  console.log(`Password: ${password}`);
  console.log('');
  
  try {
    // Create form data
    const formData = new FormData();
    formData.append('username', username);
    formData.append('password', password);
    
    // Submit login
    const response = await fetch(url, {
      method: 'POST',
      body: formData
    });
    
    console.log(`Response status: ${response.status}`);
    console.log(`Response headers:`, Object.fromEntries(response.headers.entries()));
    
    const content = await response.text();
    
    if (response.ok && content.includes('Multi-User Tunnel Control')) {
      console.log('✅ Login successful!');
      console.log('Response contains tunnel control interface');
    } else if (content.includes('Invalid username or password')) {
      console.log('❌ Login failed: Invalid credentials');
    } else if (content.includes('Username and password are required')) {
      console.log('❌ Login failed: Missing credentials');
    } else {
      console.log('❓ Unexpected response');
      console.log('First 200 chars:', content.substring(0, 200));
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

// Main execution
const args = process.argv.slice(2);
if (args.length !== 3) {
  console.log('Usage: node test-login.js <tunnel-id> <username> <password>');
  console.log('Example: node test-login.js eagle-ocean-975 alice secret123');
  process.exit(1);
}

testLogin(args[0], args[1], args[2]);