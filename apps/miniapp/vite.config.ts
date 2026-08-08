import { defineConfig } from "vite";

export default defineConfig({
  base: "/miniapp/",
  server: {
    port: 4173,
    proxy: {
      "/miniapp-api": {
        target: "http://127.0.0.1:8090",
        rewrite: (path) => path.replace(/^\/miniapp-api/, ""),
      },
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
