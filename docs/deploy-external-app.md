# 部署 External App 指南

快速指南：如何在本项目中部署一个新的第三方应用（使用现有 Docker 镜像）。

## 环境变量原则

**重要**: 区分敏感和非敏感环境变量的存放位置：

| 类型            | 存放位置                              | 示例                     |
| --------------- | ------------------------------------- | ------------------------ |
| **敏感/动态**   | `.env.example` → AWS Parameter Store  | 密码、密钥、CTX\_\* 变量 |
| **非敏感/固定** | `docker-compose.yml` 的 `environment` | 端口、时区、功能开关     |

这样做的好处：

- 配置更清晰，敏感/非敏感分离
- 非敏感配置直接在版本控制中可见
- 减少 AWS Parameter Store 依赖

## 步骤概览

1. 创建数据库（如需要）
2. 创建应用目录和配置
3. 添加 AWS Parameter Store 参数
4. 添加 mise 任务
5. 配置 Caddy 路由（本地 + 生产）
6. 提醒 管理员创建生产环境 DNS
7. 部署

## 详细步骤

### 1. 创建数据库（如需要）

#### 1.1 添加数据库名称变量

在 `infra-apps/db-prepare/.env.example` 中添加数据库名称变量：

```bash
# prod1 databases 区域
{APP}_DB_NAME={app}${CTX_DB_SUFFIX:-}
```

#### 1.2 创建迁移脚本

在 `infra-apps/db-prepare/migrations-prod1/` 创建迁移脚本：

```bash
# 文件: infra-apps/db-prepare/migrations-prod1/1XX-create-{app}-db.sh
#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

DB_NAME="${{APP}_DB_NAME:-{app}}"
create_database_with_app_user "$DB_NAME"
```

```bash
chmod +x infra-apps/db-prepare/migrations-prod1/1XX-create-{app}-db.sh
```

### 2. 创建应用目录

```bash
mkdir -p external-apps/{app-name}
```

创建以下文件：

#### `.env.example`

只放敏感或动态的环境变量：

```bash
# App Configuration
# AWS Parameter Store Prefix: /studio-dev/

# 应用特有的密钥（需添加到 AWS Parameter Store）
APP_SECRET_KEY=

# 数据库配置（敏感，使用共享 app_user）
COMMON_POSTGRES_APP_USER=
COMMON_POSTGRES_APP_USER_PASSWORD=
DB_HOST=${CTX_PG_HOST:-postgres}
POSTGRES_DB={app}${CTX_DB_SUFFIX:-}
DATABASE_URL=postgresql://${COMMON_POSTGRES_APP_USER}:${COMMON_POSTGRES_APP_USER_PASSWORD}@${DB_HOST}:5432/${POSTGRES_DB}

# 公开 URL（动态，依赖环境）
# ⚠️ 必需！CI 通过 PUBLIC_URL* 变量生成部署摘要
PUBLIC_URL=https://{app}${CTX_DNS_SUFFIX:-}.${CTX_ROOT_DOMAIN:-local.owenyoung.com}
```

#### `docker-compose.prod.yml`

> **⚠️ 重要：必须查询最新版本**
>
> 在创建配置前，**必须**通过 API 查询应用的最新稳定版本，**禁止凭记忆填写版本号**：
>
> ```bash
> # GitHub 项目 - 查询最新 release
> curl -s https://api.github.com/repos/{owner}/{repo}/releases/latest | jq -r '.tag_name'
>
> # Docker Hub 官方镜像 - 查询最新 tag
> curl -s https://hub.docker.com/v2/repositories/library/{image}/tags?page_size=10 | jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+' | head -5
> ```
>
> 示例：
> - Ghost: `curl -s https://api.github.com/repos/TryGhost/Ghost/releases/latest | jq -r '.tag_name'`
> - n8n: `curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | jq -r '.tag_name'`

```yaml
name: ${DOCKER_SERVICE_NAME}

services:
  ${DOCKER_SERVICE_NAME}:
    # ⚠️ 使用固定版本号，不要用 latest
    # ⚠️ 必须通过 API 查询最新版本，禁止凭记忆填写！
    image: vendor/image:1.2.3
    restart: unless-stopped
    env_file: .env
    environment:
      # 非敏感配置放这里，不要放 .env.example
      PORT: 3000 # Caddy 期望服务监听 3000 端口
      NODE_ENV: production
      TZ: Asia/Shanghai
      DISABLE_TELEMETRY: "true"
    networks:
      - shared
    healthcheck:
      test:
        [
          "CMD",
          "wget",
          "--quiet",
          "--tries=1",
          "--spider",
          "http://127.0.0.1:3000/health",
        ]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  shared:
    external: true
```

