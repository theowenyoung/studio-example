#!/bin/bash
set -e

# 创建备份目录
mkdir -p /backups/postgres /backups/redis /backups/sqlite

# 如果有传入命令参数，直接执行命令并退出（用于一次性任务）
if [ $# -gt 0 ]; then
    echo "Executing command: $@"
    exec "$@"
fi

# 否则启动 cron 服务（用于后台定时任务）
echo "Starting backup service..."

# 设置默认值
BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-"0 2 * * *"}
CLEANUP_SCHEDULE=${CLEANUP_SCHEDULE:-"0 5 * * *"}

# 生成 crontab
cat > /etc/crontabs/root << EOF
# 每天全量备份 (Postgres + Redis + SQLite)
${BACKUP_SCHEDULE} /usr/local/bin/backup-all.sh >> /var/log/backup.log 2>&1

# 清理旧备份
${CLEANUP_SCHEDULE} /usr/local/bin/cleanup.sh >> /var/log/backup.log 2>&1
EOF

echo "Cron schedules configured:"
cat /etc/crontabs/root
echo ""

# 显示配置信息
echo "Backup Configuration:"
if [ -n "$POSTGRES_ADMIN_URL" ]; then
    echo "  Postgres: configured via URL"
elif [ -n "$POSTGRES_HOST" ]; then
    echo "  Postgres: ${POSTGRES_HOST}"
else
    echo "  Postgres: not configured"
fi

if [ -n "$REDIS_DOCKER_URL" ]; then
    echo "  Redis: configured via URL"
elif [ -n "$REDIS_HOST" ]; then
    echo "  Redis: ${REDIS_HOST}"
else
    echo "  Redis: not configured"
fi

echo "  S3 Bucket: ${BACKUP_S3_BUCKET:-not set}"
echo "  Local Retention: ${BACKUP_RETENTION_LOCAL:-3} days"
echo "  S3 Retention: ${BACKUP_RETENTION_S3:-30} days"
echo ""

# 启动 cron（前台运行）
echo "Starting cron daemon..."
crond -f -l 2
