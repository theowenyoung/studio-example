# Owen Blog

个人博客，使用 Zola 静态站点生成器构建。

源仓库：https://github.com/theowenyoung/blog

## 构建流程

1. 从 GitHub 拉取源码（`--depth 1`）
2. 使用 `zola build` 构建静态文件到 `public/`
3. 使用 `docker/static-site/Dockerfile` 打包成 nginx 镜像
4. 推送到 ECR
5. 复制 `meilisearch-docs-scraper-config.json` 到 deploy-dist（用于 post-deploy）

## 部署

```bash
# 构建
mise run build-owen-blog

# 部署到生产环境
mise run deploy-owen-blog

# 构建搜索索引（部署后自动运行，也可手动执行）
mise run post-deploy-owen-blog
```

## Post-Deploy: 搜索索引构建

部署完成后会自动运行 `post-deploy.sh` 来构建 Meilisearch 搜索索引：

1. 等待服务启动（30 秒）
2. 使用 `docs-scraper` 爬取网站内容
3. 将内容索引到 Meilisearch

如需手动重建索引，运行：
```bash
mise run post-deploy-owen-blog
```

## 技术栈

- **生成器**: Zola
- **Web 服务器**: Nginx (Alpine，复用 `docker/nodejs-ssg/nginx.conf`）
- **端口**: 3000
- **Docker 配置**: 复用 `docker/nodejs-ssg/docker-compose.template.yml`

## 环境变量

- `COMMON_OWEN_GH_TOKEN`: GitHub token（从 AWS Parameter Store 获取）
- `MEILISEARCH_HOST_URL`: Meilisearch 服务地址（用于 post-deploy 索引构建）
- `MEILISEARCH_API_KEY`: Meilisearch API 密钥（从 AWS Parameter Store 获取）

## 复用的配置

此项目复用了以下共享配置：
- `docker/static-site/Dockerfile` - 静态站点 Dockerfile
- `docker/nodejs-ssg/nginx.conf` - Nginx 配置
- `docker/nodejs-ssg/docker-compose.template.yml` - Docker Compose 模板
