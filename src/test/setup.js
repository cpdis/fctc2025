import '@testing-library/jest-dom'

// jsdom lacks ResizeObserver, which chartKit's useWidth uses to size the charts
// to their container. A no-op stub lets the chart tests mount; they render at
// the fallback width and assert on the marks, not on resize-driven sizing.
if (typeof globalThis.ResizeObserver === 'undefined') {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
}
