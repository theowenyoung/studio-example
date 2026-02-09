import { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export", // 启用静态导出
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
  // 静态导出配置
  trailingSlash: true,
  images: {
    unoptimized: true, // 静态导出时必须禁用图片优化
  },
};

export default nextConfig;
