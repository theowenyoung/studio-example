# Static Site Dockerfile

用于打包已经构建好的静态站点的 Dockerfile。

## 用途

适用于外部项目的静态站点部署，例如：
- Zola 博客
- Hugo 站点
- Jekyll 博客
- 或任何预先构建好的静态 HTML/CSS/JS 文件

## 使用方式

```bash
docker build \
  -f docker/static-site/Dockerfile \
  --build-context static=/path/to/static/files \
  -t my-static-site .
```

## 特性

- 基于 nginx:alpine（轻量级）
- 复用 `docker/nodejs-ssg/nginx.conf` 配置
- 监听端口 3000
- 包含 gzip 压缩、静态资源缓存、安全头等优化

## 与 nodejs-ssg 的区别

- **nodejs-ssg**: 从源码构建（pnpm + workspace）
- **static-site**: 直接使用已构建的静态文件

两者共享相同的 nginx 配置和运行时行为。
