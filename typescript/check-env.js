#!/usr/bin/env node
"""
A script to check if all required environment variables are set.
It reads the required variables from a .env.example file in the current directory.
"""
import fs from 'fs';
import path from 'path';

const envExamplePath = path.resolve(process.cwd(), '.env.example');

if (!fs.existsSync(envExamplePath)) {
  console.error('Error: .env.example file not found in the current directory.');
  process.exit(1);
}

const envExampleContent = fs.readFileSync(envExamplePath, 'utf-8');
const requiredEnvVars = envExampleContent
  .split('\n')
  .map(line => line.trim())
  .filter(line => line && !line.startsWith('#'))
  .map(line => line.split('=')[0]);

const missingVars = [];

for (const varName of requiredEnvVars) {
  if (!process.env[varName]) {
    missingVars.push(varName);
  }
}

if (missingVars.length > 0) {
  console.error('ERROR: The following required environment variables are missing:');
  missingVars.forEach(varName => console.error(`- ${varName}`));
  console.error('\nPlease set them before starting the application.');
  process.exit(1);
} else {
  console.log('✓ All required environment variables are set.');
}

