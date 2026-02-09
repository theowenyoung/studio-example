# Studio

用 Docker Compose + 裸机服务器管理所有项目的 monorepo 模板。

## 为什么做这个

大多数独立开发者和小团队的部署需求其实很简单：几个 Web 应用、一个数据库、一些第三方服务。但现有的方案要么太贵（Vercel/Railway 按用量计费，规模一上来成本不可控），要么太重（Kubernetes 解决的是大规模编排问题，对于几台服务器来说是杀鸡用牛刀）。

这个项目的理念是：**用最简单的工具组合，搭建一套完整的生产级部署流程**。

- **裸机服务器而非云托管平台**。目前生产环境跑在两台 Hetzner VPS 上：生产服务器 CCX13（2 独立 vCPU / 8 GB，新加坡）月费 €21，预览服务器 CX33（4 共享 vCPU / 8 GB，欧洲）月费 €5，总共 €26/月跑着十几个服务。Docker Compose 管理容器足够好用，不需要 Kubernetes
- **Git 分支即环境**。`main` 分支推送就是部署到生产，其他分支自动创建隔离的预览环境（独立的数据库、域名、容器），合并后自动清理。不需要手动切环境
- **本地构建，远程拉取**。Docker 镜像在本地或 CI 构建好推到 ECR，服务器只做 `docker pull` + `docker compose up`。服务器上不装 Node.js、不跑 build，保持干净。通过 [docker-rollout](https://github.com/wowu/docker-rollout) 实现零停机部署——先启动新容器通过健康检查，再切换流量、停掉旧容器，失败时自动回滚
- **一个文件定义所有任务**。`mise.toml` 是唯一的任务入口，CI 工作流只调用 `mise run <task>`，不重复实现逻辑。本地开发和 CI 执行的是同一套命令
- **服务器是可替换的**。服务器挂了不用慌。Ansible playbook 定义了完整的服务器状态，Docker 镜像在 ECR，密钥在 AWS Parameter Store，数据库定期备份到 S3。开一台新机器，跑 `mr server-init` → `mr deploy-infra` → `mr deploy-apps`，整个环境就回来了。不需要记住服务器上改过什么
- **基础设施也在仓库里**。调优过的 PostgreSQL、双持久化的 Redis、每天自动备份到 S3 的备份服务（Postgres + Redis + SQLite 全覆盖），都是配好的，不用从零开始
- **Monorepo 放一切**。应用代码、基础设施配置、部署脚本、CI 工作流全部放在一个仓库。改一个配置就能看到它如何影响从构建到部署的整条链路

这套方案实际跑在生产环境中，管理着多个 Web 应用和第三方服务。

## 特性

- 基于 Git 分支自动检测环境（main → 生产，其他 → 预览）
- 每个功能分支自动创建隔离的预览环境（独立数据库、域名、容器）
- Docker 镜像本地构建，推送到 AWS ECR，服务器拉取部署
- 使用 AWS Parameter Store 管理敏感配置，支持模板化渲染
- 通过 Ansible 实现服务器初始化和应用部署
- 支持多服务器生产环境
- 零停机部署（docker-rollout）
- GitHub Actions CI/CD 工作流

## 自定义配置

本仓库包含占位符，使用前需要替换为你自己的值：

| 占位符 | 说明 | 涉及文件 |
|--------|------|----------|
| `YOUR_AWS_ACCOUNT_ID` | AWS 账户 ID，用于 ECR 镜像仓库地址 | `mise.toml`, `scripts/build-lib.sh`, `ansible/inventory.yml`, `ansible/group_vars/all.yml`, `ansible/playbooks/deploy-external-app.yml`, `.github/workflows/*.yml` |
| `YOUR_PROD_SERVER_IP` | 生产服务器 IP | `mise.toml`, `ansible/inventory.yml` |
| `YOUR_PREVIEW_SERVER_IP` | 预览服务器 IP | `mise.toml`, `ansible/inventory.yml` |
| `YOUR_PROD2_SERVER_IP` | 第二台生产服务器 IP（可选） | `ansible/inventory.yml` |
| `YOUR_S3_BUCKET` | S3 存储桶名称（Outline 文件存储用） | `external-apps/outline/.env.example` |

可以用全局搜索替换快速完成配置：

```bash
# 例如替换 AWS Account ID
grep -r "YOUR_AWS_ACCOUNT_ID" --include="*.yml" --include="*.toml" --include="*.sh" -l | \
  xargs sed -i '' 's/YOUR_AWS_ACCOUNT_ID/123456789012/g'
```

## 项目结构

```
studio/
├── js-apps/           # Node.js 应用 (hono-demo, proxy, blog, storefront, api, admin)
├── js-packages/       # 共享 TypeScript 包
├── infra-apps/        # 基础设施 (postgres, redis, caddy, backup, db-prepare)
├── external-apps/     # 第三方服务 (meilisearch, owen-blog)
├── rust-packages/     # Rust 工具 (psenv - AWS Parameter Store 同步)
├── ansible/           # 部署 playbooks
├── docker/            # 共享 Dockerfiles
└── scripts/           # 构建和部署脚本
```

## 快速开始

### 前置要求

- 在 `ansible/inventory.yml` 里配置服务器 IP 地址
- 统一使用 [mise](https://mise.dev) 管理任务，根目录用 `mise run`（别名 `mr`），应用内部用 `pnpm`

<details>
<summary>推荐的 mise bashrc 配置</summary>

```bash
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

source <(mise completion bash --include-bash-completion-lib)

function mr() {
  mise run "$@"
}
```

</details>

### 首次设置

```bash
# 1. 安装本地 HTTPS 证书
brew install mkcert
mkcert -install
mkdir -p infra-apps/caddy/.local/certs
mkcert -cert-file infra-apps/caddy/.local/certs/local-dev.pem \
         -key-file infra-apps/caddy/.local/certs/local-dev-key.pem \
         "*.local.owenyoung.com"

# 2. 初始化环境
mr env                    # 从 AWS Parameter Store 同步 .env 文件
docker network create shared
mr up                     # 启动基础设施 (postgres, redis, caddy)
mr dev-db-prepare         # 创建数据库和用户, （以后每次 dev-db-prepare 之前，记得要先 mr env, 更新 env

# 3. 安装依赖并初始化应用
pnpm install
mr dev-db-migrate         # 运行应用数据库迁移
```

### 日常开发

```bash
mr up                     # 启动基础设施（如果未启动）
mr dev-hono               # 启动单个应用
mr dev                    # 启动所有应用
mr down                   # 停止基础设施
```

## 架构设计

### 环境自动检测

根据 git 分支自动决定部署目标，无需手动指定：

- **main 分支** → 生产环境 (prod)
- **其他分支** → 预览环境 (preview)

### Preview 环境隔离

每个功能分支都有独立的预览环境（使用双分隔符便于解析）：

| 资源   | 分支 `feat-auth` 示例                                    |
| ------ | -------------------------------------------------------- |
| 数据库 | `hono_demo__feat_auth`（双下划线）                       |
| 域名   | `hono-demo--feat-auth.preview.owenyoung.com`（双中划线） |
| 容器   | `hono-demo--feat-auth-hono-demo-1`                       |
| 目录   | `/srv/hono-demo--feat-auth`                              |

### 环境变量模板

使用 `psenv` (Rust 工具) 进行两阶段渲染：

```bash
# .env.example 示例
POSTGRES_USER=                                    # 源变量：从 AWS Parameter Store 获取
DB_HOST=${CTX_PG_HOST:-localhost}                 # 计算变量：CTX_* 由构建脚本注入
DATABASE_URL=postgresql://${POSTGRES_USER}@${DB_HOST}/${POSTGRES_DB}
```

- **源变量**: 敏感信息存储在 AWS Parameter Store，构建时拉取
- **计算变量**: `${VAR:-default}` 语法，本地开发不设置 `CTX_*` 则使用默认值

### 上传环境变量到 AWS Parameter Store

使用 `mr env-push` 批量上传环境变量：

```bash
# 1. 复制模板并编辑
cp .env.parameter.example .env.parameter.local
vim .env.parameter.local

# 2. 上传到 AWS Parameter Store
mr env-push
```

文件格式支持多个前缀，用 `# PREFIX=` 注释切换：

```bash
# PREFIX=/studio-dev/umami/
DATABASE_URL=postgresql://app_user:xxx@postgres:5432/umami
APP_SECRET=dev-secret

# PREFIX=/studio-prod/umami/
DATABASE_URL=postgresql://app_user:yyy@postgres:5432/umami
APP_SECRET=prod-secret
```

变量会上传到 `{PREFIX}{KEY}`，例如 `/studio-dev/umami/DATABASE_URL`。

### 多服务器部署

生产环境支持多台服务器，每台有独立的基础设施。

**服务器配置** (`ansible/inventory.yml`)：`prod1`（主）、`prod2`（副，按需启用）、`preview`

**指定应用部署目标**：在 `.env.example` 中添加 `DEPLOY_SERVER=prod2`

**数据库迁移分离**：

```
infra-apps/db-prepare/
├── migrations/           # 通用（001-099，所有服务器）
├── migrations-prod1/     # prod1 专属（101-199）
├── migrations-prod2/     # prod2 专属（201-299）
└── migrations-prod3/     # prod3 专属（301-399）
```

<details>
<summary>添加新服务器步骤</summary>

1. 在 `ansible/inventory.yml` 添加服务器配置
2. 创建 `migrations-prodN/` 目录
3. `mr server-init` 初始化服务器
4. `mr deploy-infra` 部署基础设施
5. `mr deploy-db-prepare --server=prodN` 创建数据库
6. 在应用 `.env.example` 中设置 `DEPLOY_SERVER=prodN`

</details>

## 部署指南

### 1. 准备服务器

```bash
# 安装 Ansible 依赖（首次）
ansible-galaxy install -r ansible/requirements.yml

# 在 Hetzner 创建服务器，绑定 >10G volume 用于数据存储

# 创建 deploy 用户
mr server-init-user <server-ip> [<server-ip>...]

# 更新 ansible/inventory.yml 后初始化服务器
mr server-init
```

### 2. 部署基础设施

> 在 main 分支执行部署到生产，其他分支部署到 preview，需分别执行。

```bash
mr deploy-infra           # 部署所有基础设施
mr deploy-db-prepare      # 创建数据库
```

### 3. 部署应用

```bash
mr deploy-hono            # 后端应用（Docker + 零停机）
mr deploy-storefront      # SSG 应用（静态文件）
mr deploy-owen-blog       # 外部应用
```

### 4. 数据库备份与恢复

```bash
# 连接服务器
mr ssh

# 在服务器上执行
mr db-backup-now          # 手动备份
mr db-restore-s3          # 从 S3 恢复最新备份
```

### 5. 回滚

切换到目标 commit 后重新 deploy 即可。

### 服务器目录结构

```
/srv/
├── postgres/            # PostgreSQL
├── redis/               # Redis
├── caddy/               # Caddy 反向代理
├── backup/              # 备份服务
├── db-prepare/          # 数据库迁移
├── hono-demo/           # JS 应用示例
└── umami/               # 外部应用示例

/data/
├── docker/              # Docker volumes
└── backups/             # 备份数据
```

### ECR 镜像标签

- **生产**: `prod-latest`, `prod-20251125143052`
- **预览**: `preview-{branch}`, `preview-{branch}-20251125143052`

生命周期规则在首次构建时自动设置，已有仓库可执行 `mr ecr-lifecycle`。