#### `docker-compose.yml`（本地开发）

```yaml
services:
  {app}:
    # ⚠️ 使用固定版本号，与 prod 保持一致
    # ⚠️ 必须通过 API 查询最新版本，禁止凭记忆填写！
    image: vendor/image:1.2.3
    restart: unless-stopped
    env_file: .env
    environment:
      # 非敏感配置放这里，与 prod 保持一致
      PORT: 3000
      NODE_ENV: production
      TZ: Asia/Shanghai
      DISABLE_TELEMETRY: "true"
    ports:
      - "900X:3000" # 选择未使用的端口
    networks:
      - shared

networks:
  shared:
    external: true
```

#### `build.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

detect_environment

SERVICE_BASE="{app}"
set_docker_service_name "$SERVICE_BASE"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_BASE (version: $VERSION)"
echo "🐳 Docker service name: $DOCKER_SERVICE_NAME"

rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

export DOCKER_SERVICE_NAME
envsubst <"$SCRIPT_DIR/docker-compose.prod.yml" >"$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

echo "$VERSION" >"$SCRIPT_DIR/$DEPLOY_DIST/version.txt"
generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

echo "✅ $SERVICE_BASE built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
```

```bash
chmod +x external-apps/{app}/build.sh
```

### 3. 添加 AWS Parameter Store 参数

管理员应为应用需要的密钥添加参数，路径格式：`/studio-dev/{KEY_NAME}`

### 4. 添加 mise 任务

在 `mise.toml` 中添加以下任务：

```toml
# 本地开发（在 dev-* 任务区域）
[tasks.dev-{app}]
description = "Start {app} service"
run = 'docker compose up'
dir = "external-apps/{app}"

# 构建（在 build-* 任务区域）
[tasks.build-{app}]
description = "Build {app}"
run = "bash external-apps/{app}/build.sh"

# 部署（在 deploy-* 任务区域）
[tasks.deploy-{app}]
description = "Deploy {app} (auto-detect environment)"
run = "bash scripts/deploy-external-app.sh {app}"
```

### CI 说明

CI 会自动检测 `external-apps/*/` 中有 `build.sh` 的目录，无需手动修改 CI 配置。

当 `external-apps/{app}/` 目录有变更时，CI 会自动：

1. 运行 `mr build-{app}`
2. 运行 `mr deploy-{app}`

### 5. 配置 Caddy 路由

需要配置两个地方：

#### 本地开发 (`infra-apps/caddy/dev-config/Caddyfile`)

```caddy
{app}.local.owenyoung.com {
    import local_tls
    reverse_proxy host.docker.internal:900X  # 与 docker-compose.yml 中的端口对应
}
```

#### 生产环境 (`infra-apps/caddy/src/config/production-prod1/app-services.caddy`)

```caddy
# {App Name}
{app}.owenyoung.com {
    import app_cache
    import resilient_proxy {app}:3000
}
```

注意：

- 本地开发使用 `host.docker.internal` 连接宿主机端口
- 生产环境使用 Docker 服务名（容器间通信），端口固定为 3000

### 6. 部署

```bash
# 首次部署需先运行数据库迁移
mr deploy-db-prepare

# 部署应用
mr deploy-{app}

# 重载 Caddy（如果添加了新域名）
mr reload-caddy
```

## 注意事项

- **端口**: Caddy 期望所有服务监听 3000 端口，如果镜像默认端口不同，需要通过环境变量配置
- **数据库**: 使用共享的 `app_user`，每个应用独立数据库
- **Redis**: 所有应用共享同一个 Redis 实例，通过 database 编号隔离（Redis 默认有 16 个 database，编号 0-15）：
  ```bash
  # 在 .env.example 中指定 database 编号
  REDIS_URL=redis://${REDIS_HOST}:6379/1  # 使用 database 1
  ```
  已分配的 database：
  - `/0` - 默认（基础设施/其他）
  - `/1` - Outline
- **SQLite Volume 命名规范**: 如果应用使用 SQLite 数据库，Docker volume 名称**必须**以 `sqlite_` 开头（如 `sqlite_ghost_content`），以便被统一备份策略识别
- **域名规则**:
  - 生产: `{app}.owenyoung.com`
  - 预览: `{app}--{branch}.preview.owenyoung.com`
  - 本地: `{app}.local.owenyoung.com`
