# **DevOps Sandbox Platform**

A self-service platform **for** spinning up isolated temporary environments, deploying apps, simulating outages, and monitoring health — all on a single Linux VM.


## **Architecture**

**+------------------+
                    |   Control API    |
                    |  (Flask :8080)   |
                    +--------+---------+
                             |
          +------------------+------------------+
          |                  |                  |
+---------+------+  +--------+-------+  +-------+--------+
| create_env.sh  |  | destroy_env.sh |  | simulate_outage|
+--------+-------+  +--------+-------+  +-------+--------+
         |                   |                  |
+--------+-------------------+------------------+--------+
|                    Docker Engine                        |
|  +-------------+  +-------------+  +-------------+     |
|  | env-app-001 |  | env-app-002 |  | env-app-003 |     |
|  | (demo-app)  |  | (demo-app)  |  | (demo-app)  |     |
|  +------+------+  +------+------+  +------+------+     |
|         |                |                |             |
|  net-env-001      net-env-002      net-env-003          |
+--------+-------------------+------------------+--------+
         |                   |
+--------+-------------------+--------+
|           Nginx Proxy (:80)         |
|     (dynamic per-env routing)       |
+--------+----------------------------+
         |
+--------+-------------------+--------+
|        Cleanup Daemon               |
|     (checks TTL every 60s)          |
+--------+----------------------------+
         |
+--------+----------------------------+
|        Health Poller                |
|     (polls /health every 30s)       |
+-------------------------------------+**



## Prerequisites

- Docker
- Docker Compose
- Python 3
- make
- bash

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/devops-sandbox.git
cd devops-sandbox

# 2. Build the demo app image
docker build -t demo-app ./demo-app

# 3. Start the platform
make up

# 4. Create your first environment
make create

# 5. Check health
make health
```

## Full Demo Walkthrough

```bash
# Start platform
make up

# Create environment
make create
# Enter name: myapp
# Enter TTL: 300

# Note the ENV_ID printed, e.g. env-myapp-1778443875

# Check health status
make health

# Tail live logs
make logs ENV=env-myapp-1778443875

# Simulate outage
make simulate ENV=env-myapp-1778443875 MODE=pause

# Observe health monitor detect degradation (wait 90s)
make health

# Recover
make simulate ENV=env-myapp-1778443875 MODE=recover

# Manually destroy
make destroy ENV=env-myapp-1778443875

# Or wait for TTL to expire — cleanup daemon auto-destroys it

# Tear down everything
make down
```

## API Endpoints

| Method | Endpoint         | Description                      |
| ------ | ---------------- | -------------------------------- |
| POST   | /envs            | Create environment               |
| GET    | /envs            | List active envs + TTL remaining |
| DELETE | /envs/:id        | Destroy environment              |
| GET    | /envs/:id/logs   | Last 100 lines of app.log        |
| GET    | /envs/:id/health | Last 10 health check results     |
| POST   | /envs/:id/outage | Trigger outage simulation        |

## Makefile Targets

| Target                         | Description                          |
| ------------------------------ | ------------------------------------ |
| make up                        | Start Nginx, daemon, poller, API     |
| make down                      | Stop everything, destroy all envs    |
| make create                    | Create new environment (interactive) |
| make destroy ENV=...           | Destroy specific environment         |
| make logs ENV=...              | Tail environment logs                |
| make health                    | Show all env health statuses         |
| make simulate ENV=... MODE=... | Run outage simulation                |
| make clean                     | Wipe all state, logs, archives       |

## Outage Simulation Modes

| Mode    | Description                     |
| ------- | ------------------------------- |
| crash   | Hard kills the container        |
| pause   | Freezes the container           |
| network | Disconnects from Docker network |
| recover | Restores whatever was broken    |
| stress  | Spikes CPU with stress-ng       |

## Known Limitations

- Port collisions possible if shuf picks an already-used port
- Nginx routing uses .localhost domains — requires /etc/hosts entry for local testing
- Health poller uses polling not push — up to 30s detection lag
- Log shipping uses Approach A (simple) — no central aggregator
- stress mode requires stress-ng inside the container
  EOF
