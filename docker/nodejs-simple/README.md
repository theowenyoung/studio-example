# Node.js Simple Dockerfile

这是一个专门为**不需要构建步骤**的纯 Node.js 应用设计的 Dockerfile。

## 与 nodejs/Dockerfile 的区别

| 特性 | nodejs/Dockerfile | nodejs-simple/Dockerfile |
|------|-------------------|-------------------------|
| **适用场景** | 需要编译的应用（TypeScript, 打包等） | 纯 JavaScript 应用 |
| **构建步骤** | ✅ 执行 `pnpm run build` | ❌ 跳过构建 |
| **依赖安装** | ✅ `pnpm install` | ✅ `pnpm install` |
| **产物导出** | `pnpm deploy --prod` | `pnpm deploy --prod` |
| **构建时间** | 较慢（需要编译） | 更快（只安装依赖） |

## 适用项目类型

### ✅ 适合使用 nodejs-simple

- 直接运行 `.js` 或 `.mjs` 文件的应用
- 不需要 TypeScript 编译的项目
- 不需要打包工具（Webpack, Vite, esbuild）的应用
- 简单的 Express, Hono, Fastify 等服务器应用

**示例项目**:
- `js-apps/proxy` - Hono 代理服务（直接运行 index.mjs）

### ❌ 不适合使用 nodejs-simple

- TypeScript 项目（需要 tsc 编译）
- 使用构建工具的项目（Vite, Next.js, Remix 等）
- 需要打包优化的生产应用
- Monorepo 中有跨包引用的项目

**这些项目应使用**: `docker/nodejs/Dockerfile`

## 使用方法

### 构建参数

```bash
docker build -f docker/nodejs-simple/Dockerfile \
  --build-arg APP_PATH=js-apps/proxy \
  --build-arg EXPOSE_PORT=8002 \
  --build-arg START_CMD="node src/index.mjs" \
  -t your-repo/proxy:latest .
```

### 参数说明

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `APP_PATH` | ✅ | - | 项目在 monorepo 中的路径 |
| `EXPOSE_PORT` | ❌ | 3000 | 容器暴露的端口 |
| `START_CMD` | ❌ | "node index.js" | 启动命令（被 docker-compose 覆盖） |

## 在 build.sh 中使用

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

SERVICE_NAME="proxy"
APP_PATH="js-apps/proxy"
PORT="8002"
START_CMD="node src/index.mjs"
VERSION="$(get_version)"

IMAGE="$ECR_REGISTRY/studio/$SERVICE_NAME"

# 使用 nodejs-simple Dockerfile
build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "docker/nodejs-simple/Dockerfile" \
  --build-arg APP_PATH="$APP_PATH" \
  --build-arg EXPOSE_PORT="$PORT" \
  --build-arg START_CMD="$START_CMD"
```

## Dockerfile 构建阶段

### 1. Base Stage
- 基础 Node.js 22 Alpine 镜像
- 启用 pnpm（通过 corepack）

### 2. Dependencies Stage
- 安装 gcompat（兼容性库）
- 复制 monorepo 配置文件
- 安装所有依赖
- **跳过构建步骤**
- 使用 `pnpm deploy --prod` 导出生产依赖和源码

### 3. Runtime Stage
- 创建非 root 用户 `appuser`
- 安装 wget（用于健康检查）
- 复制应用代码和依赖
- 设置启动命令

## 优化特性

### 1. 多阶段构建
分离构建和运行环境，最终镜像更小。

### 2. Layer 缓存
- 先复制 package.json 和 lock 文件
- 再复制源码
- 利用 Docker layer 缓存加速构建

### 3. 非 root 用户
使用 `appuser` 运行，增强安全性。

### 4. 生产优化
- `pnpm deploy --prod` 只安装生产依赖
- 移除 dev dependencies，减小镜像体积

## 镜像大小对比

典型的 proxy 应用：

| Dockerfile | 镜像大小 | 构建时间 |
|------------|----------|----------|
| nodejs/Dockerfile | ~200MB | 2-3 分钟 |
| nodejs-simple/Dockerfile | ~180MB | 1-2 分钟 |

## 最佳实践

### 1. package.json 配置

确保 package.json 中有正确的入口文件：

```json
{
  "name": "proxy",
  "main": "src/index.mjs",
  "type": "module",
  "dependencies": {
    "hono": "^4.10.3"
  }
}
```

### 2. 健康检查

在 docker-compose 中配置健康检查：

```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8002/"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### 3. 日志管理

配置日志轮转避免磁盘占满：

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

## 故障排查

### 构建失败：找不到模块

**问题**: `Error: Cannot find module 'xxx'`

**解决**:
1. 检查 package.json 中是否包含该依赖
2. 确保 pnpm-lock.yaml 是最新的
3. 在本地运行 `pnpm install` 更新 lock 文件

### 运行时错误：权限问题

**问题**: `EACCES: permission denied`

**解决**:
确保文件权限正确，Dockerfile 中使用 `--chown=appuser:nodejs`。

### 健康检查失败

**问题**: 容器启动后立即变为 unhealthy

**解决**:
1. 检查应用是否监听正确的端口
2. 增加 `start_period` 时间
3. 检查应用日志确认启动成功

## 示例项目

参考 `js-apps/proxy` 项目了解完整的配置示例。
