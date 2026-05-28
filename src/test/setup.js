import '@testing-library/jest-dom'

// jsdom does not implement CSS.supports(). react-activity-calendar calls it to
// validate theme colors, so without this its render-tests blow up under jsdom.
// A permissive stub (everything "supported") is enough for rendering tests; we
// assert on color values directly elsewhere, not on browser CSS validation.
if (typeof globalThis.CSS === 'undefined') {
  globalThis.CSS = {}
}
if (typeof globalThis.CSS.supports !== 'function') {
  globalThis.CSS.supports = () => true
}

// jsdom also lacks window.matchMedia, which react-activity-calendar uses to read
// the OS color scheme. Stub it to "light" so its render-tests run.
if (typeof window !== 'undefined' && typeof window.matchMedia !== 'function') {
  window.matchMedia = (query) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: () => {},
    removeEventListener: () => {},
    addListener: () => {},
    removeListener: () => {},
    dispatchEvent: () => false,
  })
}
