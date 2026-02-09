import { Pool } from 'pg'

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
})

// 优雅关闭连接池
export async function closeDatabase() {
  // 检查 pool 是否已经关闭或正在关闭
  if (!pool.ending && !pool.ended) {
    await pool.end()
  }
}
