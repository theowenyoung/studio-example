#!/bin/bash
# 开发环境备份快捷脚本

set -e

cd "$(dirname "$0")"

case "$1" in
  all)
    echo "🔄 Backing up all services..."
    docker compose run --rm backup /usr/local/bin/backup-all.sh
    ;;
  postgres)
    echo "🔄 Backing up PostgreSQL..."
    docker compose run --rm backup /usr/local/bin/backup-postgres.sh
    ;;
  redis)
    echo "🔄 Backing up Redis..."
    docker compose run --rm backup /usr/local/bin/backup-redis.sh
    ;;
  cleanup)
    echo "🧹 Cleaning up old backups with smart strategy..."
    docker compose run --rm backup /usr/local/bin/cleanup-smart.sh
    ;;
  test)
    echo "🔍 Testing database connections..."
    docker compose run --rm backup /usr/local/bin/test-connection.sh
    ;;
  logs)
    echo "📋 Viewing backup logs..."
    if docker compose ps backup | grep -q "Up"; then
      docker compose exec backup tail -f /var/log/backup.log
    else
      echo "⚠️  Backup service is not running. Start it with: docker compose up -d"
    fi
    ;;
  list)
    echo "📁 PostgreSQL backups:"
    ls -lh ./.local/backups/postgres/ 2>/dev/null || echo "  No backups found"
    echo ""
    echo "📁 Redis backups:"
    ls -lh ./.local/backups/redis/ 2>/dev/null || echo "  No backups found"
    echo ""
    echo "📁 SQLite backups:"
    ls -lh ./.local/backups/sqlite/ 2>/dev/null || echo "  No backups found"
    ;;
  status)
    echo "📊 Backup service status:"
    docker compose ps backup
    ;;
  *)
    echo "Usage: $0 {all|postgres|redis|cleanup|test|logs|list|status}"
    echo ""
    echo "Commands:"
    echo "  all      - Backup all services (PostgreSQL + Redis + SQLite)"
    echo "  postgres - Backup PostgreSQL only"
    echo "  redis    - Backup Redis only"
    echo "  cleanup  - Clean up old backups"
    echo "  test     - Test database connections"
    echo "  logs     - View backup logs (requires service running)"
    echo "  list     - List backup files"
    echo "  status   - Show backup service status"
    echo ""
    echo "Note: SQLite backup requires /docker-volumes mount (production only)"
    exit 1
    ;;
esac
