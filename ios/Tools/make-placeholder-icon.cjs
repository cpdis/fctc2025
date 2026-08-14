#!/usr/bin/env node

// Generate the flat release placeholder without an image dependency.

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const size = 1024;
const accent = [0x0a, 0x6b, 0x33];
const destination = path.join(
  __dirname,
  '..',
  'FCTCAttendance',
  'Assets.xcassets',
  'AppIcon.appiconset',
  'icon-1024.png',
);

const crcTable = Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit += 1) {
    crc = (crc & 1) === 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return crc >>> 0;
});

function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(name, data) {
  const type = Buffer.from(name, 'ascii');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([type, data])));
  return Buffer.concat([length, type, data, checksum]);
}

const header = Buffer.alloc(13);
header.writeUInt32BE(size, 0);
header.writeUInt32BE(size, 4);
header[8] = 8; // Eight bits per channel.
header[9] = 2; // RGB with no App Store-invalid alpha channel.

const scanlines = Buffer.alloc((size * 3 + 1) * size);
for (let y = 0; y < size; y += 1) {
  const rowStart = y * (size * 3 + 1);
  scanlines[rowStart] = 0;
  for (let x = 0; x < size; x += 1) {
    const pixelStart = rowStart + 1 + x * 3;
    scanlines.set(accent, pixelStart);
  }
}

const png = Buffer.concat([
  Buffer.from('89504e470d0a1a0a', 'hex'),
  chunk('IHDR', header),
  chunk('IDAT', zlib.deflateSync(scanlines, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

fs.writeFileSync(destination, png, { mode: 0o644 });
console.log(destination);
