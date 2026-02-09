#!/bin/bash
# URL 解析工具函数

# 解析 PostgreSQL URL
# 格式: postgresql://user:password@host:port/database
# 或: postgres://user:password@host:port/database
parse_POSTGRES_ADMIN_URL() {
    local url="$1"

    if [ -z "$url" ]; then
        return 1
    fi

    # 移除协议前缀
    url="${url#postgresql://}"
    url="${url#postgres://}"

    # 提取用户名和密码
    if [[ "$url" =~ ^([^:]+):([^@]+)@(.+)$ ]]; then
        export PG_USER="${BASH_REMATCH[1]}"
        export PG_PASSWORD="${BASH_REMATCH[2]}"
        url="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^([^@]+)@(.+)$ ]]; then
        export PG_USER="${BASH_REMATCH[1]}"
        export PG_PASSWORD=""
        url="${BASH_REMATCH[2]}"
    fi

    # 提取主机和端口
    if [[ "$url" =~ ^([^:]+):([0-9]+)/(.+)$ ]]; then
        export PG_HOST="${BASH_REMATCH[1]}"
        export PG_PORT="${BASH_REMATCH[2]}"
        export PG_DATABASE="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^([^/]+)/(.+)$ ]]; then
        export PG_HOST="${BASH_REMATCH[1]}"
        export PG_PORT="5432"
        export PG_DATABASE="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    return 0
}

# 解析 Redis URL
# 格式: redis://:password@host:port/db
# 或: redis://host:port/db
# 或: redis://host:port
parse_redis_url() {
    local url="$1"

    if [ -z "$url" ]; then
        return 1
    fi

    # 移除协议前缀
    url="${url#redis://}"
    url="${url#rediss://}"

    # 提取用户名和密码
    # 支持格式: username:password@host 或 :password@host
    if [[ "$url" =~ ^([^:]*):([^@]+)@(.+)$ ]]; then
        export REDIS_USER="${BASH_REMATCH[1]}"
        export REDIS_PASS="${BASH_REMATCH[2]}"
        url="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^([^@]+)@(.+)$ ]]; then
        # 只有用户名，没有密码
        export REDIS_USER="${BASH_REMATCH[1]}"
        export REDIS_PASS=""
        url="${BASH_REMATCH[2]}"
    else
        export REDIS_USER=""
        export REDIS_PASS=""
    fi

    # 提取主机、端口和数据库
    if [[ "$url" =~ ^([^:]+):([0-9]+)/([0-9]+)$ ]]; then
        export REDIS_HOST="${BASH_REMATCH[1]}"
        export REDIS_PORT="${BASH_REMATCH[2]}"
        export REDIS_DB="${BASH_REMATCH[3]}"
    elif [[ "$url" =~ ^([^:]+):([0-9]+)$ ]]; then
        export REDIS_HOST="${BASH_REMATCH[1]}"
        export REDIS_PORT="${BASH_REMATCH[2]}"
        export REDIS_DB="0"
    elif [[ "$url" =~ ^([^/]+)$ ]]; then
        export REDIS_HOST="${BASH_REMATCH[1]}"
        export REDIS_PORT="6379"
        export REDIS_DB="0"
    else
        return 1
    fi

    return 0
}
