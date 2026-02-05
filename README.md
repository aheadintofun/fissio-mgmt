# Fissio MGMT

Project management platform for the Fissio suite, powered by [OpenProject](https://www.openproject.org/).

Part of the **Fissio Platform** for nuclear site development:
- **fissio-site** (port 8000) - Site selection & CAD designer
- **fissio-docs** (port 8001/3000) - Document intelligence & RAG
- **fissio-crmi** (port 3001) - CRM for nuclear operations
- **fissio-base** (port 8080) - Analytics & embeddable dashboards
- **fissio-mgmt** (port 8082) - Project management ← *this repo*

## Quick Start

```bash
# 1. Copy environment file
cp .env.example .env

# 2. Start OpenProject
make up

# 3. Open the project management interface
open http://localhost:8082
```

**Default credentials:** `admin` / `admin` (change on first login)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          fissio-mgmt :8082                               │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         OpenProject v17                            │  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │  │
│  │  │   Projects  │  │    Work     │  │   Gantt     │                │  │
│  │  │   & Teams   │  │   Packages  │  │   Charts    │                │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                │  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │  │
│  │  │    Wiki     │  │   Forums    │  │    Time     │                │  │
│  │  │    Docs     │  │   & News    │  │  Tracking   │                │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                │  │
│  │                                                                    │  │
│  │  ┌───────────────────────────────────────────────────────────┐   │  │
│  │  │                    PostgreSQL (embedded)                   │   │  │
│  │  └───────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Features

- **Work Packages** - Tasks, bugs, features with custom workflows
- **Gantt Charts** - Visual project timelines and dependencies
- **Kanban Boards** - Agile board views
- **Wiki & Documentation** - Built-in knowledge base per project
- **Time Tracking** - Log time against work packages
- **Team Management** - Roles, permissions, groups
- **Meetings** - Schedule and document meetings
- **Budgets** - Track project costs
- **File Management** - Attachments and document storage
- **API Access** - REST API for integrations

## Commands

```bash
make up        # Start OpenProject
make down      # Stop OpenProject
make logs      # Follow logs
make restart   # Restart container
make clean     # Stop and remove volumes (WARNING: deletes data)
make backup    # Backup PostgreSQL data
make shell     # Open shell in container
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | (random) | Rails secret key (use secure value in production) |
| `OPENPROJECT_HOST` | `localhost:8082` | Hostname for links/emails |
| `OPENPROJECT_HTTPS` | `false` | Set `true` behind HTTPS proxy |
| `SMTP_ADDRESS` | - | SMTP server for notifications |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USER` | - | SMTP username |
| `SMTP_PASSWORD` | - | SMTP password |

### HTTPS / Reverse Proxy

For production, run behind a reverse proxy (nginx, Traefik, Caddy):

```nginx
server {
    listen 443 ssl;
    server_name projects.fissio.com;

    location / {
        proxy_pass http://localhost:8082;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then set in `.env`:
```
OPENPROJECT_HOST=projects.fissio.com
OPENPROJECT_HTTPS=true
```

## Nuclear Site Development Projects

Suggested project structure for Fissio:

```
Fissio Platform
├── Site Selection
│   ├── GIS Analysis
│   ├── Environmental Assessment
│   └── Regulatory Mapping
├── Design & Engineering
│   ├── CAD Development
│   ├── Equipment Specifications
│   └── Safety Analysis
├── Regulatory Compliance
│   ├── NRC Licensing
│   ├── Environmental Permits
│   └── Documentation
├── Procurement
│   ├── Vendor Selection
│   ├── Contract Negotiation
│   └── Supply Chain
└── Construction Planning
    ├── Site Preparation
    ├── Module Fabrication
    └── Installation Schedule
```

## Data Persistence

Data is stored in Docker volumes:
- `openproject_pgdata` - PostgreSQL database
- `openproject_assets` - Uploaded files and attachments
- `openproject_logs` - Application logs

### Backup

```bash
# Backup database
make backup

# Manual backup
docker exec fissio-mgmt pg_dump -U openproject openproject > backup.sql
```

### Restore

```bash
# Stop container, restore, restart
make down
docker run --rm -v openproject_pgdata:/var/openproject/pgdata \
  -v $(pwd)/backup.sql:/backup.sql \
  postgres:13 psql -f /backup.sql
make up
```

## Running the Full Platform

```bash
# Terminal 1: Site selection app
cd ~/fissio-site && make serve

# Terminal 2: Document server
cd ~/fissio-docs && docker compose up

# Terminal 3: CRM
cd ~/fissio-crmi && make up

# Terminal 4: Analytics & Dashboards
cd ~/fissio-base && make up

# Terminal 5: Project Management
cd ~/fissio-mgmt && make up
```

### Port Summary

| App | Port | URL |
|-----|------|-----|
| fissio-site | 8000 | http://localhost:8000 |
| fissio-docs API | 8001 | http://localhost:8001 |
| fissio-docs UI | 3000 | http://localhost:3000 |
| fissio-crmi | 3001 | http://localhost:3001 |
| fissio-base | 8080 | http://localhost:8080 |
| └─ Jupyter | 8888 | http://localhost:8888 |
| └─ Superset | 8088 | http://localhost:8088 |
| └─ DuckDB UI | 5522 | http://localhost:5522 |
| **fissio-mgmt** | **8082** | **http://localhost:8082** |

## OpenProject Resources

- [Documentation](https://www.openproject.org/docs/)
- [API Reference](https://www.openproject.org/docs/api/)
- [GitHub](https://github.com/opf/openproject)
- [Community Forums](https://community.openproject.org/)

## License

OpenProject is licensed under GPL-3.0. This wrapper configuration is MIT.
