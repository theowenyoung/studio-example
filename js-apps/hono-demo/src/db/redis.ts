import { createClient } from 'redis'

console.log("process.env.REDIS_URL", process.env.REDIS_URL)
// 创建 Redis 客户端
export const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379',
  socket: {
    reconnectStrategy: (retries) => {
      if (retries > 10) {
        return new Error('Redis connection failed after 10 retries')
      }
      return retries * 100
    }
  }
})

// 错误处理
redisClient.on('error', (err) => console.error('Redis Client Error', err))
redisClient.on('connect', () => console.log('Redis Client Connected'))
redisClient.on('ready', () => console.log('Redis Client Ready'))

// 连接 Redis
export async function connectRedis() {
  if (!redisClient.isOpen) {
    await redisClient.connect()
  }
  return redisClient
}

// 关闭 Redis 连接
export async function closeRedis() {
  if (redisClient.isOpen) {
    await redisClient.quit()
  }
}

// 缓存辅助函数
export async function getCached<T>(key: string): Promise<T | null> {
  const cached = await redisClient.get(key)
  if (cached) {
    return JSON.parse(cached) as T
  }
  return null
}

export async function setCache(key: string, value: any, ttl: number = 300): Promise<void> {
  await redisClient.setEx(key, ttl, JSON.stringify(value))
}

export async function deleteCached(pattern: string): Promise<void> {
  const keys = await redisClient.keys(pattern)
  if (keys.length > 0) {
    await redisClient.del(keys)
  }
}
