#!/usr/bin/env python3

import json
import os
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

# ── Paths ──────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ENVS_DIR = os.path.join(PROJECT_ROOT, "envs")
LOGS_DIR = os.path.join(PROJECT_ROOT, "logs")

POLL_INTERVAL = 30       # seconds between polls
FAILURE_THRESHOLD = 3    # consecutive failures before "degraded"

# Track consecutive failures per env
failure_counts = {}

def log(env_id, message):
    """Write timestamped message to env's health log."""
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    log_path = os.path.join(LOGS_DIR, env_id, "health.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    line = f"[{timestamp}] {message}"
    print(line)
    with open(log_path, "a") as f:
        f.write(line + "\n")

def get_active_envs():
    """Read all state files from envs/ directory."""
    envs = []
    if not os.path.exists(ENVS_DIR):
        return envs
    for filename in os.listdir(ENVS_DIR):
        if filename.endswith(".json"):
            path = os.path.join(ENVS_DIR, filename)
            try:
                with open(path) as f:
                    envs.append(json.load(f))
            except Exception as e:
                print(f"⚠️  Could not read {filename}: {e}")
    return envs

def update_env_status(env_id, status):
    """Update the status field in the env's state file."""
    state_path = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(state_path):
        return
    try:
        with open(state_path) as f:
            data = json.load(f)
        data["status"] = status
        # Write atomically
        tmp_path = state_path + ".tmp"
        with open(tmp_path, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_path, state_path)
    except Exception as e:
        print(f"⚠️  Could not update status for {env_id}: {e}")

def poll_env(env):
    """Poll a single env's /health endpoint."""
    env_id = env["id"]
    port = env["port"]
    url = f"http://localhost:{port}/health"

    start = time.time()
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            latency = round((time.time() - start) * 1000)  # ms
            status_code = resp.status
            log(env_id, f"✅ HTTP {status_code} — {latency}ms")

            # Reset failure count on success
            failure_counts[env_id] = 0

            # Restore status if it was degraded
            if env.get("status") == "degraded":
                update_env_status(env_id, "running")
                log(env_id, "✅ Status restored to running")

    except Exception as e:
        latency = round((time.time() - start) * 1000)
        failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
        count = failure_counts[env_id]

        log(env_id, f"❌ FAILED ({count}/{FAILURE_THRESHOLD}) — {e} — {latency}ms")

        if count >= FAILURE_THRESHOLD:
            log(env_id, f"🚨 WARNING: {env_id} is DEGRADED after {count} consecutive failures!")
            update_env_status(env_id, "degraded")

def main():
    print(f"🏥 Health poller started — polling every {POLL_INTERVAL}s")
    print(f"   Project root: {PROJECT_ROOT}")
    print(f"   Failure threshold: {FAILURE_THRESHOLD} consecutive failures")

    while True:
        envs = get_active_envs()

        if not envs:
            print(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}] 📭 No active environments to poll")
        else:
            print(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}] 🔍 Polling {len(envs)} environment(s)...")
            for env in envs:
                poll_env(env)

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()