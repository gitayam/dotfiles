#!/bin/bash
# Redeploy the cffile "secure-tunnel" Worker (typescript/hybrid-tunnel.js) with
# its TUNNEL_CONFIG KV binding.
#
#   scripts/fix-cffile-worker.sh               deploy in place (the live Worker keeps serving)
#   scripts/fix-cffile-worker.sh --recreate    delete the Worker first (asks you to type its name)
#   scripts/fix-cffile-worker.sh --selftest    also register a "test-deploy" tunnel on the live Worker
#
# Earlier versions deleted the live Worker first and then deployed
# src/hybrid-tunnel.js, a path that doesn't exist, so a run ended with no
# Worker at all. Nothing here deletes or writes to production unless asked.

set -u
WORKER_NAME="secure-tunnel"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/typescript/hybrid-tunnel.js"
RECREATE=0; SELFTEST=0
for arg in "$@"; do
  case "$arg" in
    --recreate) RECREATE=1 ;;
    --selftest) SELFTEST=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

echo "🔧 cffile Worker redeploy ($WORKER_NAME)"

# Every check before anything changes
[[ -f "$SRC" ]] || { echo "❌ Worker source not found: $SRC"; exit 1; }
command -v wrangler >/dev/null || { echo "❌ wrangler not found. Install it (npm install -g wrangler) and re-run."; exit 1; }
command -v python3 >/dev/null || { echo "❌ python3 is needed to read wrangler's JSON output."; exit 1; }
if ! wrangler whoami >/dev/null 2>&1; then
  echo "❌ Not logged in to Cloudflare. Run: wrangler login"
  exit 1
fi
echo "✅ Source: ${SRC#$REPO/}; logged in to Cloudflare"

# KV namespace: reuse TUNNEL_CONFIG, or create it
KV_ID=$(wrangler kv namespace list 2>/dev/null | python3 -c '
import json, sys
try:
    print(next(n["id"] for n in json.load(sys.stdin) if n.get("title", "").endswith("TUNNEL_CONFIG")))
except (StopIteration, ValueError):
    pass')
if [[ -z "$KV_ID" ]]; then
  echo "Creating the TUNNEL_CONFIG KV namespace..."
  KV_ID=$(wrangler kv namespace create TUNNEL_CONFIG 2>&1 | grep -oE '[a-f0-9]{32}' | head -1)
  [[ -n "$KV_ID" ]] || { echo "❌ Could not create or find the TUNNEL_CONFIG KV namespace."; exit 1; }
  echo "✅ KV namespace created: $KV_ID"
else
  echo "✅ Using KV namespace $KV_ID"
fi

# Config in a temp file, removed however the script ends
CONFIG=$(mktemp "${TMPDIR:-/tmp}/wrangler-cffile.XXXXXX") || exit 1
trap 'rm -f "$CONFIG"' EXIT
cat > "$CONFIG" <<EOF
name = "$WORKER_NAME"
main = "$SRC"
compatibility_date = "2024-01-01"

[[kv_namespaces]]
binding = "TUNNEL_CONFIG"
id = "$KV_ID"
EOF

if [[ $RECREATE -eq 1 ]]; then
  echo ""
  echo "⚠️  --recreate deletes the live Worker; cffile links stop working until the deploy below succeeds."
  printf 'Type %s to confirm: ' "$WORKER_NAME"
  read -r confirm
  [[ "$confirm" == "$WORKER_NAME" ]] || { echo "Not confirmed; nothing changed."; exit 1; }
  wrangler delete --name "$WORKER_NAME" --force || { echo "❌ Delete failed; nothing else changed."; exit 1; }
fi

echo "Deploying..."
if ! wrangler deploy --config "$CONFIG"; then
  echo ""
  echo "❌ Deploy failed.$([[ $RECREATE -eq 0 ]] && echo ' The live Worker is unchanged.')"
  echo "   Manual route: dash.cloudflare.com > Workers & Pages > $WORKER_NAME > Edit code,"
  echo "   paste ${SRC#$REPO/}, and keep the TUNNEL_CONFIG KV binding ($KV_ID)."
  exit 1
fi
echo "✅ Worker deployed with the TUNNEL_CONFIG binding"

TEST_URL="https://$WORKER_NAME.wemea-5ahhf.workers.dev"
if [[ $SELFTEST -eq 1 ]]; then
  # Writes a "test-deploy" tunnel record into the live KV
  if curl -fsS -X POST "$TEST_URL/api/register" -H "Content-Type: application/json" \
       -d '{"tunnelId":"test-deploy","password":"test","port":8080,"cloudflaredUrl":"https://test.trycloudflare.com","description":"Test"}' |
     grep -q success; then
    echo "✅ Worker answered /api/register"
  else
    echo "⚠️  Worker deployed but /api/register did not answer with success"
  fi
else
  echo "Check it read-only: curl -sI $TEST_URL  (or re-run with --selftest)"
fi
echo "Test with: cffile -p mypassword somefile.txt"
