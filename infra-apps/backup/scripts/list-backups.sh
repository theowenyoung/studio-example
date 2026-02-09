#!/bin/bash
set -e

echo "=========================================="
echo "Backup Files"
echo "=========================================="
echo ""

# 列出本地备份
echo "📁 Local Backups:"
echo ""
if ls /backups/postgres/*.sql.gz >/dev/null 2>&1; then
    echo "PostgreSQL:"
    ls -lht /backups/postgres/*.sql.gz | head -10 | awk '{print "  " $9 " - " $5 " - " $6 " " $7 " " $8}'
else
    echo "  PostgreSQL: No backups found"
fi

echo ""

if ls /backups/redis/*.rdb >/dev/null 2>&1; then
    echo "Redis:"
    ls -lht /backups/redis/*.rdb | head -10 | awk '{print "  " $9 " - " $5 " - " $6 " " $7 " " $8}'
else
    echo "  Redis: No backups found"
fi

echo ""
echo "=========================================="

# 列出 S3 备份（如果配置了）
if [ -n "$BACKUP_S3_BUCKET" ] && [ -n "$BACKUP_AWS_ACCESS_KEY_ID" ]; then
    echo "☁️  S3 Backups (s3://$BACKUP_S3_BUCKET):"
    echo ""
    
    AWS_ARGS=""
    [ -n "$BACKUP_S3_ENDPOINT" ] && AWS_ARGS="$AWS_ARGS --endpoint-url $BACKUP_S3_ENDPOINT"
    [ -n "$S3_REGION" ] && AWS_ARGS="$AWS_ARGS --region $S3_REGION"
    
    echo "PostgreSQL (last 10 days):"
    aws s3 ls "s3://${BACKUP_S3_BUCKET}/postgres/" $AWS_ARGS 2>/dev/null | tail -10 | awk '{print "  " $0}' || echo "  No backups found or S3 access error"
    
    echo ""
    echo "Redis (last 10 days):"
    aws s3 ls "s3://${BACKUP_S3_BUCKET}/redis/" $AWS_ARGS 2>/dev/null | tail -10 | awk '{print "  " $0}' || echo "  No backups found or S3 access error"
else
    echo "☁️  S3 Backups: Not configured"
fi

echo ""
echo "=========================================="
