# Umami (Umami Analytics)

Self-hosted web analytics service.

## Configuration

AWS Parameter Store 前缀: `/studio-dev/umami/`

需要配置的参数:
- `DATABASE_URL` - PostgreSQL 连接字符串，格式: `postgresql://app_user:password@postgres-host:5432/umami`
- `APP_SECRET` - 用于加密 session 的密钥

## Database

数据库通过 `infra-apps/db-prepare/migrations-prod1/103-create-umami-db.sh` 创建。

## Docker Image

使用官方镜像: `docker.umami.is/umami-software/umami:postgres-v2.20.1`

查看最新版本: https://hub.docker.com/r/umamisoftware/umami/tags

## Deploy

```bash
mr build-umami
mr deploy-umami
```

## Default Login

首次部署后，默认登录:
- 用户名: `admin`
- 密码: `umami`

请立即修改默认密码！
