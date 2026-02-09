#!/bin/bash
set -e

echo "[$(date)] Starting PostgreSQL cleanup..."
echo ""
echo "⚠️  WARNING: This will delete ALL databases except system databases!"
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
    exit 1
fi

export PGPASSWORD="${COMMON_POSTGRES_PASSWORD}"

echo "[$(date)] Target: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}"
echo ""

# 获取所有数据库列表（排除系统数据库）
echo "[$(date)] Fetching database list..."
DATABASES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -t -c \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');" \
    | grep -v '^$' | sed 's/^[ \t]*//')

if [ -z "$DATABASES" ]; then
    echo "[$(date)] No user databases found, nothing to clean"
    exit 0
fi

echo "[$(date)] Found databases to delete:"
echo "$DATABASES" | while read db; do
    echo "  - $db"
done
echo ""

# 删除所有用户数据库
echo "[$(date)] Deleting databases..."
echo "$DATABASES" | while read db; do
    if [ -n "$db" ]; then
        echo "  Deleting database: $db"
        psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
            -c "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE);" 2>&1 | grep -v "^DROP DATABASE$" || true
    fi
done

# 删除所有非系统角色
echo ""
echo "[$(date)] Cleaning up roles..."
ROLES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -t -c \
    "SELECT rolname FROM pg_roles WHERE rolname NOT IN ('postgres', 'pg_monitor', 'pg_read_all_settings', 'pg_read_all_stats', 'pg_stat_scan_tables', 'pg_read_server_files', 'pg_write_server_files', 'pg_execute_server_program', 'pg_signal_backend') AND rolname NOT LIKE 'pg_%';" \
    | grep -v '^$' | sed 's/^[ \t]*//')

if [ -n "$ROLES" ]; then
    echo "$ROLES" | while read role; do
        if [ -n "$role" ]; then
            echo "  Deleting role: $role"
            psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
                -c "DROP ROLE IF EXISTS \"$role\";" 2>&1 | grep -v "^DROP ROLE$" || true
        fi
    done
fi

echo ""
echo "[$(date)] ✅ PostgreSQL cleanup completed!"
echo ""
echo "[$(date)] Verify:"
echo "  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\\l'"
