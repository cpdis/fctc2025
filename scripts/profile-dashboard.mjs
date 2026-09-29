// Profile the dashboard as a mid-range phone sees it: headless Chrome at a
// 390 pt viewport with 4x CPU throttling (Lighthouse's mobile setting),
// talking to Chrome over the DevTools protocol with Node's own WebSocket (no
// dependencies). It reports:
//
//   load          long tasks, and frame gaps over the first 8 s (the Wall's
//                 print-in curtain plays in the first ~1.5 s)
//   interactions  The Wall's sort and "Find yourself", timed through two
//                 animation frames, so style, layout and paint count
//
// Usage (serve a production build first: npm run build && npx vite preview):
//   node scripts/profile-dashboard.mjs http://localhost:4173/dashboard
//   node scripts/profile-dashboard.mjs 'http://localhost:4173/dashboard?year=all'
//
// CHROME overrides the browser path; PORT the DevTools port (default 9333).
import { spawn } from 'node:child_process'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const url = process.argv[2]
if (!url) {
  console.error('usage: node scripts/profile-dashboard.mjs <dashboard url>')
  process.exit(2)
}
const chromePath = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const port = Number(process.env.PORT ?? 9333)
const chrome = spawn(chromePath, [
  '--headless=new',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'fctc-profile-'))}`,
  '--no-first-run',
  'about:blank',
], { stdio: 'ignore' })

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// Wait for DevTools to list the blank page, then connect to it.
let targets
for (let attempt = 0; attempt < 50 && !targets; attempt++) {
  try {
    targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
  } catch {
    await sleep(200)
  }
}
const socket = new WebSocket(targets.find((target) => target.type === 'page').webSocketDebuggerUrl)
await new Promise((resolve) => socket.addEventListener('open', resolve))

// One pending promise per protocol call, resolved by its reply's id.
let nextId = 0
const pending = new Map()
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data)
  pending.get(message.id)?.(message)
  pending.delete(message.id)
})
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++nextId
    pending.set(id, resolve)
    socket.send(JSON.stringify({ id, method, params }))
  })
const evaluate = async (expression) => {
  const { result } = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails))
  return result.result.value
}

await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 3, mobile: true })
await send('Emulation.setCPUThrottlingRate', { rate: 4 })
// From the first script on: every long task, and every frame's gap to the last.
await send('Page.addScriptToEvaluateOnNewDocument', {
  source: `
    window.__long = []; window.__frames = [];
    new PerformanceObserver((list) => window.__long.push(...list.getEntries().map((e) => [Math.round(e.startTime), Math.round(e.duration)])))
      .observe({ type: 'longtask', buffered: true });
    let last = performance.now();
    const tick = (t) => { window.__frames.push([Math.round(t), Math.round(t - last)]); last = t; if (t < 8000) requestAnimationFrame(tick) };
    requestAnimationFrame(tick);
  `,
})
await send('Page.navigate', { url })
await sleep(9000)

const load = await evaluate(`(() => {
  const frames = window.__frames.filter(([t]) => t > 300);
  return {
    domNodes: document.querySelectorAll('*').length,
    wallCells: document.querySelectorAll('.wall rect.cell').length,
    longTasks: window.__long.map(([start, ms]) => ms + ' ms at ' + start),
    framesOver50ms: frames.filter(([, gap]) => gap > 50).length,
    worstFrameMs: Math.max(...frames.map(([, gap]) => gap)),
  };
})()`)

const interactions = await evaluate(`(async () => {
  const twoFrames = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const setValue = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set;
  const [find, sort] = document.querySelectorAll('.wall-tools select');
  const time = async (select, value) => {
    const start = performance.now();
    setValue.call(select, value);
    select.dispatchEvent(new Event('change', { bubbles: true }));
    await twoFrames();
    return Math.round(performance.now() - start);
  };
  const sortMs = [];
  for (const value of ['streak', 'name', 'runs', 'streak', 'name', 'runs']) sortMs.push(await time(sort, value));
  const names = [...find.options].map((o) => o.value).filter(Boolean);
  const findMs = [];
  for (const value of [names[2], names[5], '']) findMs.push(await time(find, value));
  return { sortMs, findMs };
})()`)

console.log(JSON.stringify({ url, load, interactions }, null, 2))
socket.close()
chrome.kill()
process.exit(0)
