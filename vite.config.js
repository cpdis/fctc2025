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
    // An allow-list, so vitest never descends into agent worktrees
    // (.claude/worktrees/) or the attendance app's own Node-tested areas
    // (apps-script/, ios/), which run under `node --test` and xcodebuild.
    //
    // scripts/ must stay listed: the milestone email's tests live there, and a
    // src-only pattern silently drops them, which is a green suite that proves
    // less than it did the day before.
    include: [
      'src/**/*.test.{js,jsx}',
      'scripts/**/*.test.{js,jsx}',
    ],
  },
})
