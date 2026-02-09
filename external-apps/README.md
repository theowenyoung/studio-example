# External Apps

此目录包含源码不在本项目的应用部署配置：

- 使用第三方 Docker 镜像的服务
- 独立 git repo 的项目

## 结构

每个应用包含：
- `build.sh` - 构建脚本（准备部署配置）
- `docker-compose.yml` - 本地开发配置
- `docker-compose.prod.yml` - 生产环境配置
- `.env.example` - 环境变量模板
- `.env` - 本地开发环境变量

## 应用列表

- **meilisearch** - 搜索引擎服务
- **umami** - 网站分析服务
- **n8n** - 工作流自动化平台
- **status** - 状态监控页面
- **buzzing-archive** - Buzzing 归档服务
- **owen-blog** - 博客服务

## 开发

```bash
# 启动所有服务（包括 external-apps）
mise run dev-up

# 启动单个服务
mise run dev-up-meilisearch

# 查看日志
mise run dev-logs-meilisearch
```

## 部署

```bash
# 构建并部署
mise run build-meilisearch
mise run deploy-meilisearch
```
