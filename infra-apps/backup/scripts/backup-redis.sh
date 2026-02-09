#!/bin/bash
set -e

# 加载 URL 解析工具
source /usr/local/bin/parse-url.sh

# 使用 UTC 时区避免不同机器时区差异
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
DATE=$(date -u +%Y%m%d)
FILE="redis-${TIMESTAMP}.rdb"
LOCAL_PATH="/backups/redis/${FILE}"

# 使用环境前缀（如果设置）
ENV_PREFIX=""
[ -n "$ENVIRONMENT" ] && ENV_PREFIX="${ENVIRONMENT}/"
S3_PATH="s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}redis/${DATE}/${FILE}"

echo "[$(date)] Starting Redis backup: ${FILE}"

# 解析 REDIS_DOCKER_URL 或使用单独的环境变量
if [ -n "$REDIS_DOCKER_URL" ]; then
  echo "[$(date)] Parsing REDIS_DOCKER_URL..."
  if ! parse_redis_url "$REDIS_DOCKER_URL"; then
    echo "[$(date)] ERROR: Invalid REDIS_DOCKER_URL format"
    echo "[$(date)] Expected format: redis://[username:]password@host:port[/db]"
    exit 1
  fi
  REDIS_HOST="$REDIS_HOST"
  REDIS_PORT="$REDIS_PORT"
  REDIS_USER="$REDIS_USER"
  COMMON_REDIS_PASSWORD="$REDIS_PASS"
fi

# 检查必需的环境变量
if [ -z "$REDIS_HOST" ]; then
  echo "[$(date)] ERROR: REDIS_HOST or REDIS_DOCKER_URL not set"
  exit 1
fi

# 构建 redis-cli 命令
REDIS_CLI_CMD="redis-cli -h $REDIS_HOST -p ${REDIS_PORT:-6379}"

# 添加用户名（如果指定，Redis 6.0+ ACL）
if [ -n "$REDIS_USER" ]; then
  REDIS_CLI_CMD="$REDIS_CLI_CMD --user $REDIS_USER"
fi

# 添加密码（如果指定）
if [ -n "$COMMON_REDIS_PASSWORD" ]; then
  REDIS_CLI_CMD="$REDIS_CLI_CMD -a $COMMON_REDIS_PASSWORD --no-auth-warning"
fi

# 使用 redis-cli --rdb 备份（推荐方法）
echo "[$(date)] Dumping Redis database..."
$REDIS_CLI_CMD --rdb "$LOCAL_PATH"

# 检查备份是否成功
if [ ! -f "$LOCAL_PATH" ]; then
  echo "[$(date)] ERROR: Backup file not created"
  exit 1
fi

# 检查文件大小
SIZE=$(stat -c%s "$LOCAL_PATH" 2>/dev/null || stat -f%z "$LOCAL_PATH")
SIZE_MB=$((SIZE / 1024 / 1024))
echo "[$(date)] Backup size: ${SIZE_MB} MB"

# 检查备份是否为空
if [ "$SIZE" -lt 10 ]; then
  echo "[$(date)] WARNING: Backup file is suspiciously small (${SIZE} bytes)"
fi

# 上传到 S3（如果配置了）
if [ -n "$BACKUP_S3_BUCKET" ]; then
  echo "[$(date)] Uploading to S3..."

  AWS_ARGS=""
  [ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
  [ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"

  if aws s3 cp "$LOCAL_PATH" "$S3_PATH" $AWS_ARGS; then
    echo "[$(date)] Uploaded to S3: $S3_PATH"
  else
    echo "[$(date)] ERROR: Failed to upload to S3"
    exit 1
  fi
else
  echo "[$(date)] S3 upload skipped (BACKUP_S3_BUCKET not set)"
fi

echo "[$(date)] Redis backup completed successfully"
