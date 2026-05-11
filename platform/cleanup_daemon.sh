#!/bin/bash
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$PROJECT_ROOT/envs"
LOG_FILE="$PROJECT_ROOT/logs/cleanup.log"

mkdir -p "$PROJECT_ROOT/logs"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" | tee -a "$LOG_FILE"
}

log "🚀 Cleanup daemon started (PID: $$)"

# ── Main Loop ─────────────────────────────────────────────
while true; do
    log "🔍 Scanning environments..."

    # Check if any state files exist
    if ls "$ENVS_DIR"/*.json 2>/dev/null | grep -q .; then

        for STATE_FILE in "$ENVS_DIR"/*.json; do
            # Extract fields from state file
            ENV_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['id'])")
            CREATED_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['created_at'])")
            TTL=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ttl'])")
            STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['status'])")

            # Calculate expiry time
            CREATED_TS=$(date -d "$CREATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED_AT" +%s)
            EXPIRY_TS=$(( CREATED_TS + TTL ))
            NOW_TS=$(date +%s)
            REMAINING=$(( EXPIRY_TS - NOW_TS ))

            if [[ $NOW_TS -ge $EXPIRY_TS ]]; then
                log "⏰ ENV $ENV_ID has expired (TTL: ${TTL}s) — destroying..."
                bash "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG_FILE" 2>&1
                log "✅ ENV $ENV_ID destroyed"
            else
                log "✅ ENV $ENV_ID OK — ${REMAINING}s remaining"
            fi
        done

    else
        log "📭 No active environments"
    fi

    log "😴 Sleeping 60 seconds..."
    sleep 60
done