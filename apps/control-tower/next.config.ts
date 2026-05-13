import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  output: "standalone",
  // Disable x-powered-by header for security
  poweredByHeader: false,
  // The Control Tower package uses the monorepo workspace lockfile. Pin
  // Turbopack to the repo root so it can resolve Next.js from workspace deps.
  turbopack: {
    root: path.resolve(__dirname, "../.."),
  },
};

export default nextConfig;
