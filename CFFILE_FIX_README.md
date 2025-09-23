# cffile Password Authentication Fix

## Problem
When using `cffile` with password protection (e.g., `cffile -p mypass file.txt`), the Worker shows a "Connection Instructions" page instead of redirecting to your actual files after authentication.

## Root Cause
The deployed Worker at `secure-tunnel.wemea-5ahhf.workers.dev` is using outdated code that doesn't properly handle the hybrid authentication + cloudflared tunnel approach.

## Solution

We provide two fix methods depending on whether wrangler is working:

### Method 1: Automated Fix (if wrangler works)
```bash
./fix-cffile-worker.sh
```

This script will:
1. Authenticate with Cloudflare (if needed)
2. Delete the old Worker
3. Create necessary KV namespace
4. Deploy the new hybrid Worker
5. Test the deployment

### Method 2: Manual Fix (if wrangler is broken)
```bash
./fix-cffile-manual.sh
```

This will:
1. Prepare the Worker code for copying
2. Open it in TextEdit
3. Provide step-by-step manual deployment instructions

Then follow these steps in the Cloudflare Dashboard:

1. **Delete old Worker**:
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
   - Workers & Pages → `secure-tunnel` → Settings → Delete

2. **Create new Worker**:
   - Click Create → Create Worker
   - Name: `secure-tunnel` (must be exact)
   - Click Deploy

3. **Add the code**:
   - Click "Edit code"
   - Delete all existing code
   - Paste code from TextEdit
   - Save and deploy

4. **Add KV namespace**:
   - Settings → Variables → KV Namespace Bindings
   - Add binding: `TUNNEL_CONFIG`

## Testing the Fix

After deployment, test with:
```bash
# Test with password
cffile -p testpass somefile.txt

# Or test the Worker directly
/tmp/test-cffile-fix.sh
```

## What the Fix Does

The updated Worker:
- ✅ Properly handles authentication
- ✅ Redirects directly to cloudflared URL after login
- ✅ Preserves file paths through authentication
- ✅ No more "Connection Instructions" page

## How cffile Works After Fix

1. **Without password** (`cffile file.txt` or `cffile --no-auth file.txt`):
   - Creates cloudflared tunnel
   - Gives you direct public URL
   - No authentication needed

2. **With password** (`cffile -p mypass file.txt`):
   - Creates cloudflared tunnel
   - Registers with Worker for authentication
   - Gives you both URLs:
     - Public URL (direct, no password)
     - Protected URL (requires password)
   - After entering password, redirects to files

## Files Involved

- **Worker Code**: `src/hybrid-tunnel.js` - The fixed Worker code
- **Shell Script**: `cffile-hybrid.sh` - The main cffile implementation
- **Fix Scripts**: 
  - `fix-cffile-worker.sh` - Automated fix
  - `fix-cffile-manual.sh` - Manual fix helper
- **Worker URL**: `https://secure-tunnel.wemea-5ahhf.workers.dev`

## Troubleshooting

If the fix doesn't work:

1. **Check Worker is deployed**:
   ```bash
   curl -s https://secure-tunnel.wemea-5ahhf.workers.dev/
   ```
   Should show the Worker home page.

2. **Check Worker version**:
   ```bash
   /tmp/test-cffile-fix.sh
   ```
   Should show "✅ Worker is working correctly!"

3. **If wrangler hangs**:
   ```bash
   # Reset wrangler
   rm -rf ~/Library/Preferences/.wrangler/
   killall node wrangler 2>/dev/null
   npm uninstall -g wrangler
   npm install -g wrangler@latest
   wrangler login
   ```

4. **Alternative Worker name**:
   If `secure-tunnel` name is taken or problematic:
   - Deploy as `secure-tunnel-v2`
   - Update `cffile-hybrid.sh` line 10:
     ```bash
     WORKER_URL="https://secure-tunnel-v2.YOUR-SUBDOMAIN.workers.dev"
     ```

## For Dotfiles Users

Anyone using these dotfiles should run the fix once:
```bash
# Option 1: If you have wrangler working
./fix-cffile-worker.sh

# Option 2: If wrangler is broken
./fix-cffile-manual.sh
# Then follow the manual steps
```

This is a one-time fix. Once deployed, the Worker will work correctly for all future uses of `cffile`.