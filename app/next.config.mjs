/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // Emit a self-contained server bundle in .next/standalone.
  // The Docker runtime stage copies only that, which keeps the final
  // image small and free of build tooling.
  output: 'standalone',
};

export default nextConfig;
