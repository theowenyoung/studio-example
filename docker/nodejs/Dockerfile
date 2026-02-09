# docker/nodejs/Dockerfile
# 用法示例：
# docker build -f docker/nodejs/Dockerfile \
#   --build-arg APP_PATH=js-apps/xxx \
#   --build-arg EXPOSE_PORT=3000 \
#   --build-arg START_CMD="node dist/index.js" \
#   -t your-repo/xxx:latest .

# ---------- Base ----------
FROM node:22-alpine AS base

# 启用 pnpm（用 corepack，版本可跟随 package.json 的 packageManager）
RUN corepack enable

# ---------- Builder ----------
FROM base AS builder
RUN apk add --no-cache gcompat
WORKDIR /repo

# 允许在构建时指定要打包的子项目目录，例如 js-apps/xxx
ARG APP_PATH
# 可选：构建脚本名（默认 "build"），如果你的子包脚本不是 build 可以改
ARG BUILD_SCRIPT=build

# 先拷贝 workspace 关键文件，尽量提升依赖安装缓存命中率
# （若仓库没有某些文件，可自行删除对应行）
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# 再拷贝所有源码（最省心；如需更强缓存控制，可改成分阶段拷贝）
COPY . .

# 安装依赖（会自动安装正确平台的可选依赖）
RUN pnpm -w install --frozen-lockfile

# 构建目标应用及其所有 workspace 依赖（按拓扑顺序）
# 注意：{path}... 表示包及其依赖，...{path} 表示包及其被依赖者
RUN pnpm -w --filter "{./${APP_PATH}}..." run ${BUILD_SCRIPT}

# 导出生产运行所需的独立产物（包含 node_modules、package.json、dist 等）
# 需要 pnpm v8.15+/v9（corepack 通常会给到较新版本）
RUN pnpm --filter="./${APP_PATH}" deploy --prod /out

# 提取 pnpm 版本供 runtime 阶段使用
RUN node -p "require('./package.json').packageManager.replace('pnpm@', '')" > /tmp/pnpm-version

# ---------- Runtime ----------
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# 启动命令（通过构建参数传入，必须在 FROM 之后立即声明）
ARG START_CMD="node dist/server/index.js"
ENV START_CMD=${START_CMD}

# 安装运行时依赖
RUN apk add --no-cache bash postgresql-client

# 从 builder 获取 pnpm 版本并安装
COPY --from=builder /tmp/pnpm-version /tmp/pnpm-version
RUN corepack enable && \
    corepack prepare pnpm@$(cat /tmp/pnpm-version) --activate && \
    rm /tmp/pnpm-version

# 从 builder 导入"已裁剪的"产物
COPY --from=builder /out/ /app/

# 复制 scripts 目录到根目录（供迁移脚本使用）
# package.json 中的迁移命令使用 ../../scripts，从 /app 算起即 /scripts
COPY --from=builder /repo/scripts /scripts

# 暴露端口
ARG EXPOSE_PORT=3000
EXPOSE ${EXPOSE_PORT}

# 启动命令（使用 shell 形式以展开环境变量）
CMD sh -c "$START_CMD"
