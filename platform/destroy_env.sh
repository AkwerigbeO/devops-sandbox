#!/bin/bash
set -euo pipefail

# ── Arguments ─────────────────────────────────────────────
ENV_ID="${1:-}"

if [[ -z "$ENV_ID" ]]; then
  echo "Usage: ./destroy_env.sh <env-id>"
  exit 1
fi

STATE_FILE="envs/$ENV_ID.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ No state file found for: $ENV_ID"
  exit 1
fi

echo "💥 Destroying environment: $ENV_ID"

# ── Read network name from state file ─────────────────────
NETWORK_NAME=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['network'])")

# ── Kill log shipping process ─────────────────────────────
LOG_PID_FILE="logs/$ENV_ID/log.pid"
if [[ -f "$LOG_PID_FILE" ]]; then
  LOG_PID=$(cat "$LOG_PID_FILE")
  kill "$LOG_PID" 2>/dev/null && echo "✅ Log shipping stopped (PID: $LOG_PID)"
  rm -f "$LOG_PID_FILE"
fi

# ── Stop & remove all labeled containers ──────────────────
CONTAINERS=$(docker ps -aq --filter "label=sandbox.env=$ENV_ID")
if [[ -n "$CONTAINERS" ]]; then
  docker stop $CONTAINERS
  docker rm $CONTAINERS
  echo "✅ Containers removed"
fi

# ── Remove Docker network ─────────────────────────────────
docker network rm "$NETWORK_NAME" 2>/dev/null && echo "✅ Network removed"

# ── Remove Nginx config and reload ────────────────────────
NGINX_CONF="nginx/conf.d/$ENV_ID.conf"
if [[ -f "$NGINX_CONF" ]]; then
  rm -f "$NGINX_CONF"
  docker exec nginx-proxy nginx -s reload 2>/dev/null || echo "⚠️  Nginx reload skipped"
  echo "✅ Nginx config removed"
fi

# ── Archive logs ──────────────────────────────────────────
if [[ -d "logs/$ENV_ID" ]]; then
  mkdir -p "logs/archived"
  mv "logs/$ENV_ID" "logs/archived/$ENV_ID"
  echo "✅ Logs archived"
fi

# ── Delete state file ─────────────────────────────────────
rm -f "$STATE_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Environment $ENV_ID destroyed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"