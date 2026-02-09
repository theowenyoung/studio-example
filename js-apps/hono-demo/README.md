# Hono Demo - Vite Integration

这是一个使用 Hono + Vite 的工程化示例项目，展示了如何在 Hono 应用中实现前端资源的版本控制和缓存管理。

## 项目特点

- ✅ **开发环境零构建**: 一条命令启动,无需预构建
- ✅ **生产环境自动哈希**: 客户端资源自动添加哈希文件名
- ✅ **类型安全**: 完整的 TypeScript 支持
- ✅ **资源中间件**: 统一的资源路径管理
- ✅ **可扩展**: 轻松添加更多客户端脚本
- ✅ **数据库 Migrations**: 遵循最佳实践的数据库迁移系统
- ✅ **Redis 缓存**: 集成 Redis 进行数据缓存

## 快速开始

### 环境配置

1. 复制环境变量配置文件：
```bash
cp .env.example .env
```

2. 修改 `.env` 文件，配置数据库连接：
```env
DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres
REDIS_URL=redis://default:password@localhost:6379
```

### 开发环境

```bash
pnpm dev
```

访问 http://localhost:8001

- 修改服务端代码自动重启
- 修改客户端代码支持 HMR（如果需要编译）
- 静态资源直接服务，无需构建
- 应用启动时自动运行数据库 migrations

### 生产环境

```bash
# 1. 构建客户端和服务端
pnpm build

# 2. 启动服务
pnpm start
```

访问 http://localhost:3000

## 项目结构

```
hono-demo/
├── src/                    # 服务端代码
│   ├── index.tsx          # 应用入口
│   ├── middleware/
│   │   └── assets.ts      # 资源中间件
│   ├── components/
│   │   └── Layout.tsx     # 布局组件
│   └── pages/             # 页面组件
├── client/                 # 客户端代码（需要构建）
│   └── datastar.ts        # 客户端脚本
├── public/                 # 公共静态资源（开发环境使用）
│   └── static/js/
│       └── datastar.js    # 开发环境使用的脚本
├── dist/                   # 构建输出
│   ├── client/            # 客户端构建产物（带哈希）
│   │   ├── assets/
│   │   │   └── datastar-abc123.js
│   │   └── .vite/
│   │       └── manifest.json
│   └── server/            # 服务端构建产物
└── vite.config.ts         # Vite 配置
```

## 工作原理

### 开发环境

1. `pnpm dev` 启动 Vite + @hono/vite-dev-server
2. Hono 服务器在 Vite 内部运行
3. 资源中间件返回 `/static/js/datastar.js` 路径
4. Hono 直接服务 `public/static/js/` 目录下的文件
5. 无需构建，即时启动

### 生产环境

1. `pnpm build:client` 构建客户端资源
   - 输出到 `dist/client/assets/datastar-[hash].js`
   - 生成 `dist/client/.vite/manifest.json`
2. `pnpm build:server` 编译 TypeScript
3. `pnpm start` 启动生产服务器
4. 资源中间件从 manifest.json 读取带哈希的文件名
5. Hono 服务 `dist/client/` 目录

## 添加新的客户端脚本

### 1. 创建客户端文件

```typescript
// client/page-a.ts
console.log('Page A script loaded!')

export function initPageA() {
  // 你的逻辑
}
```

### 2. 更新 Vite 配置

```typescript
// vite.config.ts
export default defineConfig(({ mode }) => {
  if (mode === 'client') {
    return {
      build: {
        rollupOptions: {
          input: {
            datastar: './client/datastar.ts',
            'page-a': './client/page-a.ts',  // 添加入口
          },
        },
      },
    }
  }
  // ...
})
```

### 3. 在页面中使用

```tsx
// src/pages/top.tsx
export const Top = (props: { posts: Post[]; c: Context }) => {
  return (
    <Layout title={'Top'} c={props.c}>
      <main>
        <h2>Posts</h2>
        {/* ... */}
      </main>
      {/* 添加页面特定的脚本 */}
      <script type="module" src={props.c.var.asset('page-a.ts')}></script>
    </Layout>
  )
}
```

## 资源管理 API

在组件中通过 Context 访问 asset() 方法：

```tsx
// 在组件中
const asset = props.c.var.asset

// 开发环境返回: /static/js/datastar.js
// 生产环境返回: /assets/datastar-abc123.js
asset('datastar.ts')
```

## 数据库管理

本项目使用 [node-pg-migrate](https://salsita.github.io/node-pg-migrate/) 管理数据库 schema。详细文档请查看 [README-MIGRATIONS.md](./README-MIGRATIONS.md)。

### 常用命令

```bash
# 运行所有 pending migrations
pnpm migrate:up

# 回滚最后一个 migration
pnpm migrate:down

# 创建新的 migration
pnpm migrate:create add-users-table

# 测试数据库连接
pnpm test:db
```

### Migration 特性

- ✅ 成熟的第三方工具（node-pg-migrate）
- ✅ 支持 SQL 和 TypeScript/JavaScript
- ✅ 支持 up/down migrations（回滚）
- ✅ 事务支持，失败自动回滚
- ✅ 应用启动时自动运行
- ✅ Dry-run 模式预览
- ✅ CLI 工具完善

### 项目数据库结构

```
hono-demo/
├── .node-pg-migrate.config.js          # Migration 配置
├── migrations/                          # Migration 文件目录
│   ├── 1730000001_create-posts-table.sql
│   └── 1730000002_seed-posts.sql
└── src/db/
    ├── postgres.ts                      # 数据库连接池
    ├── redis.ts                         # Redis 连接和缓存
    └── posts.ts                         # Posts 数据操作
```

## 部署建议

1. **构建**: `pnpm build` 生成生产版本
2. **环境变量**: 设置 `NODE_ENV=production`
3. **静态资源**: `dist/client/` 可以部署到 CDN
4. **服务器**: 运行 `dist/server/index.js`

## 注意事项

- 开发环境使用 `public/static/js/` 的文件（无需构建）
- 生产环境使用 `client/` 构建后的文件（带哈希）
- 如果客户端脚本是纯 JS，可以直接放在 `public/` 目录
- 如果需要 TypeScript/模块打包，放在 `client/` 目录并添加到 Vite 配置

## 进一步优化

1. **CSS 处理**: 在 `client/` 中添加 CSS 文件，Vite 会自动提取和压缩
2. **代码分割**: 使用动态 import() 实现按需加载
3. **Tree-shaking**: Vite 自动移除未使用的代码
4. **压缩**: 生产构建自动压缩 JS 和 CSS
