import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Local dev: `npm run dev` proxies /api to a running API (default the Sydney endpoint).
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': { target: process.env.API_URL ?? 'https://syd.mimidog.click', changeOrigin: true },
    },
  },
});
