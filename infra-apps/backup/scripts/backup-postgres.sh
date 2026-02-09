#!/bin/bash
set -e

# 使用 UTC 时区避免不同机器时区差异
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
DATE=$(date -u +%Y%m%d)
FILE="postgres-all-${TIMESTAMP}.sql.gz"
LOCAL_PATH="/backups/postgres/${FILE}"

# 使用环境前缀（如果设置）
ENV_PREFIX=""
[ -n "$ENVIRONMENT" ] && ENV_PREFIX="${ENVIRONMENT}/"
S3_PATH="s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/${DATE}/${FILE}"

echo "[$(date)] Starting Postgres backup (all databases): ${FILE}"

# 解析 POSTGRES_ADMIN_URL 格式：postgresql://user:password@host:port
if [ -n "$POSTGRES_ADMIN_URL" ]; then
  echo "[$(date)] Parsing POSTGRES_ADMIN_URL..."

  # 移除协议前缀
  url="${POSTGRES_ADMIN_URL#postgresql://}"
  url="${url#postgres://}"

  # 提取用户名和密码
  if [[ "$url" =~ ^([^:]+):([^@]+)@(.+)$ ]]; then
    POSTGRES_USER="${BASH_REMATCH[1]}"
    COMMON_POSTGRES_PASSWORD="${BASH_REMATCH[2]}"
    url="${BASH_REMATCH[3]}"
  elif [[ "$url" =~ ^([^@]+)@(.+)$ ]]; then
    POSTGRES_USER="${BASH_REMATCH[1]}"
    COMMON_POSTGRES_PASSWORD=""
    url="${BASH_REMATCH[2]}"
  fi

  # 提取主机和端口
  if [[ "$url" =~ ^([^:]+):([0-9]+)/?$ ]]; then
    POSTGRES_HOST="${BASH_REMATCH[1]}"
    POSTGRES_PORT="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^([^/]+)/?$ ]]; then
    POSTGRES_HOST="${BASH_REMATCH[1]}"
    POSTGRES_PORT="5432"
  else
    echo "[$(date)] ERROR: Invalid POSTGRES_ADMIN_URL format"
    echo "[$(date)] Expected format: postgresql://user:password@host:port"
    exit 1
  fi
fi

# 检查必需的环境变量
if [ -z "$POSTGRES_HOST" ]; then
  echo "[$(date)] ERROR: POSTGRES_HOST or POSTGRES_ADMIN_URL not set"
  exit 1
fi

if [ -z "$POSTGRES_USER" ]; then
  echo "[$(date)] ERROR: POSTGRES_USER not set"
  exit 1
fi

# 使用 pg_dumpall 备份所有数据库
export PGPASSWORD="${COMMON_POSTGRES_PASSWORD}"
pg_dumpall \
  -h "$POSTGRES_HOST" \
  -p "${POSTGRES_PORT:-5432}" \
  -U "$POSTGRES_USER" \
  --no-role-passwords |
  gzip >"$LOCAL_PATH"

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
if [ "$SIZE" -lt 100 ]; then
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

echo "[$(date)] Postgres backup completed successfully"
