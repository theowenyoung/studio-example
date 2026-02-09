# ========================================
# Shared Dockerfile for Node.js SSG Projects
# Supports: Remix, Next.js, Vite
# ========================================

# Build stage
FROM node:22-alpine AS builder

WORKDIR /app

# Copy root workspace files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# Install pnpm
RUN corepack enable && corepack prepare pnpm@8.15.6 --activate

# Copy all workspace dependencies (js-packages)
COPY js-packages ./js-packages

# Accept build argument for which app to build
ARG APP_NAME
ARG BASE_PATH=/
ENV APP_NAME=${APP_NAME}
ENV BASE_PATH=${BASE_PATH}

# Copy the specific app
COPY js-apps/${APP_NAME} ./js-apps/${APP_NAME}

# Install dependencies (workspace aware, including dependencies' dependencies)
RUN pnpm install --frozen-lockfile --filter "./js-apps/${APP_NAME}..."

# Build workspace dependencies first (like @repo/ui)
RUN pnpm --filter "./js-packages/*" --if-present build

# Build the app
WORKDIR /app/js-apps/${APP_NAME}
RUN pnpm build

# ========================================
# Runtime stage - minimal nginx image
# ========================================
FROM nginx:alpine

ARG APP_NAME
ENV APP_NAME=${APP_NAME}

# Copy built files based on framework
# The build output detection happens at runtime based on what exists
COPY docker/nodejs-ssg/nginx.conf /etc/nginx/nginx.conf

# Copy all possible build outputs
COPY --from=builder /app/js-apps/${APP_NAME}/ /tmp/app-build/

# Copy the appropriate build output to nginx html directory
RUN if [ -d "/tmp/app-build/build/client" ] && [ "$(ls -A /tmp/app-build/build/client 2>/dev/null)" ]; then \
      echo "Found Remix build output"; \
      cp -r /tmp/app-build/build/client/* /usr/share/nginx/html/; \
    elif [ -d "/tmp/app-build/out" ] && [ "$(ls -A /tmp/app-build/out 2>/dev/null)" ]; then \
      echo "Found Next.js build output"; \
      cp -r /tmp/app-build/out/* /usr/share/nginx/html/; \
    elif [ -d "/tmp/app-build/dist" ] && [ "$(ls -A /tmp/app-build/dist 2>/dev/null)" ]; then \
      echo "Found Vite build output"; \
      cp -r /tmp/app-build/dist/* /usr/share/nginx/html/; \
    else \
      echo "ERROR: No build output found!"; \
      ls -la /tmp/app-build/; \
      exit 1; \
    fi && \
    rm -rf /tmp/app-build

WORKDIR /usr/share/nginx/html

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
