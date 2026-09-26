import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 5173,
    // the sandbox preview is served from an arbitrary *.e2b.app host
    allowedHosts: true,
    proxy: {
      '/ws': { target: 'ws://127.0.0.1:8080', ws: true },
      '/health': { target: 'http://127.0.0.1:8080' },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'es2020',
    sourcemap: false,
    chunkSizeWarningLimit: 1400,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/three')) return 'three';
        },
      },
    },
  },
});
