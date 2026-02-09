import { vitePlugin as remix } from "@remix-run/dev";
import { installGlobals } from "@remix-run/node";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

installGlobals();

// 从环境变量获取 base path（用于子路径部署）
// 例如: BASE_PATH=/blog 时，静态资源会从 /blog/assets/... 加载
const rawBasePath = process.env.BASE_PATH || "/";

// Vite base 需要尾部斜杠
const viteBase = rawBasePath === "/" ? "/" : rawBasePath.endsWith("/") ? rawBasePath : rawBasePath + "/";

// Remix basename 不要尾部斜杠
const remixBasename = rawBasePath === "/" ? "/" : rawBasePath.replace(/\/$/, "");

export default defineConfig({
  base: viteBase,
  plugins: [
    remix({
      // 移除 Vercel preset，使用标准构建
      ssr: false, // 禁用 SSR，生成纯静态站点
      basename: remixBasename, // Remix 路由不要尾部斜杠
    }),
    tsconfigPaths(),
  ],
  build: {
    outDir: "build/client", // 输出目录
  },
});
