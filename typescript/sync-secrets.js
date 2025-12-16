#!/usr/bin/env node

/**
 * Sync local .env secrets to Cloudflare Workers
 * Usage: npm run secrets:sync
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ENV_FILE = path.join(__dirname, '..', '.env');

function parseEnvFile() {
  if (!fs.existsSync(ENV_FILE)) {
    throw new Error(`.env file not found at ${ENV_FILE}`);
  }

  const envContent = fs.readFileSync(ENV_FILE, 'utf8');
  const secrets = {};
  
  const lines = envContent.split('\\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const [key, ...valueParts] = trimmed.split('=');
      if (key && valueParts.length > 0) {
        secrets[key] = valueParts.join('=');
      }
    }
  }
  
  return secrets;
}

function syncSecretToWrangler(key, value) {
  try {
    console.log(`🔄 Syncing secret: ${key}`);
    
    // Use echo to pipe the value to wrangler secret put
    const command = `echo "${value}" | wrangler secret put ${key}`;
    execSync(command, { stdio: 'inherit' });
    
    console.log(`✅ Successfully synced: ${key}`);
    return true;
  } catch (error) {
    console.error(`❌ Failed to sync ${key}:`, error.message);
    return false;
  }
}

async function main() {
  try {
    console.log('🚀 Starting secrets sync to Cloudflare Workers...');
    
    const secrets = parseEnvFile();
    const secretKeys = Object.keys(secrets);
    
    if (secretKeys.length === 0) {
      console.log('⚠️  No secrets found in .env file');
      return;
    }
    
    console.log(`📋 Found ${secretKeys.length} secrets to sync:`);
    secretKeys.forEach(key => console.log(`  - ${key}`));
    
    let successCount = 0;
    let failureCount = 0;
    
    for (const [key, value] of Object.entries(secrets)) {
      // Skip empty values
      if (!value || value.trim() === '') {
        console.log(`⚠️  Skipping empty value for: ${key}`);
        continue;
      }
      
      if (syncSecretToWrangler(key, value)) {
        successCount++;
      } else {
        failureCount++;
      }
    }
    
    console.log('\\n📊 Sync Summary:');
    console.log(`✅ Successful: ${successCount}`);
    console.log(`❌ Failed: ${failureCount}`);
    
    if (failureCount > 0) {
      console.log('\\n⚠️  Some secrets failed to sync. Check the errors above.');
      process.exit(1);
    } else {
      console.log('\\n🎉 All secrets synced successfully!');
    }
    
  } catch (error) {
    console.error('❌ Error syncing secrets:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}