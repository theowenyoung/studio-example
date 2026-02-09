# Database prepare

一次性执行数据库管理员操作的 Docker 服务，用于创建数据库、用户和设置权限。

## 功能

- 执行管理员级别的 SQL 操作
- 创建数据库和用户
- 配置数据库权限和角色
- 支持可重复执行（幂等性）

## 目录结构

```
db-prepare/
├── docker-compose.yml       # Docker Compose 配置
├── .env                     # 环境变量（不提交到版本控制）
├── .env.example             # 环境变量模板
├── scripts/
│   ├── common.sh            # 通用数据库设置函数（POSIX sh 兼容）
│   └── run-migrations.sh    # 迁移执行脚本（POSIX sh 兼容）
└── migrations/
    └── 001-create-demo-db.sh # 迁移脚本示例
```

## 使用方法

### 1. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑 .env 文件，设置实际的密码
vim .env
```

### 2. 确保 PostgreSQL 服务正在运行

```bash
# 启动 PostgreSQL（如果还没运行）
cd ../postgres
docker compose up -d
```

### 3. 运行迁移

```bash
# 方式 1: 使用 docker compose run (推荐，自动清理)
docker compose run --rm db-prepare

# 方式 2: 使用 mise task (最推荐)
cd ../..  # 回到项目根目录
mise run db:admin:migrations

# 方式 3: 使用 docker compose up (需手动清理)
docker compose up
docker compose down  # 需要手动清理
```

## 创建新的数据库

有两种方式创建数据库，取决于你的安全需求：

### 方式 1: 使用共享的 app_user（推荐用于大多数应用）

适用场景：大多数普通应用，简化用户管理

参考：`migrations/002-create-hono-demo-db.sh`

```sh
#!/bin/sh
set -e

# Source the functions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

# ==========================================
# Configuration - Modify these variables
# ==========================================
DB_NAME="myapp"

# ==========================================
# Create Database with Shared app_user
# ==========================================

create_database_with_app_user "$DB_NAME"
```

**优点**：
- 极其简单，只需修改 `DB_NAME` 变量
- 共享 app_user，减少用户数量
- 适合大多数应用场景
- 所有逻辑都封装在 `common.sh` 中

**环境变量**：
- 只需要 `COMMON_POSTGRES_APP_USER_PASSWORD`（已在 001 迁移中配置）

**使用**：
```bash
DATABASE_URL=postgresql://app_user:<password>@<host>:5432/myapp
```

---

### 方式 2: 创建独立用户和数据库（用于高安全需求）

适用场景：需要严格隔离的应用，或需要独立的只读用户

参考：`migrations/003-create-demo-db-with-dedicated-user.sh`

**步骤**：

1. **创建迁移脚本** `migrations/00X-create-myapp-db-with-dedicated-user.sh`:

```sh
#!/bin/sh
set -e

# Source the functions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

# ==========================================
# Configuration - Modify these variables
# ==========================================
DB_NAME="myapp"
USER_NAME="myapp"
USER_PASSWORD_ENV="POSTGRES_MYAPP_USER_PASSWORD"
READONLY_PASSWORD_ENV="POSTGRES_MYAPP_READONLY_PASSWORD"

# ==========================================
# Create Dedicated Database with Users
# ==========================================

# Validate required environment variables
require_env_var "$USER_PASSWORD_ENV"
require_env_var "$READONLY_PASSWORD_ENV"

# Get passwords from environment
eval USER_PASSWORD="\$$USER_PASSWORD_ENV"
eval READONLY_PASSWORD="\$$READONLY_PASSWORD_ENV"

# Create database with dedicated users
create_database_with_dedicated_users "$DB_NAME" "$USER_NAME" "$USER_PASSWORD" "$READONLY_PASSWORD"
```

2. **添加执行权限**：
```bash
chmod +x migrations/00X-create-myapp-db-with-dedicated-user.sh
```

3. **配置环境变量** 在 `.env.example` 和 `.env` 中添加：
```bash
POSTGRES_MYAPP_USER_PASSWORD=
POSTGRES_MYAPP_READONLY_PASSWORD=
```

**优点**：
- 完全隔离，每个应用有独立的用户
- 支持只读用户（适合分析、报表等场景）
- 更高的安全性
- 配置清晰，所有变量集中在顶部
- 所有逻辑都封装在 `common.sh` 中

**使用**：
```bash
# 读写
DATABASE_URL=postgresql://myapp:<password>@<host>:5432/myapp

# 只读
DATABASE_URL=postgresql://myapp_readonly:<password>@<host>:5432/myapp
```

---

### 选择建议

- **使用方式 1（共享 app_user）**：大多数内部应用、开发环境
- **使用方式 2（独立用户）**：生产环境、需要只读访问、高安全要求的应用

### 运行迁移

```bash
# 本地开发
mise run dev-db-prepare

# 生产部署
mise run deploy-db-prepare
```

## 注意事项

- **幂等性**: 所有脚本使用 `IF NOT EXISTS` 检查，可以安全地重复执行
- **密码安全**: 永远不要将 `.env` 文件提交到版本控制
- **执行顺序**: 脚本按字母顺序执行，使用数字前缀控制顺序（如 001-, 002-）
- **自动清理**: 使用 `docker compose run --rm` 会自动清理容器

