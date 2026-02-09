# 构建说明

## 何时需要重建镜像

当修改了以下文件时，**必须**重新构建 Docker 镜像：

- ✅ `Dockerfile`
- ✅ `entrypoint.sh`
- ✅ `scripts/*.sh`（备份脚本）

**不需要**重建镜像的情况：
- ❌ `.env` 文件（环境变量在运行时加载）
- ❌ `docker-compose.yml`（配置在启动时读取）

## 如何重建镜像

### 方法 1: 完全重建（推荐，确保最新）

```bash
cd infra-apps/backup
docker compose build --no-cache backup
```

### 方法 2: 使用缓存快速重建

```bash
cd infra-apps/backup
docker compose build backup
```

### 方法 3: 使用快捷脚本

```bash
cd infra-apps/backup
./build.sh
```

## 验证构建

### 检查新的 entrypoint.sh

```bash
docker compose run --rm backup head -15 /entrypoint.sh
```

应该看到：
```bash
if [ $# -gt 0 ]; then
    echo "Executing command: $@"
    exec "$@"
fi
```

### 测试自动退出

```bash
# 这个命令应该立即退出（<1秒）
time docker compose run --rm backup echo "Test"
```

如果命令能在 1 秒内退出，说明构建成功！

## 常见问题

### Q1: 修改了脚本但没有生效？

**原因**: 没有重建镜像

**解决**:
```bash
docker compose build --no-cache backup
```

### Q2: docker compose run 一直挂起？

**原因**: 使用了旧镜像，entrypoint.sh 还是旧版本

**解决**:
```bash
# 1. 强制重建
docker compose build --no-cache backup

# 2. 验证 entrypoint
docker compose run --rm backup head -15 /entrypoint.sh

# 3. 测试
docker compose run --rm backup echo "Test"
```

### Q3: 如何确认使用的是新镜像？

```bash
# 查看镜像创建时间
docker images | grep backup

# 查看镜像详情
docker compose images backup
```

## mise 集成

如果使用 mise 任务，确保在首次运行或修改脚本后重建：

```bash
# 1. 重建镜像
cd infra-apps/backup
docker compose build --no-cache backup

# 2. 运行 mise 任务（现在会正常退出）
mise run dev:backup
```

## 自动化构建

你可以在 mise 任务中加入构建步骤：

```toml
[tasks."dev:backup"]
description = "Backup all databases"
run = """
cd infra-apps/backup
docker compose build backup
docker compose run --rm backup /usr/local/bin/backup-all.sh
"""
```

或者分离构建任务：

```toml
[tasks."dev:backup:build"]
description = "Build backup image"
run = "cd infra-apps/backup && docker compose build --no-cache backup"

[tasks."dev:backup"]
description = "Backup all databases"
run = "cd infra-apps/backup && docker compose run --rm backup /usr/local/bin/backup-all.sh"
```

## 生产环境

### 构建生产镜像

```bash
cd infra-apps/backup

# 构建并打标签
docker build -t backup:latest .
docker build -t backup:$(date +%Y%m%d) .

# 或使用 compose 构建
docker compose -f docker-compose.prod.yml build
```

### 推送到镜像仓库（可选）

```bash
# 标记镜像
docker tag backup:latest your-registry/backup:latest

# 推送
docker push your-registry/backup:latest

# 更新生产环境配置
# docker-compose.prod.yml 中使用 image: your-registry/backup:latest
```

## 故障排除

### 清理旧镜像

```bash
# 查看所有 backup 相关镜像
docker images | grep backup

# 删除旧镜像
docker rmi backup-backup:latest

# 清理悬空镜像
docker image prune -f
```

### 完全重置

```bash
# 1. 停止所有容器
docker compose down

# 2. 删除镜像
docker rmi backup-backup:latest

# 3. 清理缓存
docker builder prune -f

# 4. 重新构建
docker compose build --no-cache backup

# 5. 测试
docker compose run --rm backup echo "Test"
```
