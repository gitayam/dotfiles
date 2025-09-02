#!/usr/bin/env node

/**
 * Get secrets from Cloudflare Workers and populate .env file
 * Usage: npm run secrets:get
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ENV_FILE = path.join(__dirname, '..', '.env');
const ENV_BACKUP_DIR = path.join(__dirname, '..', '.env-backups');

// Secret mappings from Cloudflare to local .env
const SECRET_MAPPINGS = {
  'REMOTE_HOST': 'REMOTE_HOST',
  'REMOTE_PORT': 'REMOTE_PORT', 
  'REMOTE_BASE_PATH': 'REMOTE_BASE_PATH',
  'GPG_KEY': 'GPG_KEY',
  'TWILIO_ACCOUNT_SID': 'TWILIO_ACCOUNT_SID',
  'TWILIO_API_KEY': 'TWILIO_API_KEY',
  'TWILIO_API_SECRET': 'TWILIO_API_SECRET',
  'TWILIO_AUTH_TOKEN': 'TWILIO_AUTH_TOKEN',
  'AWS_PROFILE': 'AWS_PROFILE',
  'AWS_REGION': 'AWS_REGION',
  'AWS_ACCESS_KEY_ID': 'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY': 'AWS_SECRET_ACCESS_KEY',
  'AWS_ORG_ID': 'AWS_ORG_ID',
  'RCLONE_REMOTE': 'RCLONE_REMOTE',
  'RCLONE_BASE_PATH': 'RCLONE_BASE_PATH',
  'RCLONE_CONFIG': 'RCLONE_CONFIG'
};

function createBackup() {
  if (!fs.existsSync(ENV_FILE)) {
    console.log('No existing .env file to backup');
    return;
  }

  if (!fs.existsSync(ENV_BACKUP_DIR)) {
    fs.mkdirSync(ENV_BACKUP_DIR, { recursive: true });
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = path.join(ENV_BACKUP_DIR, `.env.${timestamp}`);
  
  fs.copyFileSync(ENV_FILE, backupPath);
  console.log(`✅ Backup created: ${backupPath}`);
}

function getSecretFromWrangler(secretName) {
  try {
    // Note: wrangler secret list only shows names, not values
    // For actual secret retrieval, you'd need to implement this in a Worker
    console.log(`🔍 Checking for secret: ${secretName}`);
    
    // This is a placeholder - actual implementation would call your worker
    const result = execSync(`wrangler secret list | grep -q "${secretName}"`, 
      { encoding: 'utf8', stdio: 'pipe' });
    
    return null; // Secrets can't be retrieved directly via CLI
  } catch (error) {
    console.log(`❌ Secret ${secretName} not found or error occurred`);
    return null;
  }
}

function updateEnvFile(secrets) {
  let envContent = '';
  
  if (fs.existsSync(ENV_FILE)) {
    envContent = fs.readFileSync(ENV_FILE, 'utf8');
  }

  // Add header comment
  const header = '#~/.env file\\n\\n';
  if (!envContent.includes(header.replace('\\n', '\\n'))) {
    envContent = header.replace(/\\n/g, '\\n') + envContent;
  }

  for (const [localKey, cloudflareKey] of Object.entries(SECRET_MAPPINGS)) {
    const secretValue = secrets[cloudflareKey];
    if (secretValue) {
      const regex = new RegExp(`^${localKey}=.*$`, 'm');
      const newLine = `${localKey}=${secretValue}`;
      
      if (regex.test(envContent)) {
        envContent = envContent.replace(regex, newLine);
      } else {
        envContent += `${newLine}\\n`;
      }
    }
  }

  fs.writeFileSync(ENV_FILE, envContent);
  console.log(`✅ Updated ${ENV_FILE}`);
}

async function main() {
  try {
    console.log('🚀 Starting secrets sync from Cloudflare Workers...');
    
    // Create backup of existing .env
    createBackup();
    
    // Get list of available secrets
    const secretList = execSync('wrangler secret list', { encoding: 'utf8' });
    console.log('📋 Available secrets:', secretList);
    
    // Note: For security, actual secret values need to be retrieved
    // by calling your Cloudflare Worker, not via CLI
    console.log('⚠️  To retrieve actual secret values, implement a Worker endpoint');
    console.log('⚠️  that returns secrets to authorized requests');
    
    const secrets = {};
    
    // This would be replaced with actual worker call:
    // const response = await fetch('https://your-worker.your-subdomain.workers.dev/secrets');
    // secrets = await response.json();
    
    updateEnvFile(secrets);
    
  } catch (error) {
    console.error('❌ Error syncing secrets:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}