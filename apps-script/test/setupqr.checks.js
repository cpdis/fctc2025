'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { buildPayload, renderHtml, writePrivateFile } = require('../make-setup-qr.js');
const { encodeText } = require('../qr-encode.js');

const TEST_SECRET = 'test-secret-not-real';

test('setup payload uses the scanner contract without changing values', () => {
  const payload = buildPayload({
    url: 'https://script.google.com/macros/s/example/exec',
    secret: TEST_SECRET,
    device: 'Aaron phone',
  });

  assert.deepEqual(JSON.parse(payload), {
    endpoint: 'https://script.google.com/macros/s/example/exec',
    secret: TEST_SECRET,
    deviceName: 'Aaron phone',
  });
});

test('payload construction rejects insecure and blank setup values', () => {
  assert.throws(
    () => buildPayload({ url: 'http://example.test/exec', secret: TEST_SECRET, device: 'Phone' }),
    /URL must use HTTPS/,
  );
  assert.throws(
    () => buildPayload({ url: ' ', secret: TEST_SECRET, device: 'Phone' }),
    /Missing URL/,
  );
  assert.throws(
    () => buildPayload({ url: 'https://example.test/exec', secret: ' ', device: 'Phone' }),
    /Missing secret/,
  );
  assert.throws(
    () => buildPayload({ url: 'https://example.test/exec', secret: TEST_SECRET, device: ' ' }),
    /Missing device name/,
  );
});

test('encoder chooses the smallest version and returns a square module matrix', () => {
  const qr = encodeText('A'.repeat(80));

  // Version 4-M holds 62 byte-mode characters. Version 5-M holds 84.
  assert.equal(qr.version, 5);
  assert.equal(qr.size, 37);
  assert.equal(qr.matrix.length, qr.size);
  assert.ok(qr.matrix.every((row) => row.length === qr.size));
});

test('encoder draws all three finder patterns', () => {
  const qr = encodeText('finder pattern check');

  assertFinder(qr.matrix, 0, 0);
  assertFinder(qr.matrix, qr.size - 7, 0);
  assertFinder(qr.matrix, 0, qr.size - 7);
});

test('different masks change data modules but not finder modules', () => {
  const zero = encodeText('mask application check', { mask: 0 });
  const one = encodeText('mask application check', { mask: 1 });

  assert.equal(zero.version, one.version);
  assert.notDeepEqual(zero.matrix, one.matrix);
  assertFinder(zero.matrix, 0, 0);
  assertFinder(one.matrix, 0, 0);
  assert.ok(zero.functionModules.some((row, y) => row.some((isFunction, x) => {
    return !isFunction && zero.matrix[y][x] !== one.matrix[y][x];
  })));
});

test('self-contained HTML embeds the exact payload and QR modules', () => {
  const payload = buildPayload({
    url: 'https://example.test/exec',
    secret: TEST_SECRET,
    device: 'Run phone',
  });
  const qr = encodeText(payload);
  const html = renderHtml(payload, qr);

  assert.match(html, /<!doctype html>/i);
  assert.ok(html.includes(JSON.stringify(payload)));
  assert.ok(html.includes(JSON.stringify(qr.matrix)));
  assert.doesNotMatch(html, /https:\/\/cdn|<script\s+src=/i);
});

test('private HTML writes repair permissions on an existing file', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'fctc-setup-qr-'));
  const output = path.join(directory, 'setup.html');
  try {
    fs.writeFileSync(output, 'old', { mode: 0o644 });
    fs.chmodSync(output, 0o644);

    writePrivateFile(output, 'new setup payload');

    assert.equal(fs.readFileSync(output, 'utf8'), 'new setup payload');
    assert.equal(fs.statSync(output).mode & 0o777, 0o600);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

function assertFinder(matrix, originX, originY) {
  for (let y = 0; y < 7; y += 1) {
    for (let x = 0; x < 7; x += 1) {
      const expected = x === 0 || x === 6 || y === 0 || y === 6
        || (x >= 2 && x <= 4 && y >= 2 && y <= 4);
      assert.equal(
        matrix[originY + y][originX + x],
        expected,
        `finder module ${originX + x},${originY + y}`,
      );
    }
  }
}

test('a production-length payload encodes above the old version-10 ceiling', () => {
  // Regression (2026-08-14 first real deploy): a real /exec URL plus a strong
  // secret is ~250 bytes, which overflowed the encoder's original 213-byte
  // version-10-M ceiling. The tables now extend to version 14.
  const payload = buildPayload({
    url: `https://script.google.com/macros/s/${'A'.repeat(71)}/exec`,
    secret: `fctc-${'a'.repeat(48)}`,
    device: 'Colin iPhone',
  });
  assert.ok(payload.length > 213, `expected an over-ceiling payload, got ${payload.length}`);

  const qr = encodeText(payload);
  assert.ok(qr.version >= 11, `expected version 11+, got ${qr.version}`);
  assert.ok(qr.version <= 14);
  assert.equal(qr.size, qr.version * 4 + 17);
  assert.equal(qr.matrix.length, qr.size);
  assertFinder(qr.matrix, 0, 0);
  assertFinder(qr.matrix, qr.size - 7, 0);
  assertFinder(qr.matrix, 0, qr.size - 7);
});
