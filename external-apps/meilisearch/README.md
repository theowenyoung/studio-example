# Meilisearch

搜索引擎服务，使用官方 Meilisearch Docker 镜像。

## 本地开发

```bash
# 启动 Meilisearch
mise run dev-up-meilisearch

# 查看日志
mise run dev-logs-meilisearch

# 停止
mise run dev-down-meilisearch
```

访问地址：http://localhost:7700

## 部署

```bash
# 构建（准备配置）
mise run build-meilisearch

# 部署到生产环境
mise run deploy-meilisearch
```

## 配置

- **端口**: 7700
- **数据持久化**: Docker volume `meilisearch_data`
- **环境变量**:
  - `MEILI_MASTER_KEY`: API 密钥
  - `MEILI_ENV`: 环境（development/production）

## 文档

官方文档：https://www.meilisearch.com/docs
