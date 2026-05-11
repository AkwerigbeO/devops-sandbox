#!/bin/bash
set -euo pipefail

# ── Arguments ────────────────────────────────────────────
ENV_NAME="${1:-}"
TTL="${2:-1800}"   # default 30 minutes in seconds

if [[ -z "$ENV_NAME" ]]; then
  echo "Usage: ./create_env.sh <name> [ttl_seconds]"
  exit 1
fi

# ── Generate unique ID ────────────────────────────────────
ENV_ID="env-$(echo $ENV_NAME | tr '[:upper:]' '[:lower:]' | tr ' ' '-')-$(date +%s)"
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PORT=$(shuf -i 4000-9000 -n 1)   # random available port
NETWORK_NAME="net-$ENV_ID"
STATE_FILE="envs/$ENV_ID.json"

echo "🚀 Creating environment: $ENV_ID"

# ── Create Docker network ─────────────────────────────────
docker network create "$NETWORK_NAME"
echo "✅ Network created: $NETWORK_NAME"

# ── Start app container ───────────────────────────────────
docker run -d \
  --name "$ENV_ID" \
  --network "$NETWORK_NAME" \
  --label "sandbox.env=$ENV_ID" \
  -p "$PORT:5000" \
  demo-app

echo "✅ Container started on port $PORT"

# ── Write state file (atomic) ─────────────────────────────
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" <<EOF
{
  "id": "$ENV_ID",
  "name": "$ENV_NAME",
  "created_at": "$CREATED_AT",
  "ttl": $TTL,
  "port": $PORT,
  "network": "$NETWORK_NAME",
  "status": "running"
}
EOF
mv "$TEMP_FILE" "$STATE_FILE"
echo "✅ State file written: $STATE_FILE"

# ── Set up log directory ──────────────────────────────────
mkdir -p "logs/$ENV_ID"

# ── Start log shipping (Approach A) ──────────────────────
docker logs -f "$ENV_ID" >> "logs/$ENV_ID/app.log" 2>&1 &
LOG_PID=$!
echo "$LOG_PID" > "logs/$ENV_ID/log.pid"
echo "✅ Log shipping started (PID: $LOG_PID)"

# ── Register Nginx route ──────────────────────────────────
cat > "nginx/conf.d/$ENV_ID.conf" <<EOF
server {
    listen 80;
    server_name $ENV_ID.localhost;

    location / {
        proxy_pass http://host.docker.internal:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

docker exec nginx-proxy nginx -s reload 2>/dev/null || echo "⚠️  Nginx reload skipped (not running yet)"
echo "✅ Nginx route registered"

# ── Done ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ENV ID  : $ENV_ID"
echo "  URL     : http://$ENV_ID.localhost"
echo "  PORT    : $PORT"
echo "  TTL     : ${TTL}s ($(( TTL / 60 )) minutes)"
echo "  EXPIRES : $(date -u -d "+${TTL} seconds" +"%Y-%m-%dT%H:%M:%SZ")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"