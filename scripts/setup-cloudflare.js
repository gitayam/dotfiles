#!/usr/bin/env node

/**
 * Setup script for Cloudflare Workers and R2 integration
 * Usage: node scripts/setup-cloudflare.js
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const WRANGLER_CONFIG = path.join(__dirname, '..', 'wrangler.toml');
const WRANGLER_TEMPLATE = path.join(__dirname, '..', 'wrangler.template.toml');

function checkWranglerAuth() {
  try {
    console.log('🔍 Checking Wrangler authentication...');
    execSync('wrangler whoami', { stdio: 'pipe' });
    console.log('✅ Wrangler is authenticated');
    return true;
  } catch (error) {
    console.log('❌ Wrangler not authenticated');
    console.log('Run: wrangler login');
    return false;
  }
}

function createR2Bucket(bucketName) {
  try {
    console.log(`📦 Creating R2 bucket: ${bucketName}...`);
    execSync(`wrangler r2 bucket create ${bucketName}`, { stdio: 'inherit' });
    console.log(`✅ R2 bucket '${bucketName}' created successfully`);
    return true;
  } catch (error) {
    if (error.message.includes('already exists')) {
      console.log(`✅ R2 bucket '${bucketName}' already exists`);
      return true;
    } else {
      console.log(`❌ Failed to create R2 bucket '${bucketName}':`, error.message);
      return false;
    }
  }
}

function listR2Buckets() {
  try {
    console.log('📋 Listing existing R2 buckets...');
    const output = execSync('wrangler r2 bucket list', { encoding: 'utf8' });
    console.log(output);
    return true;
  } catch (error) {
    console.log('❌ Failed to list R2 buckets:', error.message);
    return false;
  }
}

function deployWorker() {
  try {
    console.log('🚀 Deploying worker...');
    execSync('wrangler deploy', { stdio: 'inherit' });
    console.log('✅ Worker deployed successfully');
    return true;
  } catch (error) {
    console.log('❌ Failed to deploy worker:', error.message);
    return false;
  }
}

async function main() {
  console.log('🚀 Setting up Cloudflare Workers and R2...');
  console.log('');

  // Check authentication
  if (!checkWranglerAuth()) {
    console.log('');
    console.log('Please authenticate with Cloudflare first:');
    console.log('  wrangler login');
    process.exit(1);
  }

  // List existing buckets
  console.log('');
  listR2Buckets();

  // Create default R2 buckets
  const defaultBuckets = ['files', 'screenshots', 'backups', 'images'];
  
  console.log('');
  console.log('📦 Creating default R2 buckets...');
  
  for (const bucket of defaultBuckets) {
    createR2Bucket(bucket);
  }

  // Check if wrangler.toml exists
  if (!fs.existsSync(WRANGLER_CONFIG)) {
    if (fs.existsSync(WRANGLER_TEMPLATE)) {
      console.log('');
      console.log('📄 Copying wrangler.template.toml to wrangler.toml...');
      fs.copyFileSync(WRANGLER_TEMPLATE, WRANGLER_CONFIG);
      console.log('✅ Configuration file created');
      
      console.log('');
      console.log('⚠️  Please edit wrangler.toml to add your specific IDs:');
      console.log('   - KV namespace IDs');
      console.log('   - D1 database IDs');
      console.log('   - Custom domain routes');
      console.log('   - Zone IDs');
    }
  }

  // Deploy worker
  console.log('');
  if (deployWorker()) {
    console.log('');
    console.log('🎉 Setup complete!');
    console.log('');
    console.log('Next steps:');
    console.log('1. Test your functions: cflist, cfu, cfshot');
    console.log('2. Upload your first file: cfu ~/some-file.txt');
    console.log('3. Take a screenshot: cfshot');
    console.log('4. Backup your dotfiles: cfbak');
  } else {
    console.log('');
    console.log('⚠️  Worker deployment failed. Check the errors above.');
    console.log('You can still use R2 functions (cfu, cfshot, etc.)');
  }
}

if (require.main === module) {
  main();
}