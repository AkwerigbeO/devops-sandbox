.PHONY: up down create destroy logs health simulate clean

# ── Start everything ───────────────────────────────────────
up:
	@echo "🚀 Starting Sandbox Platform..."
	@cd nginx && docker-compose up -d
	@mkdir -p logs envs
	@nohup bash platform/cleanup_daemon.sh > /dev/null 2>&1 & echo $$! > logs/cleanup_daemon.pid
	@echo "✅ Cleanup daemon started (PID: $$(cat logs/cleanup_daemon.pid))"
	@nohup python3 monitor/health_poller.py > /dev/null 2>&1 & echo $$! > logs/health_poller.pid
	@echo "✅ Health poller started (PID: $$(cat logs/health_poller.pid))"
	@nohup python3 platform/api.py > /dev/null 2>&1 & echo $$! > logs/api.pid
	@echo "✅ Control API started (PID: $$(cat logs/api.pid))"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Platform is UP"
	@echo "  API: http://localhost:8080"
	@echo "  Nginx: http://localhost:80"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Stop everything ────────────────────────────────────────
down:
	@echo "🛑 Stopping Sandbox Platform..."
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		echo "  Destroying $$ENV_ID..."; \
		bash platform/destroy_env.sh "$$ENV_ID" 2>/dev/null || true; \
	done
	@[ -f logs/cleanup_daemon.pid ] && kill $$(cat logs/cleanup_daemon.pid) 2>/dev/null || true
	@[ -f logs/health_poller.pid ] && kill $$(cat logs/health_poller.pid) 2>/dev/null || true
	@[ -f logs/api.pid ] && kill $$(cat logs/api.pid) 2>/dev/null || true
	@cd nginx && docker-compose down 2>/dev/null || true
	@rm -f logs/*.pid
	@echo "✅ Platform stopped"

# ── Create new environment ─────────────────────────────────
create:
	@read -p "Environment name: " name; \
	read -p "TTL in seconds (default 1800): " ttl; \
	ttl=$${ttl:-1800}; \
	bash platform/create_env.sh "$$name" "$$ttl"

# ── Destroy specific environment ───────────────────────────
destroy:
	@[ -z "$(ENV)" ] && echo "Usage: make destroy ENV=<env-id>" && exit 1 || true
	@bash platform/destroy_env.sh "$(ENV)"

# ── Tail environment logs ──────────────────────────────────
logs:
	@[ -z "$(ENV)" ] && echo "Usage: make logs ENV=<env-id>" && exit 1 || true
	@LOG=logs/$(ENV)/app.log; \
	ARCHIVED=logs/archived/$(ENV)/app.log; \
	if [ -f "$$LOG" ]; then tail -f "$$LOG"; \
	elif [ -f "$$ARCHIVED" ]; then tail -f "$$ARCHIVED"; \
	else echo "❌ No logs found for $(ENV)"; fi

# ── Show all env health statuses ──────────────────────────
health:
	@echo "🏥 Environment Health Status"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || { echo "  No active environments"; break; }; \
		ID=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		STATUS=$$(python3 -c "import json; print(json.load(open('$$f'))['status'])"); \
		PORT=$$(python3 -c "import json; print(json.load(open('$$f'))['port'])"); \
		echo "  $$ID | status: $$STATUS | port: $$PORT"; \
	done
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Run outage simulation ──────────────────────────────────
simulate:
	@[ -z "$(ENV)" ] && echo "Usage: make simulate ENV=<env-id> MODE=<crash|pause|network|recover|stress>" && exit 1 || true
	@[ -z "$(MODE)" ] && echo "Usage: make simulate ENV=<env-id> MODE=<crash|pause|network|recover|stress>" && exit 1 || true
	@bash platform/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

# ── Wipe everything ────────────────────────────────────────
clean:
	@echo "🧹 Cleaning all state, logs and archives..."
	@rm -rf logs/* envs/*
	@rm -f nginx/conf.d/env-*.conf
	@docker ps -aq --filter "label=sandbox.env" | xargs docker rm -f 2>/dev/null || true
	@docker network ls --filter "name=net-env" -q | xargs docker network rm 2>/dev/null || true
	@echo "✅ Clean complete"