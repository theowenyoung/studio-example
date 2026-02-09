#!/bin/bash
set -e

echo "[$(date)] ========================================="
echo "[$(date)] Starting full backup (all services)"
echo "[$(date)] ========================================="

FAILED=0

# 执行 Postgres 备份
if [ -n "$POSTGRES_ADMIN_URL" ] || [ -n "$POSTGRES_HOST" ]; then
    echo "[$(date)] Running Postgres backup..."
    if /usr/local/bin/backup-postgres.sh; then
        echo "[$(date)] Postgres backup: SUCCESS"
    else
        echo "[$(date)] Postgres backup: FAILED"
        FAILED=$((FAILED + 1))
    fi
else
    echo "[$(date)] Postgres backup: SKIPPED (POSTGRES_ADMIN_URL not set)"
fi

echo ""

# 执行 Redis 备份
if [ -n "$REDIS_DOCKER_URL" ] || [ -n "$REDIS_HOST" ]; then
    echo "[$(date)] Running Redis backup..."
    if /usr/local/bin/backup-redis.sh; then
        echo "[$(date)] Redis backup: SUCCESS"
    else
        echo "[$(date)] Redis backup: FAILED"
        FAILED=$((FAILED + 1))
    fi
else
    echo "[$(date)] Redis backup: SKIPPED (REDIS_DOCKER_URL not set)"
fi

echo ""

# 执行 SQLite 备份
if [ -d "/docker-volumes" ]; then
    echo "[$(date)] Running SQLite backup..."
    if /usr/local/bin/backup-sqlite.sh; then
        echo "[$(date)] SQLite backup: SUCCESS"
    else
        echo "[$(date)] SQLite backup: FAILED"
        FAILED=$((FAILED + 1))
    fi
else
    echo "[$(date)] SQLite backup: SKIPPED (/docker-volumes not mounted)"
fi

echo ""
echo "[$(date)] ========================================="
if [ $FAILED -eq 0 ]; then
    echo "[$(date)] Full backup completed successfully"
    echo "[$(date)] ========================================="
    exit 0
else
    echo "[$(date)] Full backup completed with ${FAILED} failure(s)"
    echo "[$(date)] ========================================="
    exit 1
fi
