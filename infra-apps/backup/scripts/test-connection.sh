#!/bin/bash
# 测试数据库连接脚本

set -e

echo "========================================"
echo "Testing Database Connections"
echo "========================================"
echo ""

# 测试 PostgreSQL 连接
if [ -n "$POSTGRES_ADMIN_URL" ]; then
    echo "Testing PostgreSQL connection..."
    echo "POSTGRES_ADMIN_URL: ${POSTGRES_ADMIN_URL%:*@*}:*****@${POSTGRES_ADMIN_URL##*@}"  # 隐藏密码
    
    # 解析 URL
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
    
    echo "  Host: $POSTGRES_HOST"
    echo "  Port: $POSTGRES_PORT"
    echo "  User: $POSTGRES_USER"
    
    export PGPASSWORD="$COMMON_POSTGRES_PASSWORD"
    if pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "  Status: ✅ Connected"
        
        # 列出数据库
        echo "  Databases:"
        psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | sed 's/^/    - /'
    else
        echo "  Status: ❌ Connection failed"
        exit 1
    fi
else
    echo "PostgreSQL: Not configured (POSTGRES_ADMIN_URL not set)"
fi

echo ""

# 测试 Redis 连接
if [ -n "$REDIS_DOCKER_URL" ]; then
    echo "Testing Redis connection..."
    echo "REDIS_DOCKER_URL: ${REDIS_DOCKER_URL%:*@*}:*****@${REDIS_DOCKER_URL##*@}"  # 隐藏密码
    
    # 简单解析 Redis URL
    url="${REDIS_DOCKER_URL#redis://}"
    
    if [[ "$url" =~ ^:([^@]+)@(.+)$ ]]; then
        COMMON_REDIS_PASSWORD="${BASH_REMATCH[1]}"
        url="${BASH_REMATCH[2]}"
    fi
    
    if [[ "$url" =~ ^([^:]+):([0-9]+)$ ]]; then
        REDIS_HOST="${BASH_REMATCH[1]}"
        REDIS_PORT="${BASH_REMATCH[2]}"
    else
        REDIS_HOST="${url%%:*}"
        REDIS_PORT="6379"
    fi
    
    echo "  Host: $REDIS_HOST"
    echo "  Port: $REDIS_PORT"
    
    # 测试连接
    if [ -n "$COMMON_REDIS_PASSWORD" ]; then
        REDIS_CMD="redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $COMMON_REDIS_PASSWORD --no-auth-warning"
    else
        REDIS_CMD="redis-cli -h $REDIS_HOST -p $REDIS_PORT"
    fi
    
    if $REDIS_CMD ping > /dev/null 2>&1; then
        echo "  Status: ✅ Connected"
        
        # 显示 Redis 信息
        INFO=$($REDIS_CMD INFO server 2>/dev/null | grep redis_version | cut -d: -f2 | tr -d '\r')
        echo "  Version: $INFO"
    else
        echo "  Status: ❌ Connection failed"
        exit 1
    fi
else
    echo "Redis: Not configured (REDIS_DOCKER_URL not set)"
fi

echo ""
echo "========================================"
echo "All configured databases are accessible!"
echo "========================================"
