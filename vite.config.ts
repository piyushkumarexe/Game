import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig(({ command }) => ({
  base: command === 'serve' ? '/' : '/Game/',
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'apple-touch-icon.svg'],
      manifest: {
        name: 'Dustbound RV',
        short_name: 'Dustbound',
        description: 'A pocket-sized physics road trip through the wild backcountry.',
        theme_color: '#171a25',
        background_color: '#171a25',
        display: 'standalone',
        orientation: 'landscape',
        start_url: '.',
        icons: [
          { src: 'icon-192.svg', sizes: '192x192', type: 'image/svg+xml', purpose: 'any' },
          { src: 'icon-512.svg', sizes: '512x512', type: 'image/svg+xml', purpose: 'any maskable' }
        ]
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,webp,woff2}'],
        cleanupOutdatedCaches: true
      }
    })
  ],
  build: {
    target: 'es2022',
    sourcemap: true,
    chunkSizeWarningLimit: 1800
  },
  server: {
    host: '0.0.0.0',
    allowedHosts: true
  },
  preview: {
    host: '0.0.0.0',
    allowedHosts: true
  }
}));
