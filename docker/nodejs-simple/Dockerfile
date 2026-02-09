# docker/nodejs-simple/Dockerfile
# 用于不需要构建步骤的纯 Node.js 应用（如直接运行 .mjs/.js 文件）
#
# 用法示例：
# docker build -f docker/nodejs-simple/Dockerfile \
#   --build-arg APP_PATH=js-apps/proxy \
#   --build-arg EXPOSE_PORT=8002 \
#   --build-arg START_CMD="node src/index.mjs" \
#   -t your-repo/proxy:latest .

# ---------- Base ----------
FROM node:22-alpine AS base

# 启用 pnpm（用 corepack，版本可跟随 package.json 的 packageManager）
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"
RUN corepack enable

# ---------- Dependencies ----------
FROM base AS deps
RUN apk add --no-cache gcompat
WORKDIR /repo

# 允许在构建时指定要打包的子项目目录，例如 js-apps/proxy
ARG APP_PATH

# 先拷贝 workspace 关键文件，尽量提升依赖安装缓存命中率
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# 再拷贝所有源码
COPY . .

# 安装依赖（会自动安装正确平台的可选依赖）
RUN pnpm -w install --frozen-lockfile

# 导出生产运行所需的独立产物（包含 node_modules、package.json、源码等）
# 注意：这里不执行构建步骤，直接导出源码和依赖
RUN pnpm --filter="./${APP_PATH}" deploy --prod /out

# ---------- Runtime ----------
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# 启用 pnpm（用于运行脚本等任务）
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH="${PNPM_HOME}:${PATH}"
RUN corepack enable

# 安装 wget（用于健康检查）
RUN apk add --no-cache wget

# 非 root 运行
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 appuser

# 从 deps 导入"已裁剪的"产物
COPY --from=deps --chown=appuser:nodejs /out/ /app/

# 暴露端口（生产环境统一使用 3000）
ARG EXPOSE_PORT=3000
EXPOSE ${EXPOSE_PORT}

USER appuser

# 默认启动命令（会被 docker-compose.yml 的 command 覆盖）
# 对于简单应用，通常是 node index.js 或 node src/index.mjs
CMD ["node", "src/index.mjs"]
