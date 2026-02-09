#!/bin/bash
set -e

S3_PATH="${1:-latest}"

echo "[$(date)] Starting PostgreSQL restore from S3..."

# 检查 S3 配置
if [ -z "$BACKUP_S3_BUCKET" ]; then
    echo "[$(date)] ERROR: BACKUP_S3_BUCKET not set"
    exit 1
fi

if [ -z "$BACKUP_AWS_ACCESS_KEY_ID" ]; then
    echo "[$(date)] ERROR: BACKUP_AWS_ACCESS_KEY_ID not set"
    exit 1
fi

AWS_ARGS=""
[ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
[ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"

# 使用环境前缀（如果设置）
ENV_PREFIX=""
if [ -n "$ENVIRONMENT" ]; then
    ENV_PREFIX="${ENVIRONMENT}/"
    echo "[$(date)] Using environment: $ENVIRONMENT"
fi

# 如果是 latest，找最新的 S3 备份
if [ "$S3_PATH" = "latest" ]; then
    echo "[$(date)] Finding latest backup from S3..."

    # 列出所有日期目录，取最新的
    LATEST_DATE=$(aws s3 ls "s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/" $AWS_ARGS | grep "PRE" | awk '{print $2}' | sed 's/\///' | sort -r | head -1)

    if [ -z "$LATEST_DATE" ]; then
        echo "[$(date)] ERROR: No backups found in S3"
        exit 1
    fi

    # 找该日期下最新的备份文件
    LATEST_FILE=$(aws s3 ls "s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/${LATEST_DATE}/" $AWS_ARGS | grep "\.sql\.gz$" | sort -k1,2 -r | head -1 | awk '{print $4}')

    if [ -z "$LATEST_FILE" ]; then
        echo "[$(date)] ERROR: No backup files found in S3 for date ${LATEST_DATE}"
        exit 1
    fi

    S3_PATH="s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/${LATEST_DATE}/${LATEST_FILE}"
    echo "[$(date)] Using latest S3 backup: $S3_PATH"
else
    # 如果不是完整路径，补充前缀
    if [[ "$S3_PATH" != s3://* ]]; then
        S3_PATH="s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/${S3_PATH}"
    fi
fi

# 下载到临时目录
# 使用 UTC 时间戳避免时区差异
TEMP_FILE="/tmp/restore-$(date -u +%s).sql.gz"
echo "[$(date)] Downloading from S3: $S3_PATH"
echo "[$(date)] Temporary file: $TEMP_FILE"

aws s3 cp "$S3_PATH" "$TEMP_FILE" $AWS_ARGS

if [ ! -f "$TEMP_FILE" ]; then
    echo "[$(date)] ERROR: Failed to download backup from S3"
    exit 1
fi

# 显示文件信息
FILE_SIZE=$(stat -c%s "$TEMP_FILE" 2>/dev/null || stat -f%z "$TEMP_FILE")
FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
echo "[$(date)] Downloaded: ${FILE_SIZE_MB} MB"
echo ""

# 解析 POSTGRES_ADMIN_URL
if [ -n "$POSTGRES_ADMIN_URL" ]; then
    url="${POSTGRES_ADMIN_URL#postgresql://}"
    url="${url#postgres://}"
    
    if [[ "$url" =~ ^([^:]+):([^@]+)@(.+)$ ]]; then
        POSTGRES_USER="${BASH_REMATCH[1]}"
        COMMON_POSTGRES_PASSWORD="${BASH_REMATCH[2]}"
        url="${BASH_REMATCH[3]}"
    fi
    
    if [[ "$url" =~ ^([^:]+):([0-9]+)/?$ ]]; then
        POSTGRES_HOST="${BASH_REMATCH[1]}"
        POSTGRES_PORT="${BASH_REMATCH[2]}"
    else
        POSTGRES_HOST="${url%%/*}"
        POSTGRES_PORT="5432"
    fi
fi

if [ -z "$POSTGRES_HOST" ]; then
    echo "[$(date)] ERROR: POSTGRES_HOST or POSTGRES_ADMIN_URL not set"
    rm -f "$TEMP_FILE"
    exit 1
fi

echo "[$(date)] Target: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}"
echo "[$(date)] ⚠️  WARNING: This will OVERWRITE all existing databases!"
echo ""

# 执行恢复
export PGPASSWORD="${COMMON_POSTGRES_PASSWORD}"

echo "[$(date)] Restoring database..."
gunzip -c "$TEMP_FILE" | psql -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" -U "$POSTGRES_USER" -d postgres 2>&1 | \
    grep -v "^ERROR.*already exists" | \
    grep -v "^ERROR.*duplicate key" || true

# 清理临时文件
rm -f "$TEMP_FILE"

echo ""
echo "[$(date)] ✅ Restore completed!"
echo ""
echo "[$(date)] Verify the restore:"
echo "  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\\l'"
