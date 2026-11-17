import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  allowedDevOrigins: [
    "127.0.0.1",
    "8328-iqn80diyzpfe36wh1ygrb-89472cc1.us5.manus.computer",
  ],
};

export default nextConfig;
