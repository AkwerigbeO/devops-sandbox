#!/bin/bash
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Arguments ─────────────────────────────────────────────
ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)   ENV_ID="$2";  shift 2 ;;
        --mode)  MODE="$2";    shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
    echo "Usage: ./simulate_outage.sh --env <env-id> --mode <crash|pause|network|recover|stress>"
    exit 1
fi

# ── Safety Guard ───────────────────────────────────────────
# Never run simulation against Nginx or daemon container
PROTECTED_CONTAINERS=("nginx-proxy" "cleanup-daemon")
for protected in "${PROTECTED_CONTAINERS[@]}"; do
    if [[ "$ENV_ID" == "$protected" ]]; then
        echo "🛑 REFUSED: Cannot simulate outage on protected container: $ENV_ID"
        exit 1
    fi
done

# Also check the env ID looks like a sandbox env
if [[ ! "$ENV_ID" =~ ^env- ]]; then
    echo "🛑 REFUSED: ENV_ID must start with 'env-'. Got: $ENV_ID"
    exit 1
fi

STATE_FILE="$PROJECT_ROOT/envs/$ENV_ID.json"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "❌ No state file found for: $ENV_ID"
    exit 1
fi

echo "💥 Simulating [$MODE] outage on: $ENV_ID"

case "$MODE" in

    crash)
        # Hard kill the container — health monitor should catch within 90s
        docker kill "$ENV_ID"
        echo "✅ Container killed — health monitor will detect within 90s"
        ;;

    pause)
        # Freeze the container — it still exists but won't respond
        docker pause "$ENV_ID"
        echo "✅ Container paused — recover with: --mode recover"
        ;;

    network)
        # Disconnect from its network — requests will time out
        NETWORK=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['network'])")
        docker network disconnect "$NETWORK" "$ENV_ID"
        echo "✅ Container disconnected from network: $NETWORK"
        echo "   Recover with: --mode recover"
        ;;

    recover)
        # Try all recovery methods
        echo "🔧 Attempting recovery for: $ENV_ID"

        # Unpause if paused
        if docker inspect "$ENV_ID" --format '{{.State.Paused}}' 2>/dev/null | grep -q true; then
            docker unpause "$ENV_ID"
            echo "✅ Container unpaused"
        fi

        # Restart if stopped/killed
        if docker inspect "$ENV_ID" --format '{{.State.Running}}' 2>/dev/null | grep -q false; then
            docker start "$ENV_ID"
            echo "✅ Container restarted"
        fi

        # Reconnect network if disconnected
        NETWORK=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['network'])")
        CONNECTED=$(docker inspect "$ENV_ID" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
        if [[ "$CONNECTED" != *"$NETWORK"* ]]; then
            docker network connect "$NETWORK" "$ENV_ID"
            echo "✅ Container reconnected to network: $NETWORK"
        fi

        echo "✅ Recovery complete"
        ;;

    stress)
        # Spike CPU inside the container with stress-ng
        if docker exec "$ENV_ID" which stress-ng &>/dev/null; then
            docker exec -d "$ENV_ID" stress-ng --cpu 2 --timeout 60s
            echo "✅ CPU stress started for 60s inside $ENV_ID"
        else
            echo "⚠️  stress-ng not found in container — installing..."
            docker exec "$ENV_ID" apt-get install -y stress-ng -q
            docker exec -d "$ENV_ID" stress-ng --cpu 2 --timeout 60s
            echo "✅ CPU stress started for 60s"
        fi
        ;;

    *)
        echo "❌ Unknown mode: $MODE"
        echo "   Valid modes: crash, pause, network, recover, stress"
        exit 1
        ;;
esac