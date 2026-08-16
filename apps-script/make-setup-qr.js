#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { encodeText } = require('./qr-encode.js');

/** Custom URL scheme the iOS app claims. Keep in sync with `ios/project.yml`
 *  (CFBundleURLSchemes) and `SetupCodeParser.scheme`. */
const SETUP_SCHEME = 'fctc-attendance';

/**
 * Build the setup code as a custom-scheme link rather than raw JSON.
 *
 * Every generic scanner (the iOS Camera app, Live Text in Photos) lifts a URL out
 * of whatever it scans. A JSON payload therefore sent people to the Apps Script
 * endpoint in Safari, which answered `method_not_allowed` and configured nothing.
 * A link the app claims makes the obvious action the correct one: the Camera app
 * offers "Open in FCTC Attendance" and the fields reach the parser directly.
 */
function buildPayload({ url, secret, device }) {
  const endpoint = requiredText(url, 'URL');
  const parsed = new URL(endpoint);
  if (parsed.protocol !== 'https:') throw new Error('URL must use HTTPS.');
  const query = [
    ['endpoint', endpoint],
    ['secret', requiredText(secret, 'secret')],
    ['device', requiredText(device, 'device name')],
  ]
    // encodeURIComponent, not URLSearchParams: the latter writes a space as `+`,
    // which `URLComponents.queryItems` on iOS returns verbatim instead of decoding.
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join('&');
  return `${SETUP_SCHEME}://setup?${query}`;
}

function renderHtml(payload, qr) {
  const safePayload = scriptJSON(payload);
  const safeMatrix = scriptJSON(qr.matrix);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FCTC Attendance Setup</title>
  <style>
    :root { color-scheme: light; font-family: ui-rounded, "Avenir Next", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f2f5ef; color: #122115; }
    main { width: min(92vw, 680px); padding: 40px; text-align: center; background: white; border: 2px solid #0a6b33; border-radius: 28px; box-shadow: 0 18px 60px #16351f22; }
    h1 { margin: 0 0 8px; font-size: clamp(1.8rem, 5vw, 2.7rem); letter-spacing: -0.04em; }
    p { margin: 0 auto 24px; max-width: 34rem; color: #4c5c50; line-height: 1.5; }
    canvas { width: min(78vw, 480px); height: min(78vw, 480px); image-rendering: pixelated; background: white; border-radius: 12px; }
    details { margin-top: 24px; text-align: left; }
    pre { overflow-wrap: anywhere; white-space: pre-wrap; padding: 14px; border-radius: 12px; background: #f2f5ef; font: 0.78rem ui-monospace, monospace; }
  </style>
</head>
<body>
  <main>
    <h1>FCTC Attendance</h1>
    <p>Install <strong>FCTC Attendance</strong> from TestFlight first. Then point the iPhone <strong>Camera</strong> at this code and tap the banner that appears. The app asks you to confirm before it connects.</p>
    <p>Keep this file private because the code contains the shared secret.</p>
    <canvas id="qr" aria-label="FCTC Attendance setup QR code"></canvas>
    <details><summary>Show payload</summary><pre id="payload"></pre></details>
  </main>
  <script>
    const payload = ${safePayload};
    const matrix = ${safeMatrix};
    const quiet = 4;
    const moduleSize = 10;
    const canvas = document.querySelector('#qr');
    const side = matrix.length + quiet * 2;
    canvas.width = side * moduleSize;
    canvas.height = side * moduleSize;
    const context = canvas.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = '#08130b';
    matrix.forEach((row, y) => row.forEach((dark, x) => {
      if (dark) context.fillRect((x + quiet) * moduleSize, (y + quiet) * moduleSize, moduleSize, moduleSize);
    }));
    document.querySelector('#payload').textContent = payload;
  </script>
</body>
</html>
`;
}

function main(argv = process.argv.slice(2), env = process.env) {
  const args = parseArguments(argv);
  const payload = buildPayload({
    url: args.url || env.FCTC_SETUP_URL,
    secret: args.secret || env.FCTC_SETUP_SECRET,
    device: args.device || env.FCTC_SETUP_DEVICE,
  });
  const qr = encodeText(payload);
  const output = path.resolve(args.output || env.FCTC_SETUP_QR_OUTPUT || 'setup-qr.html');
  writePrivateFile(output, renderHtml(payload, qr));
  process.stdout.write(`${payload}\n`);
  process.stderr.write(`Wrote ${output} (QR version ${qr.version}, mask ${qr.mask}).\n`);
  return output;
}

function writePrivateFile(output, contents) {
  // Apply the mode to the open descriptor before writing. Node's `mode` option
  // only affects new files, so a plain overwrite could keep unsafe old bits.
  const descriptor = fs.openSync(output, 'w', 0o600);
  try {
    fs.fchmodSync(descriptor, 0o600);
    fs.writeFileSync(descriptor, contents, 'utf8');
  } finally {
    fs.closeSync(descriptor);
  }
}

function parseArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith('--')) throw new Error(`Unknown argument: ${argument}`);
    const equals = argument.indexOf('=');
    const name = argument.slice(2, equals === -1 ? undefined : equals);
    if (!['url', 'secret', 'device', 'output'].includes(name)) {
      throw new Error(`Unknown option: --${name}`);
    }
    const value = equals === -1 ? argv[++index] : argument.slice(equals + 1);
    if (value === undefined || value.startsWith('--')) throw new Error(`--${name} needs a value.`);
    result[name] = value;
  }
  return result;
}

function requiredText(value, label) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`Missing ${label}.`);
  return value.trim();
}

function scriptJSON(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`Could not create setup QR: ${error.message}\n`);
    process.stderr.write('Use --url, --secret, --device, and optional --output.\n');
    process.exitCode = 1;
  }
}

module.exports = {
  SETUP_SCHEME,
  buildPayload,
  main,
  parseArguments,
  renderHtml,
  writePrivateFile,
};
