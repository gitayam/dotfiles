#!/usr/bin/env node

/**
 * Cloudflare Worker secrets cannot be read back: `wrangler secret list` shows
 * names only, by design. This script used to "fetch" them, could never get a
 * value, and still rewrote .env. It now only lists the names Cloudflare has,
 * so you can compare them with your .env, and changes nothing.
 *
 * Keep the values where you created them (a mode-600 file outside the repo,
 * or your password manager) and push them with: npm run secrets:sync
 *
 * Usage: npm run secrets:get
 */

const { execFileSync } = require('child_process');

try {
  const out = execFileSync('wrangler', ['secret', 'list'], { encoding: 'utf8' });
  const names = JSON.parse(out).map((s) => s.name).sort();
  console.log(`Cloudflare has ${names.length} secret(s) for this Worker (values can't be read back):`);
  names.forEach((name) => console.log(`  - ${name}`));
} catch (error) {
  console.error('Could not list secrets with wrangler:', error.message.split('\n')[0]);
  process.exit(1);
}
