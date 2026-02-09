#!/bin/bash
set -e

BACKUP_FILE="${1:-latest}"

echo "[$(date)] Starting PostgreSQL restore..."

# 如果是 latest，自动找最新的备份
if [ "$BACKUP_FILE" = "latest" ]; then
    BACKUP_FILE=$(ls -t /backups/postgres/*.sql.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_FILE" ]; then
        echo "[$(date)] ERROR: No backup files found in /backups/postgres/"
        exit 1
    fi
    echo "[$(date)] Using latest backup: $BACKUP_FILE"
else
    # 如果是相对路径，添加 /backups/postgres/ 前缀
    if [[ "$BACKUP_FILE" != /* ]]; then
        BACKUP_FILE="/backups/postgres/$BACKUP_FILE"
    fi
fi

# 检查文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[$(date)] ERROR: Backup file not found: $BACKUP_FILE"
    echo "[$(date)] Available backups:"
    ls -lh /backups/postgres/*.sql.gz 2>/dev/null || echo "  No backups found"
    exit 1
fi

# 显示备份信息
FILE_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE")
FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
echo "[$(date)] Backup file: $BACKUP_FILE"
echo "[$(date)] File size: ${FILE_SIZE_MB} MB"
echo ""

# 解析 POSTGRES_ADMIN_URL
if [ -n "$POSTGRES_ADMIN_URL" ]; then
    # 移除协议前缀
    url="${POSTGRES_ADMIN_URL#postgresql://}"
    url="${url#postgres://}"
    
    # 提取用户名和密码
    if [[ "$url" =~ ^([^:]+):([^@]+)@(.+)$ ]]; then
        POSTGRES_USER="${BASH_REMATCH[1]}"
        COMMON_POSTGRES_PASSWORD="${BASH_REMATCH[2]}"
        url="${BASH_REMATCH[3]}"
    fi
    
    # 提取主机和端口
    if [[ "$url" =~ ^([^:]+):([0-9]+)/?$ ]]; then
        POSTGRES_HOST="${BASH_REMATCH[1]}"
        POSTGRES_PORT="${BASH_REMATCH[2]}"
    else
        POSTGRES_HOST="${url%%/*}"
        POSTGRES_PORT="5432"
    fi
fi

# 检查必需的环境变量
if [ -z "$POSTGRES_HOST" ]; then
    echo "[$(date)] ERROR: POSTGRES_HOST or POSTGRES_ADMIN_URL not set"
    exit 1
fi

echo "[$(date)] Target: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}"
echo "[$(date)] ⚠️  WARNING: This will OVERWRITE all existing databases!"
echo ""

# 执行恢复
export PGPASSWORD="${COMMON_POSTGRES_PASSWORD}"

echo "[$(date)] Restoring database..."
gunzip -c "$BACKUP_FILE" | psql -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" -U "$POSTGRES_USER" -d postgres 2>&1 | \
    grep -v "^ERROR.*already exists" | \
    grep -v "^ERROR.*duplicate key" || true

echo ""
echo "[$(date)] ✅ Restore completed!"
echo ""
echo "[$(date)] Verify the restore:"
echo "  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\\l'"
