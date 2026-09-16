'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createEnvironment } = require('./support/fakeAppsScript');

function grid() {
  return [
    ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', 'Toby', "+1's", 'Total Attendance per run'],
    ['Fri, 3-Jan', 'Beach, "north"\nMeeting point', 'Soft Sand', 7.5, 7.2, 'x', '-', 1, 2],
  ];
}
function environment() {
  return createEnvironment({ grid: grid(), sheetName: '2026', sheetId: 26,
    extraSheets: [{ name: '2025', sheetId: 25, grid: grid() },
      { name: '_FCTC_Guests', sheetId: 90, grid: [['Private guest history']] }],
    properties: { SHARED_GUESTS_ENABLED: 'true' } });
}

test('export captures only allowlisted seasons as displayed cell strings under one lock', () => {
  const env = environment();
  const result = env.post({ action: 'exportAttendanceSnapshot' });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.apiVersion, 2);
  assert.deepEqual(result.seasons.map(s => s.year), [2025, 2026]);
  assert.deepEqual(result.seasons.map(s => s.seasonSheetId), [25, 26]);
  assert.equal(result.seasons[0].grid[1][1], 'Beach, "north"\nMeeting point');
  assert.equal(result.seasons[0].grid[1][4], '7.2');
  assert.ok(result.seasons.every(s => s.grid.every(row => row.every(value => typeof value === 'string'))));
  assert.match(result.snapshotRevision, /^[a-f0-9]{64}$/);
  assert.ok(Number.isFinite(Date.parse(result.capturedAt)));
  assert.ok(!JSON.stringify(result).includes('Private guest history'));
  assert.deepEqual(env.lockLog.map(entry => entry.kind), ['waitLock', 'releaseLock']);
  assert.equal(env.batches.length, 0);
  const configuration = fs.readFileSync(path.join(__dirname, '../../src/config/years.js'), 'utf8');
  const years = [...configuration.matchAll(/^\s+(\d{4}): '\/data\//gm)].map(match => Number(match[1])).sort();
  assert.deepEqual(result.seasons.map(s => s.year), years);
});

test('a pending write or lock refusal prevents an inconsistent export', () => {
  const env = environment();
  env.properties.FCTC_PENDING_OPERATION = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  assert.equal(env.post({ action: 'exportAttendanceSnapshot' }).error, 'busy');
  const locked = createEnvironment({ grid: grid(), lockHeld: true });
  assert.equal(locked.post({ action: 'exportAttendanceSnapshot' }).error, 'busy');
});

test('missing seasons and invalid authentication fail without exposing a partial snapshot', () => {
  const env = environment();
  env.allSheets.splice(env.allSheets.findIndex(s => s.name === '2025'), 1);
  const result = env.post({ action: 'exportAttendanceSnapshot' });
  assert.equal(result.error, 'snapshot_invalid', JSON.stringify(result));
  assert.equal(result.seasons, undefined);
  for (const secret of [undefined, 'wrong']) {
    assert.equal(env.raw(JSON.stringify({ action: 'exportAttendanceSnapshot', secret })).error, 'bad_secret');
  }
});

test('one snapshot revision covers historical edits and ignores capture time', () => {
  const env = environment();
  const before = env.post({ action: 'exportAttendanceSnapshot' });
  assert.equal(before.ok, true, JSON.stringify(before));
  assert.equal(env.post({ action: 'exportAttendanceSnapshot' }).snapshotRevision, before.snapshotRevision);
  env.spreadsheet.getSheetById(25).values[1][6] = 'x';
  const after = env.post({ action: 'exportAttendanceSnapshot' });
  assert.notEqual(after.snapshotRevision, before.snapshotRevision);
  assert.equal(after.seasons[0].grid[1][6], 'x');
});

// A write pause must not break the read-only dashboard snapshot.
test('exports remain available while guest writes are paused', () => {
  const env = environment();
  env.properties.SHARED_GUESTS_ENABLED = 'false';
  const result = env.post({ action: 'exportAttendanceSnapshot' });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.deepEqual(result.seasons.map(s => s.year), [2025, 2026]);
});
