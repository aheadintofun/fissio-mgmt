.PHONY: up down logs restart clean backup shell status help

# Default target
help:
	@echo "Fissio MGMT - Project Management (OpenProject)"
	@echo ""
	@echo "Usage:"
	@echo "  make up        Start OpenProject"
	@echo "  make down      Stop OpenProject"
	@echo "  make logs      Follow container logs"
	@echo "  make restart   Restart container"
	@echo "  make status    Show container status"
	@echo "  make shell     Open shell in container"
	@echo "  make backup    Backup PostgreSQL database"
	@echo "  make clean     Stop and remove volumes (WARNING: deletes data)"
	@echo ""
	@echo "Access: http://localhost:8082"
	@echo "Default credentials: admin / admin"

up:
	@echo "Starting Fissio MGMT (OpenProject)..."
	docker compose up -d
	@echo ""
	@echo "OpenProject is starting up (this may take 1-2 minutes)..."
	@echo "Access at: http://localhost:8082"
	@echo "Default credentials: admin / admin"

down:
	docker compose down

logs:
	docker compose logs -f

restart:
	docker compose restart

status:
	docker compose ps
	@echo ""
	@docker exec fissio-mgmt curl -sf http://localhost:80/health_checks/default 2>/dev/null && echo "Health: OK" || echo "Health: Starting up or unhealthy"

shell:
	docker exec -it fissio-mgmt bash

backup:
	@echo "Backing up OpenProject database..."
	@mkdir -p backups
	docker exec fissio-mgmt pg_dump -U postgres -d openproject > backups/openproject_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "Backup saved to backups/"

clean:
	@echo "WARNING: This will delete all OpenProject data!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose down -v
	@echo "All data removed."
