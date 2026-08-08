import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  build: {
    // matrix-js-sdk includes the complete sync, crypto and MatrixRTC clients.
    // Keep the warning threshold aligned with that intentional vendor payload;
    // the Rust crypto binary is emitted as a separate WASM asset.
    chunkSizeWarningLimit: 1200,
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
});
