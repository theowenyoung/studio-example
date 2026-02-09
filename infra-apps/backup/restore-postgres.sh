#!/bin/bash
set -e

cd "$(dirname "$0")"

# 解析参数
AUTO_YES=false
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        latest)
            # 使用最新的备份文件
            BACKUP_FILE=$(ls -t ./.local/backups/postgres/*.sql.gz 2>/dev/null | head -1)
            if [ -z "$BACKUP_FILE" ]; then
                echo "❌ Error: No backup files found"
                exit 1
            fi
            shift
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

# 检查参数
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 [OPTIONS] <backup-file|latest>"
    echo ""
    echo "Options:"
    echo "  -y, --yes    Skip confirmation prompt"
    echo ""
    echo "Examples:"
    echo "  $0 ./.local/backups/postgres/postgres-all-20251116-095831.sql.gz"
    echo "  $0 latest                    # Use latest backup"
    echo "  $0 --yes latest              # Auto-confirm with latest backup"
    echo ""
    echo "Available backups:"
    ls -lht ./.local/backups/postgres/*.sql.gz 2>/dev/null | head -5 || echo "  No backups found"
    exit 1
fi

# 检查文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "=========================================="
echo "PostgreSQL Database Restore"
echo "=========================================="
echo ""
echo "📁 Backup file: $BACKUP_FILE"
echo "🗄️  Target: postgres@postgres:5432"
echo ""
echo "⚠️  WARNING: This will OVERWRITE all existing databases!"
echo ""

# 如果不是自动模式，要求确认
if [ "$AUTO_YES" = false ]; then
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ Restore cancelled."
        exit 0
    fi
fi

echo ""
echo "🔄 Starting restore..."
echo ""

# 解压并恢复
gunzip -c "$BACKUP_FILE" | \
    docker compose run --rm -T backup \
    psql -h postgres -U postgres -d postgres

echo ""
echo "✅ Restore completed!"
echo ""
echo "Verify the restore:"
echo "  docker compose -f ../postgres/docker-compose.yml exec postgres psql -U postgres -d postgres -c '\\l'"
