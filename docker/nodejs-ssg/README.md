# Shared SSG Dockerfile

这是一个通用的 Dockerfile，用于构建所有 Node.js SSG（Static Site Generator）项目。

## 支持的框架

- **Remix** - 构建输出：`build/client/`
- **Next.js** - 构建输出：`out/`
- **Vite** - 构建输出：`dist/`

## 使用方法

### 构建镜像

```bash
# 从项目根目录运行
docker build \
  -f docker/nodejs-ssg/Dockerfile \
  --build-arg APP_NAME=blog \
  -t my-blog:latest \
  .
```

### Build Arguments

- `APP_NAME` (必需) - 要构建的应用名称，对应 `js-apps/` 下的目录名
  - 示例：`blog`, `storefront`

## 工作原理

### 构建阶段 (Build Stage)

1. 使用 `node:22-alpine` 作为基础镜像
2. 安装 pnpm
3. 复制 monorepo 的 workspace 配置
4. 复制共享包 (`js-packages/`)
5. 复制指定的应用 (`js-apps/${APP_NAME}`)
6. 安装依赖并构建

### 运行阶段 (Runtime Stage)

1. 使用 `nginx:alpine` 作为基础镜像
2. 复制优化的 nginx 配置
3. 智能检测并复制构建输出：
   - 尝试 `build/client` (Remix)
   - 尝试 `out` (Next.js)
   - 尝试 `dist` (Vite)
4. 将找到的构建输出复制到 nginx 的 html 目录

## Nginx 配置特性

位于 `docker/nodejs-ssg/nginx.conf`：

- ✅ SPA 路由支持 (fallback to index.html)
- ✅ 静态资源缓存 (1 year)
- ✅ HTML 文件禁用缓存
- ✅ Gzip 压缩
- ✅ 安全响应头
- ✅ Health check 端点 (`/health`)

## 在项目中使用

每个 SSG 项目的 `build.sh` 应该这样使用：

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="blog"  # 或 "storefront"
VERSION="$(get_version)"
IMAGE_NAME="${ECR_REGISTRY}/${SERVICE_NAME}"
IMAGE_TAG="${IMAGE_NAME}:${VERSION}"

# 从项目根目录构建
cd "$SCRIPT_DIR/../.."
docker build \
  -f docker/nodejs-ssg/Dockerfile \
  --build-arg APP_NAME="${SERVICE_NAME}" \
  -t "${IMAGE_TAG}" \
  .
```

## 添加新的 SSG 项目

1. 在 `js-apps/` 下创建新项目
2. 确保项目有 `pnpm build` 命令
3. 确保构建输出在以下之一：
   - `build/client/` (Remix)
   - `out/` (Next.js)
   - `dist/` (Vite)
4. 创建 `build.sh` 使用此 Dockerfile
5. 就这样！无需创建独立的 Dockerfile

## 本地测试

```bash
# 构建镜像
docker build \
  -f docker/nodejs-ssg/Dockerfile \
  --build-arg APP_NAME=blog \
  -t test-blog:latest \
  .

# 运行容器
docker run -p 8080:80 test-blog:latest

# 访问
open http://localhost:8080

# Health check
curl http://localhost:8080/health
```

## 故障排查

### 构建失败：找不到构建输出

确保你的项目正确配置了构建输出目录：

- **Remix**: 默认输出到 `build/client`
- **Next.js**: 需要配置 `output: 'export'` 并输出到 `out`
- **Vite**: 默认输出到 `dist`

### Nginx 404 错误

检查构建输出是否包含 `index.html`：

```bash
docker run --rm test-blog:latest ls -la /usr/share/nginx/html/
```

### 路由不工作

确保 nginx 配置中的 `try_files` 正确设置：

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

## 性能优化

- 多阶段构建：最终镜像只包含 nginx 和静态文件
- Alpine Linux：最小化镜像大小
- Gzip 压缩：自动压缩文本内容
- 静态资源缓存：1 年过期时间
- 并行构建：使用 BuildKit 加速
