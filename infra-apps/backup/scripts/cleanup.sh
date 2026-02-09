#!/bin/bash
set -e

echo "[$(date)] Starting cleanup (local + S3)"
echo ""

# ===== 1. 清理本地备份 =====
BACKUP_RETENTION_LOCAL=${BACKUP_RETENTION_LOCAL:-3}

echo "==========================================="
echo "Cleaning LOCAL backups (keep ${BACKUP_RETENTION_LOCAL} days)"
echo "==========================================="

for DIR in postgres redis sqlite; do
    if [ -d "/backups/${DIR}" ]; then
        DELETED=$(find /backups/${DIR} -type f -mtime +${BACKUP_RETENTION_LOCAL} -delete -print | wc -l)
        echo "  ${DIR}: deleted ${DELETED} old file(s)"
    fi
done

echo ""

# ===== 2. 清理 S3 备份 =====
BACKUP_RETENTION_S3=${BACKUP_RETENTION_S3:-30}

echo "==========================================="
echo "Cleaning S3 backups (keep ${BACKUP_RETENTION_S3} days)"
echo "==========================================="

if [ -z "$BACKUP_S3_BUCKET" ] || [ -z "$BACKUP_AWS_ACCESS_KEY_ID" ]; then
    echo "⚠️  S3 cleanup skipped (credentials not set)"
    echo ""
    echo "[$(date)] Cleanup completed (local only)"
    exit 0
fi

AWS_ARGS=""
[ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
[ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"

CUTOFF_DATE=$(date -u -d "${BACKUP_RETENTION_S3} days ago" +%Y%m%d 2>/dev/null || date -u -v-${BACKUP_RETENTION_S3}d +%Y%m%d)

for DB_TYPE in postgres redis sqlite; do
    echo ""
    echo "--- ${DB_TYPE} ---"

    DATES=$(aws s3 ls "s3://${BACKUP_S3_BUCKET}/${DB_TYPE}/" $AWS_ARGS 2>/dev/null | \
        grep "PRE" | awk '{print $2}' | sed 's/\///' | grep '^[0-9]' || true)

    if [ -z "$DATES" ]; then
        echo "  No backups found"
        continue
    fi

    DELETED=0
    KEPT=0
    echo "$DATES" | while read folder_date; do
        if [ "$folder_date" -lt "$CUTOFF_DATE" ]; then
            aws s3 rm "s3://${BACKUP_S3_BUCKET}/${DB_TYPE}/${folder_date}/" --recursive $AWS_ARGS > /dev/null
            DELETED=$((DELETED + 1))
            echo "  ❌ DELETE: $folder_date"
        else
            KEPT=$((KEPT + 1))
        fi
    done
done

echo ""
echo "==========================================="
echo "[$(date)] Cleanup completed"
echo "==========================================="
