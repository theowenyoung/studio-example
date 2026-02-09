import 'dotenv/config' // 在最顶部导入
import { Hono } from 'hono'
import { Page } from './pages/page'
import { Top } from './pages/top'
import { PostsManager } from './pages/posts-manager'
import { serveStatic } from '@hono/node-server/serve-static'
import { assetsMiddleware } from './middleware/assets'
import { closeDatabase } from './db/postgres'
import { connectRedis, closeRedis } from './db/redis'
import {
  getAllPosts,
  getPostById,
  createPost,
  updatePost,
  deletePost
} from './db/posts'

// 导出 Post 类型供其他模块使用
export type { Post } from './db/posts'

const app = new Hono()

app.use('*', assetsMiddleware)

// 页面路由
app.get('/', async (c) => {
  const posts = await getAllPosts()
  return c.html(<PostsManager posts={posts} c={c} />)
})

app.get('/posts', async (c) => {
  const posts = await getAllPosts()
  return c.html(<Top posts={posts} c={c} />)
})

app.get('/post/:id{[0-9]+}', async (c) => {
  const id = parseInt(c.req.param('id'))
  const post = await getPostById(id)
  if (!post) return c.notFound()
  return c.html(<Page post={post} c={c} />)
})

// API 路由 - 用于 Datastar 交互
app.get('/api/posts', async (c) => {
  try {
    const posts = await getAllPosts()
    return c.json(posts)
  } catch (error) {
    console.error('Error fetching posts:', error)
    return c.json({ error: 'Failed to fetch posts' }, 500)
  }
})

app.get('/api/posts/:id{[0-9]+}', async (c) => {
  try {
    const id = parseInt(c.req.param('id'))
    const post = await getPostById(id)
    if (!post) return c.json({ error: 'Post not found' }, 404)
    return c.json(post)
  } catch (error) {
    console.error('Error fetching post:', error)
    return c.json({ error: 'Failed to fetch post' }, 500)
  }
})

app.post('/api/posts/:id{[0-9]+}', async (c) => {
  try {
    const id = parseInt(c.req.param('id'))
    const body = await c.req.parseBody()

    // 支持 _method 字段用于模拟 PUT/DELETE
    const method = body._method as string

    if (method === 'PUT') {
      return handleUpdate(c, id, body)
    } else if (method === 'DELETE') {
      return handleDelete(c, id)
    }

    return c.json({ error: 'Invalid method' }, 400)
  } catch (error) {
    console.error('Error processing post:', error)
    return c.json({ error: 'Failed to process post' }, 500)
  }
})

app.post('/api/posts', async (c) => {
  try {
    const body = await c.req.parseBody()

    const title = body.title as string
    const postBody = body.body as string

    if (!title || !postBody) {
      return c.json({ error: 'Title and body are required' }, 400)
    }

    const post = await createPost(title, postBody)

    // 重定向回首页以刷新列表
    return c.redirect('/')
  } catch (error) {
    console.error('Error creating post:', error)
    return c.json({ error: 'Failed to create post' }, 500)
  }
})

// 辅助函数处理更新
async function handleUpdate(c: any, id: number, body: any) {
  const title = body.title as string
  const postBody = body.body as string

  if (!title || !postBody) {
    return c.json({ error: 'Title and body are required' }, 400)
  }

  const post = await updatePost(id, title, postBody)
  if (!post) return c.json({ error: 'Post not found' }, 404)

  return c.redirect('/')
}

// 辅助函数处理删除
async function handleDelete(c: any, id: number) {
  const success = await deletePost(id)
  if (!success) return c.json({ error: 'Post not found' }, 404)

  return c.redirect('/')
}

app.put('/api/posts/:id{[0-9]+}', async (c) => {
  try {
    const id = parseInt(c.req.param('id'))
    const body = await c.req.parseBody()
    const title = body.title as string
    const postBody = body.body as string

    if (!title || !postBody) {
      return c.json({ error: 'Title and body are required' }, 400)
    }

    const post = await updatePost(id, title, postBody)
    if (!post) return c.json({ error: 'Post not found' }, 404)

    // 重定向回首页以刷新列表
    return c.redirect('/')
  } catch (error) {
    console.error('Error updating post:', error)
    return c.json({ error: 'Failed to update post' }, 500)
  }
})

app.delete('/api/posts/:id{[0-9]+}', async (c) => {
  try {
    const id = parseInt(c.req.param('id'))
    const success = await deletePost(id)
    if (!success) return c.json({ error: 'Post not found' }, 404)

    // 重定向回首页以刷新列表
    return c.redirect('/')
  } catch (error) {
    console.error('Error deleting post:', error)
    return c.json({ error: 'Failed to delete post' }, 500)
  }
})

// 静态文件服务（放在路由之后，作为兜底）
// 优先级：业务路由 > 静态文件
const isDev = process.env.NODE_ENV !== 'production'

// 静态文件服务
// Vite 会自动把 public/ 复制到 dist/client/
app.use('/static/*', serveStatic({ root: isDev ? './public' : './dist/client' }))

// 在生产环境中，提供 Vite 生成的 assets
if (!isDev) {
  app.use('/assets/*', serveStatic({ root: './dist/client' }))
}

// 导出 app 供 Vite dev server 使用
export default app

// 初始化函数
async function initialize() {
  try {

    console.log('Connecting to Redis...')
    await connectRedis()
    console.log('Initialization complete!')
  } catch (error) {
    console.error('Initialization failed:', error)
    throw error
  }
}

// 优雅关闭
let isShuttingDown = false
async function shutdown() {
  // 防止重复执行
  if (isShuttingDown) {
    return
  }
  isShuttingDown = true

  console.log('Shutting down...')
  try {
    await closeDatabase()
    await closeRedis()
    console.log('Shutdown complete')
  } catch (error) {
    console.error('Error during shutdown:', error)
  } finally {
    process.exit(0)
  }
}

process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
console.log("process.env.NODE_ENV", process.env.NODE_ENV)

// 仅在非 Vite 环境下启动服务器（生产环境）
if (process.env.NODE_ENV === 'production') {
  const { serve } = await import('@hono/node-server')

  // 先初始化数据库
  await initialize()

  // 生产环境默认使用 3000，可通过 PORT 环境变量覆盖
  const port = process.env.PORT ? parseInt(process.env.PORT) : 3000
  serve({
    fetch: app.fetch,
    port
  }, (info) => {
    console.log(`Server is running on http://localhost:${info.port}`)
  })
} else {
  // 开发环境也需要初始化
  await initialize()
  // 打印开发环境域名
  console.log("Caddy", 'https://hono.local.owenyoung.com')
}

