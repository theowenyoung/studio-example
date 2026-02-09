# n8n

n8n 是一个可扩展的工作流自动化工具，使用 PostgreSQL 作为数据库存储。

## 配置

### 环境变量

| 变量 | 说明 |
|------|------|
| `N8N_ENCRYPTION_KEY` | 凭证加密密钥（必需，使用 `openssl rand -hex 32` 生成） |
| `DB_TYPE` | 数据库类型，固定为 `postgresdb` |
| `DB_POSTGRESDB_*` | PostgreSQL 连接配置 |
| `N8N_HOST` | n8n 访问域名 |
| `WEBHOOK_URL` | Webhook 回调 URL |

### 数据持久化

n8n 数据存储在 Docker volume `n8n_data` 中，包含：
- 工作流定义
- 执行历史
- 凭证数据（已加密）

## 本地开发

```bash
# 启动 n8n
mise run dev-up-n8n

# 访问
open https://n8n.local.owenyoung.com
```

## 部署

```bash
# 1. 确保数据库已创建（如果是首次部署）
mise run deploy-db-prepare

# 2. 构建并部署
mise run deploy-n8n
```

## 首次使用

1. 访问 n8n URL
2. 创建管理员账户
3. 开始创建工作流
