FROM alpine:latest

# 添加 edge 仓库以获取 PostgreSQL 18
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

# 安装依赖
# 使用 postgresql18-client 匹配服务器版本（从 edge 仓库）
RUN apk add --no-cache \
    postgresql18-client \
    redis \
    sqlite \
    aws-cli \
    dcron \
    bash \
    gzip \
    coreutils \
    findutils

# 创建备份目录
RUN mkdir -p /backups/postgres /backups/redis /backups/sqlite

# 复制备份脚本（从 repo root 的相对路径）
COPY infra-apps/backup/scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# 复制入口脚本（从 repo root 的相对路径）
COPY infra-apps/backup/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建日志目录
RUN mkdir -p /var/log && touch /var/log/backup.log

ENTRYPOINT ["/entrypoint.sh"]
