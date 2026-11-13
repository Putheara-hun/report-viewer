import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  plugins: [vue()],
  base: './',
  server: { port: 5175, host: 'localhost' },
  build: {
    chunkSizeWarningLimit: 2000,
    // the viewer answers on / and on /viewer.html (the address viewer.js uses)
    rollupOptions: {
      input: {
        index: fileURLToPath(new URL('./index.html', import.meta.url)),
        viewer: fileURLToPath(new URL('./viewer.html', import.meta.url)),
      },
    },
  },
});
