# PostgreSQL Development Environment

Production-grade PostgreSQL setup for local development using Docker Compose.

## Features

- PostgreSQL 18 Alpine (latest stable)
- **Migrations System** - Run database migrations without restarting PostgreSQL
- Production-grade performance configuration via `postgresql.conf`
- Automatic database creation with read-write and read-only users
- Minimal environment variables for easy management
- Automatic health checks
- Automatic daily backups with configurable retention
- Data persistence with local volumes
- Initialization scripts for extensions, roles, and schema

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- At least 2GB of available RAM

### Setup

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Update the password in `.env` file:
   - `COMMON_POSTGRES_PASSWORD`

3. Ensure the external network exists:
```bash
docker network create shared
```

4. Start the services:
```bash
docker compose up -d postgres
```

5. Run migrations (creates demo database and users):
```bash
./migrate.sh
```

6. Verify the services are running:
```bash
docker compose ps
```

6. Check logs:
```bash
docker compose logs -f postgres
```

## Access

### PostgreSQL Databases

#### Root Access
- **Host**: localhost
- **Port**: 5432
- **Database**: postgres
- **Username**: postgres
- **Password**: Set in `.env` as `COMMON_POSTGRES_PASSWORD`

Connection string:
```
postgresql://postgres:your_password@localhost:5432/postgres
```

#### Demo Database (created by migrations)
- **Database**: demo
- **Read-Write User**: demo_user (password: `DEMO_POSTGRES_USER_PASSWORD` in `.env`)
  - Permissions: SELECT, INSERT, UPDATE, DELETE
  - Connection limit: 50 connections
- **Read-Only User**: demo_readonly_user (password: `DEMO_POSTGRES_READONLY_PASSWORD` in `.env`)
  - Permissions: SELECT only
  - Connection limit: 20 connections

Connection examples:
```bash
# Read-write access
psql postgresql://demo_user:your_password@localhost:5432/demo

# Read-only access
psql postgresql://demo_readonly_user:your_password@localhost:5432/demo

# Using docker
docker compose exec postgres psql -U demo_user -d demo
```

### Network Configuration

The PostgreSQL container is connected to an external Docker network named `shared`. This allows other containers in the same network to communicate with PostgreSQL.

To access PostgreSQL from other containers, use:
- Host: `postgres` (container name)
- Port: `5432`

## Configuration

### Environment Variables (.env)

The `.env` file contains minimal configuration:
- Database credentials (user, password, database name)
- Port mapping for host access

### PostgreSQL Configuration (postgresql.conf)

All PostgreSQL performance and behavior settings are managed in `postgresql.conf`. This production-grade configuration is optimized for a typical development machine with 4GB+ RAM:

**Connection Settings:**
- `max_connections`: 200 concurrent connections
- `superuser_reserved_connections`: 3

**Memory Settings:**
- `shared_buffers`: 256MB (25% of available RAM)
- `effective_cache_size`: 1GB (estimated OS cache)
- `work_mem`: 4MB per query operation
- `maintenance_work_mem`: 128MB for maintenance operations

**Performance Features:**
- Parallel query execution enabled
- Optimized checkpoint configuration
- Query statistics tracking (pg_stat_statements)
- Slow query logging (>1000ms)

**To adjust settings:**
1. Edit `postgresql.conf` directly
2. Restart the container: `docker compose restart postgres`
3. Verify settings: `docker compose exec postgres psql -U postgres -d app -c "SHOW max_connections;"`

## Migrations System

### Overview

This setup includes a powerful migrations system that allows you to add new databases, tables, and schema changes **without restarting PostgreSQL**.

- **initdb.d/**: Scripts run ONCE on first database initialization
- **migrations/**: Scripts run on-demand, tracked automatically
- **No downtime**: Migrations run in a separate container

### Running Migrations

```bash
# Run all pending migrations
./migrate.sh

# Check migration status
./migrate.sh status

# View help
./migrate.sh help
```

### Adding New Migrations

Create a new file in `migrations/` with a numeric prefix:

**SQL Migration** (`migrations/002_create_users_table.sql`):
```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

**Shell Migration** (`migrations/003_create_new_db.sh`):
```bash
#!/bin/bash
set -e
source "/docker-entrypoint-initdb.d/000-functions.sh"

create_database_with_users \
  "myapp" \
  "${POSTGRES_MYAPP_USER_PASSWORD}" \
  "${POSTGRES_MYAPP_READONLY_PASSWORD}" \
  "My Application Database"
```

Then run:
```bash
./migrate.sh up
```

### Migration Tracking

Migrations are automatically tracked in the `schema_migrations` table:
```bash
# View migration history
docker compose exec postgres psql -U postgres -d postgres -c \
  "SELECT filename, executed_at, success FROM schema_migrations ORDER BY executed_at;"
```

For detailed documentation, see [migrations/README.md](./migrations/README.md).

## Initialization Scripts

Scripts in `initdb.d/` run automatically on first startup:

- `000-functions.sh`: Reusable functions for creating databases with users
- `001-create-demo-db.sh`: Example (now moved to migrations)


## Common Operations

### Start services
```bash
docker compose up -d
```

### Stop services
```bash
docker compose stop
```

### Restart services
```bash
docker compose restart
```

### View logs
```bash
docker compose logs -f postgres
```

### Access PostgreSQL CLI
```bash
docker compose exec postgres psql -U postgres -d app
```

### Backup database
```bash
docker compose exec postgres pg_dump -U postgres app > backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore database
```bash
docker compose exec -T postgres psql -U postgres -d app < backup.sql
```

### Connect with psql client (if installed locally)
```bash
psql postgresql://postgres:your_password@localhost:5432/app
```

## Data Persistence

Data is persisted in local directories:

- `.local/backups`: Backup directory (mounted at `/backups` in container)

These directories are created automatically and excluded from git via `.gitignore`.

To completely reset (WARNING: destroys all data):
```bash
docker compose down
rm -rf .local
docker compose up -d
```

## Troubleshooting

### Container won't start
Check logs: `docker compose logs postgres`

### Connection refused
- Verify PostgreSQL is healthy: `docker compose ps`
- Check port conflicts: `lsof -i :5432`
- Ensure firewall allows connections

### Performance issues
- Adjust memory settings in `postgresql.conf` (e.g., `shared_buffers`, `effective_cache_size`)
- Monitor resource usage: `docker stats postgres-dev`
- Check slow queries: `docker compose exec postgres psql -U postgres -d app -c "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"`
- After editing `postgresql.conf`, restart: `docker compose restart postgres`

### Reset initialization scripts
Initialization scripts only run on first startup. To re-run:
```bash
docker compose down -v
docker compose up -d
```

## Security Notes

⚠️ **Important**: This setup is for LOCAL DEVELOPMENT only.

For production:
- Use strong, randomly generated passwords
- Enable SSL/TLS connections
- Configure proper firewall rules
- Regular backups with off-site storage
- Enable audit logging
- Use connection pooling (PgBouncer)
- Restrict network access
- Keep PostgreSQL updated

## Production Considerations

This configuration follows production best practices:

- **Logging**: Configured to log slow queries (>1000ms)
- **Connections**: Supports 200 concurrent connections
- **Checkpoints**: Optimized checkpoint configuration
- **Parallel Processing**: Enabled for query performance
- **WAL Management**: Configured for durability and performance

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PgAdmin Documentation](https://www.pgadmin.org/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
