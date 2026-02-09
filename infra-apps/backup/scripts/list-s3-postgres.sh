#!/bin/bash
set -e

echo "=========================================="
echo "S3 PostgreSQL Backups"
echo "=========================================="
echo ""

# 检查 S3 配置
if [ -z "$BACKUP_S3_BUCKET" ]; then
    echo "ERROR: BACKUP_S3_BUCKET not set"
    exit 1
fi

if [ -z "$BACKUP_AWS_ACCESS_KEY_ID" ]; then
    echo "ERROR: BACKUP_AWS_ACCESS_KEY_ID not set"
    exit 1
fi

AWS_ARGS=""
[ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
[ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"

# 使用环境前缀（如果设置）
ENV_PREFIX=""
if [ -n "$ENVIRONMENT" ]; then
    ENV_PREFIX="${ENVIRONMENT}/"
    echo "Environment: $ENVIRONMENT"
fi

echo "Bucket: s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/"
echo ""

# 列出所有日期目录
echo "Available backup dates:"
DATES=$(aws s3 ls "s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/" $AWS_ARGS | grep "PRE" | awk '{print $2}' | sed 's/\///' | sort -r)

if [ -z "$DATES" ]; then
    echo "  No backups found"
    exit 0
fi

echo "$DATES" | head -20 | nl

echo ""
echo "=========================================="
echo "Latest backups by date:"
echo "=========================================="
echo ""

# 显示最近10天的备份详情
echo "$DATES" | head -10 | while read date; do
    # 计算距今天数（使用 UTC 时区）
    TODAY=$(date -u +%Y%m%d)
    if [ "$date" = "$TODAY" ]; then
        AGE_STR="(today)"
    else
        DAYS_AGO=$(( ($(date -u +%s) - $(date -u -d "$date" +%s 2>/dev/null || date -u -j -f "%Y%m%d" "$date" +%s)) / 86400 ))
        if [ "$DAYS_AGO" -eq 1 ]; then
            AGE_STR="(yesterday)"
        else
            AGE_STR="($DAYS_AGO days ago)"
        fi
    fi

    echo "📅 $date $AGE_STR:"
    aws s3 ls "s3://${BACKUP_S3_BUCKET}/${ENV_PREFIX}postgres/${date}/" $AWS_ARGS | grep "\.sql\.gz$" | while read line; do
        DATE_TIME=$(echo "$line" | awk '{print $1, $2}')
        SIZE=$(echo "$line" | awk '{print $3}')
        FILE=$(echo "$line" | awk '{print $4}')
        SIZE_MB=$((SIZE / 1024 / 1024))
        echo "  - ${FILE}"
        echo "    Size: ${SIZE_MB} MB | Created: ${DATE_TIME}"
    done
    echo ""
done

echo "=========================================="
echo ""
echo "To restore from S3:"
echo "  docker compose run --rm backup /usr/local/bin/restore-postgres-s3.sh latest"
echo "  docker compose run --rm backup /usr/local/bin/restore-postgres-s3.sh 20251116/postgres-all-20251116-095831.sql.gz"
