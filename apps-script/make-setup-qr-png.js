'use strict';

/**
 * Render a setup QR as a PNG for the badged-image handoff flow.
 *
 * The HTML flavour (make-setup-qr.js) suits opening on the Mac; this one feeds
 * ios/Tools/badge-qr.swift, which stamps the tester's initial and name on the
 * image and verifies it still decodes. See the release runbook, section 10.
 *
 *   FCTC_SETUP_SECRET=... node make-setup-qr-png.js \
 *     --url https://script.google.com/macros/s/DEPLOYMENT/exec \
 *     --device "Aaron iPhone" --output /tmp/qr-aaron.png
 *
 * The PNG is written with node's built-in zlib; no dependencies.
 */

const fs = require('node:fs');
const zlib = require('node:zlib');
const { buildPayload } = require('./make-setup-qr.js');
const { encodeText } = require('./qr-encode.js');

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || argv[i + 1] === undefined) {
      throw new Error(`Unpaired argument: ${argv[i]}`);
    }
    args[argv[i].slice(2)] = argv[i + 1];
  }
  return args;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/** Grayscale 8-bit PNG: one filter byte (0) plus one byte per pixel per row. */
function renderPng(matrix, moduleSize, quietModules) {
  const size = (matrix.length + quietModules * 2) * moduleSize;
  const raw = Buffer.alloc((size + 1) * size, 0xff);
  for (let y = 0; y < size; y += 1) {
    raw[y * (size + 1)] = 0; // per-row filter: none
    const my = Math.floor(y / moduleSize) - quietModules;
    for (let x = 0; x < size; x += 1) {
      const mx = Math.floor(x / moduleSize) - quietModules;
      const dark = mx >= 0 && my >= 0 && mx < matrix.length
        && my < matrix.length && matrix[my][mx];
      if (dark) raw[y * (size + 1) + 1 + x] = 0;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 0;  // grayscale
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const payload = buildPayload({
    url: args.url,
    secret: process.env.FCTC_SETUP_SECRET || args.secret,
    device: args.device,
  });
  const qr = encodeText(payload);
  const out = args.output || 'setup-qr.png';
  fs.writeFileSync(out, renderPng(qr.matrix, 12, 4), { mode: 0o600 });
  console.log(`Wrote ${out} (QR version ${qr.version}, ${qr.size}x${qr.size} modules).`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`Could not create setup QR image: ${error.message}`);
    process.exit(1);
  }
}

module.exports = { renderPng };
