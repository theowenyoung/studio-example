import { createMiddleware } from 'hono/factory'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

type Manifest = Record<string, { file: string }>

let manifest: Manifest | undefined

// 仅在生产环境加载 manifest
if (process.env.NODE_ENV === 'production') {
  try {
    const manifestPath = resolve(process.cwd(), 'dist/client/.vite/manifest.json')
    manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'))
  } catch (e) {
    console.warn('⚠️  Manifest not found')
  }
}

export const assetsMiddleware = createMiddleware(async (c, next) => {
  const isDev = process.env.NODE_ENV === 'development'

  c.set('clientAsset', (filename: string) => {
    // 如果没有扩展名，默认添加 .ts
    const fullFilename = filename.includes('.') ? filename : `${filename}.ts`

    if (isDev) {
      // 开发环境：通过 Vite 处理（用于需要编译的 TS 文件）
      return `/src/client/${fullFilename}`
    }

    // 生产环境：从 manifest 获取构建后的路径
    const entry = manifest?.[`src/client/${fullFilename}`]
    return entry ? `/${entry.file}` : `/assets/${fullFilename}`
  })

  await next()
})

declare module 'hono' {
  interface ContextVariableMap {
    clientAsset: (name: string) => string
  }
}
