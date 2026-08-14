import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.js',
    css: false,
    // Only the dashboard's own suite: never descend into agent worktrees
    // (.claude/worktrees/) or the attendance app's Node-tested areas.
    include: ['src/**/*.test.{js,jsx}'],
  },
})
