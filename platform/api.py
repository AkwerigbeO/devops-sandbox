#!/usr/bin/env python3

from flask import Flask, jsonify, request
import subprocess
import json
import os
from datetime import datetime, timezone

app = Flask(__name__)

# ── Paths ──────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ENVS_DIR = os.path.join(PROJECT_ROOT, "envs")
LOGS_DIR = os.path.join(PROJECT_ROOT, "logs")

# ── Helpers ────────────────────────────────────────────────
def get_env(env_id):
    """Read a single env state file."""
    path = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)

def get_all_envs():
    """Read all env state files."""
    envs = []
    if not os.path.exists(ENVS_DIR):
        return envs
    for filename in os.listdir(ENVS_DIR):
        if filename.endswith(".json"):
            path = os.path.join(ENVS_DIR, filename)
            try:
                with open(path) as f:
                    envs.append(json.load(f))
            except:
                pass
    return envs

def ttl_remaining(env):
    """Calculate seconds remaining before env expires."""
    created = datetime.strptime(env["created_at"], "%Y-%m-%dT%H:%M:%SZ")
    created = created.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    elapsed = (now - created).total_seconds()
    remaining = env["ttl"] - elapsed
    return max(0, int(remaining))

def run_script(cmd):
    """Run a bash script and return output."""
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT
    )
    return result.returncode, result.stdout, result.stderr

# ── Routes ─────────────────────────────────────────────────

# POST /envs — create new environment
@app.route("/envs", methods=["POST"])
def create_env():
    data = request.get_json() or {}
    name = data.get("name")
    ttl  = data.get("ttl", 1800)

    if not name:
        return jsonify({"error": "name is required"}), 400

    code, stdout, stderr = run_script([
        "bash", "platform/create_env.sh", name, str(ttl)
    ])

    if code != 0:
        return jsonify({"error": stderr or "Failed to create env"}), 500

    # Find the newly created env (most recent state file)
    envs = sorted(get_all_envs(), key=lambda e: e["created_at"], reverse=True)
    new_env = envs[0] if envs else {}

    return jsonify({
        "message": "Environment created",
        "env": new_env,
        "output": stdout
    }), 201


# GET /envs — list all active envs with TTL remaining
@app.route("/envs", methods=["GET"])
def list_envs():
    envs = get_all_envs()
    result = []
    for env in envs:
        result.append({
            **env,
            "ttl_remaining": ttl_remaining(env),
            "url": f"http://{env['id']}.localhost"
        })
    return jsonify({"envs": result, "count": len(result)})


# DELETE /envs/:id — destroy environment
@app.route("/envs/<env_id>", methods=["DELETE"])
def destroy_env(env_id):
    env = get_env(env_id)
    if not env:
        return jsonify({"error": f"Environment {env_id} not found"}), 404

    code, stdout, stderr = run_script([
        "bash", "platform/destroy_env.sh", env_id
    ])

    if code != 0:
        return jsonify({"error": stderr or "Failed to destroy env"}), 500

    return jsonify({"message": f"Environment {env_id} destroyed"})


# GET /envs/:id/logs — last 100 lines of app.log
@app.route("/envs/<env_id>/logs", methods=["GET"])
def get_logs(env_id):
    # Check archived logs too
    log_path = os.path.join(LOGS_DIR, env_id, "app.log")
    archived_path = os.path.join(LOGS_DIR, "archived", env_id, "app.log")

    path = log_path if os.path.exists(log_path) else archived_path

    if not os.path.exists(path):
        return jsonify({"error": "No logs found"}), 404

    with open(path) as f:
        lines = f.readlines()

    return jsonify({
        "env_id": env_id,
        "lines": [l.rstrip() for l in lines[-100:]]
    })


# GET /envs/:id/health — last 10 health check results
@app.route("/envs/<env_id>/health", methods=["GET"])
def get_health(env_id):
    log_path = os.path.join(LOGS_DIR, env_id, "health.log")
    archived_path = os.path.join(LOGS_DIR, "archived", env_id, "health.log")

    path = log_path if os.path.exists(log_path) else archived_path

    if not os.path.exists(path):
        return jsonify({"error": "No health logs found"}), 404

    with open(path) as f:
        lines = f.readlines()

    env = get_env(env_id)
    return jsonify({
        "env_id": env_id,
        "status": env["status"] if env else "unknown",
        "last_10": [l.rstrip() for l in lines[-10:]]
    })


# POST /envs/:id/outage — trigger outage simulation
@app.route("/envs/<env_id>/outage", methods=["POST"])
def simulate_outage(env_id):
    env = get_env(env_id)
    if not env:
        return jsonify({"error": f"Environment {env_id} not found"}), 404

    data = request.get_json() or {}
    mode = data.get("mode")

    if not mode:
        return jsonify({"error": "mode is required (crash/pause/network/recover/stress)"}), 400

    code, stdout, stderr = run_script([
        "bash", "platform/simulate_outage.sh",
        "--env", env_id,
        "--mode", mode
    ])

    if code != 0:
        return jsonify({"error": stderr or "Simulation failed"}), 500

    return jsonify({
        "message": f"Outage simulation [{mode}] triggered on {env_id}",
        "output": stdout
    })


# ── Start ──────────────────────────────────────────────────
if __name__ == "__main__":
    print("🚀 Sandbox Control API running on http://0.0.0.0:8080")
    app.run(host="0.0.0.0", port=8080, debug=False)