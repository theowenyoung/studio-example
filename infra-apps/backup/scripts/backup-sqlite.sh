#!/bin/bash
set -e

# SQLite 备份脚本
# 扫描 /docker-volumes/ 下所有包含 sqlite_ 的 volume，备份其中的 .db 和 .sqlite 文件

DOCKER_VOLUMES_DIR="/docker-volumes"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
DATE=$(date -u +%Y%m%d)

# 使用环境前缀（如果设置）
ENV_PREFIX=""
[ -n "$ENVIRONMENT" ] && ENV_PREFIX="${ENVIRONMENT}/"

echo "[$(date)] Starting SQLite backup"
echo "[$(date)] Scanning for sqlite_* volumes in ${DOCKER_VOLUMES_DIR}..."

# 检查目录是否存在
if [ ! -d "$DOCKER_VOLUMES_DIR" ]; then
  echo "[$(date)] WARNING: ${DOCKER_VOLUMES_DIR} not found, skipping SQLite backup"
  exit 0
fi

BACKUP_COUNT=0
FAILED_COUNT=0

# 扫描所有包含 sqlite_ 的目录（Docker Compose 会加项目名前缀，如 microbin_sqlite_xxx）
for volume_dir in "${DOCKER_VOLUMES_DIR}"/*sqlite_*; do
  # 检查是否存在匹配的目录
  [ -d "$volume_dir" ] || continue

  volume_name=$(basename "$volume_dir")
  data_dir="${volume_dir}/_data"

  # 检查 _data 目录是否存在
  if [ ! -d "$data_dir" ]; then
    echo "[$(date)] WARNING: ${volume_name} has no _data directory, skipping"
    continue
  fi

  echo "[$(date)] Processing volume: ${volume_name}"

  # 查找所有 .db 和 .sqlite 文件
  find "$data_dir" \( -name "*.db" -o -name "*.sqlite" \) -type f 2>/dev/null | while read -r db_file; do
    db_name=$(basename "$db_file")
    # 从 volume 名中提取应用名（去掉 sqlite_ 前缀和 _data 后缀）
    app_name=$(echo "$volume_name" | sed 's/^sqlite_//' | sed 's/_data$//')

    # 移除 .db 或 .sqlite 后缀
    db_base="${db_name%.db}"
    db_base="${db_base%.sqlite}"
    FILE="sqlite-${app_name}-${db_base}-${TIMESTAMP}.db"
    LOCAL_PATH="/backups/sqlite/${FILE}"
    S3_PATH="s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}sqlite/${DATE}/${FILE}"

    echo "[$(date)]   Backing up: ${db_file} -> ${LOCAL_PATH}"

    # 确保目录存在
    mkdir -p /backups/sqlite

    # 使用 sqlite3 .backup 命令安全备份（避免锁问题）
    if sqlite3 "$db_file" ".backup '${LOCAL_PATH}'"; then
      SIZE=$(stat -c%s "$LOCAL_PATH" 2>/dev/null || stat -f%z "$LOCAL_PATH")
      SIZE_KB=$((SIZE / 1024))
      echo "[$(date)]   Backup size: ${SIZE_KB} KB"

      # 上传到 S3（如果配置了）
      if [ -n "$BACKUP_S3_BUCKET" ]; then
        AWS_ARGS=""
        [ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
        [ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"

        if aws s3 cp "$LOCAL_PATH" "$S3_PATH" $AWS_ARGS; then
          echo "[$(date)]   Uploaded to S3: $S3_PATH"
        else
          echo "[$(date)]   WARNING: Failed to upload to S3"
        fi
      fi

      BACKUP_COUNT=$((BACKUP_COUNT + 1))
    else
      echo "[$(date)]   ERROR: Failed to backup ${db_file}"
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
  done
done

echo "[$(date)] SQLite backup completed: ${BACKUP_COUNT} successful, ${FAILED_COUNT} failed"

if [ "$FAILED_COUNT" -gt 0 ]; then
  exit 1
fi
