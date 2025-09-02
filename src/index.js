/**
 * Cloudflare Worker for MacOS Dotfiles Secrets Management
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const { pathname } = url;

    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Routes
      switch (pathname) {
        case '/':
          return handleRoot();
        
        case '/secrets':
          return handleSecrets(request, env);
        
        case '/config':
          return handleConfig(request, env);
        
        case '/health':
          return handleHealth();
        
        default:
          return new Response('Not Found', { 
            status: 404, 
            headers: corsHeaders 
          });
      }
    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({ 
        error: 'Internal Server Error',
        message: error.message 
      }), {
        status: 500,
        headers: { 
          'Content-Type': 'application/json',
          ...corsHeaders 
        }
      });
    }
  }
};

function handleRoot() {
  return new Response(JSON.stringify({
    service: 'MacOS Dotfiles Secrets Manager',
    version: '1.0.0',
    endpoints: [
      'GET /secrets - List available secrets',
      'POST /secrets - Create/update secrets',
      'GET /config - Get configuration',
      'GET /health - Health check'
    ]
  }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

async function handleSecrets(request, env) {
  const method = request.method;
  
  // For now, just return a list of available secret keys
  // In production, you'd use KV namespaces or env variables
  const secretKeys = [
    'REMOTE_HOST',
    'REMOTE_PORT',
    'REMOTE_BASE_PATH',
    'GPG_KEY',
    'TWILIO_ACCOUNT_SID',
    'TWILIO_API_KEY',
    'TWILIO_API_SECRET',
    'TWILIO_AUTH_TOKEN',
    'AWS_PROFILE',
    'AWS_REGION',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_ORG_ID'
  ];

  if (method === 'GET') {
    return new Response(JSON.stringify({
      available_secrets: secretKeys,
      note: 'Secrets are managed via wrangler CLI'
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }

  if (method === 'POST') {
    const { key, value } = await request.json();
    
    if (!key) {
      return new Response(JSON.stringify({
        error: 'Key is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      message: `Secret ${key} would be updated (use wrangler CLI for actual updates)`
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }

  return new Response('Method Not Allowed', { status: 405 });
}

async function handleConfig(request, env) {
  return new Response(JSON.stringify({
    environment: env.ENVIRONMENT || 'development',
    log_level: env.LOG_LEVEL || 'info',
    timestamp: new Date().toISOString()
  }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

function handleHealth() {
  return new Response(JSON.stringify({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: Date.now()
  }), {
    headers: { 'Content-Type': 'application/json' }
  });
}