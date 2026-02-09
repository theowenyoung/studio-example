import { pool } from './postgres'
import { getCached, setCache, deleteCached } from './redis'

export type Post = {
  id: number
  title: string
  body: string
  created_at?: Date
  updated_at?: Date
}

const CACHE_TTL = 300 // 5 分钟

// 获取所有 posts
export async function getAllPosts(): Promise<Post[]> {
  // 先尝试从 Redis 获取
  const cached = await getCached<Post[]>('posts:all')
  if (cached) {
    console.log('Cache hit: posts:all')
    return cached
  }

  // 从数据库查询
  const result = await pool.query(
    'SELECT * FROM posts ORDER BY created_at DESC'
  )

  const posts = result.rows

  // 存入缓存
  await setCache('posts:all', posts, CACHE_TTL)

  return posts
}

// 根据 ID 获取单个 post
export async function getPostById(id: number): Promise<Post | null> {
  // 先尝试从 Redis 获取
  const cached = await getCached<Post>(`posts:${id}`)
  if (cached) {
    console.log(`Cache hit: posts:${id}`)
    return cached
  }

  // 从数据库查询
  const result = await pool.query(
    'SELECT * FROM posts WHERE id = $1',
    [id]
  )

  if (result.rows.length === 0) {
    return null
  }

  const post = result.rows[0]

  // 存入缓存
  await setCache(`posts:${id}`, post, CACHE_TTL)

  return post
}

// 创建新 post
export async function createPost(title: string, body: string): Promise<Post> {
  const result = await pool.query(
    'INSERT INTO posts (title, body) VALUES ($1, $2) RETURNING *',
    [title, body]
  )

  const post = result.rows[0]

  // 清除列表缓存
  await deleteCached('posts:all')

  return post
}

// 更新 post
export async function updatePost(id: number, title: string, body: string): Promise<Post | null> {
  const result = await pool.query(
    'UPDATE posts SET title = $1, body = $2 WHERE id = $3 RETURNING *',
    [title, body, id]
  )

  if (result.rows.length === 0) {
    return null
  }

  const post = result.rows[0]

  // 清除相关缓存
  await deleteCached(`posts:${id}`)
  await deleteCached('posts:all')

  return post
}

// 删除 post
export async function deletePost(id: number): Promise<boolean> {
  const result = await pool.query(
    'DELETE FROM posts WHERE id = $1',
    [id]
  )

  // 清除相关缓存
  await deleteCached(`posts:${id}`)
  await deleteCached('posts:all')

  return result.rowCount !== null && result.rowCount > 0
}

