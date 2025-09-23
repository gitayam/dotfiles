# Deployment Instructions for Hybrid Tunnel Worker

## Problem
The current `secure-tunnel` Worker deployed at https://secure-tunnel.wemea-5ahhf.workers.dev is using the old code that doesn't properly handle the hybrid approach with cloudflared.

## Solution
Deploy the `hybrid-tunnel.js` Worker to replace the current `secure-tunnel` Worker.

## Manual Deployment Steps

1. **Via Cloudflare Dashboard:**
   - Go to https://dash.cloudflare.com
   - Navigate to Workers & Pages
   - Find the `secure-tunnel` Worker
   - Click "Quick edit" 
   - Copy the entire contents of `src/hybrid-tunnel.js`
   - Paste it into the editor
   - Click "Save and Deploy"

2. **Via Wrangler (when it's working):**
   ```bash
   wrangler deploy src/hybrid-tunnel.js --name secure-tunnel --compatibility-date 2024-01-01
   ```

3. **Alternative Wrangler Command:**
   ```bash
   # Using the custom config file
   wrangler deploy --config wrangler-hybrid.toml
   ```

## Key Changes in the New Worker

1. **Direct Redirect After Auth**: After successful authentication, the Worker now directly redirects to the cloudflared URL instead of showing an intermediate page.

2. **Path Preservation**: The requested file path is preserved through the authentication flow and included in the redirect.

3. **No More Proxy Attempt**: The Worker no longer tries to proxy files itself - it only handles authentication and then redirects to cloudflared.

## Testing

After deployment, test with:
```bash
cffile_function ./some-file.txt -p testpass
```

The flow should be:
1. Access the protected URL
2. Enter password
3. Immediately redirect to the cloudflared URL showing your files
4. No "Connection Instructions" page should appear

## Files Involved

- **Worker Code**: `/Users/sac/Git/dotfiles/macos/src/hybrid-tunnel.js`
- **Shell Script**: `/Users/sac/Git/dotfiles/macos/cffile-hybrid.sh`
- **Worker URL**: `https://secure-tunnel.wemea-5ahhf.workers.dev`