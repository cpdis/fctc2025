'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createEnvironment } = require('./support/fakeAppsScript');
const { environment, setup, guest, attendance, mutation } = require('./guest-api.checks');

// Count top-level service reads only. The fake implements getFormulas through
// getValues internally, whereas Apps Script performs a single formula read.
function observeReads(env) {
  const reads = [];
  for (const sheet of env.allSheets) {
    const original = sheet.getRange;
    sheet.getRange = function (...args) {
      const range = original.apply(this, args);
      let nested = false;
      for (const method of ['getValues', 'getFormulas']) {
        const read = range[method];
        range[method] = function () {
          const previous = nested;
          if (!nested) reads.push({ sheet: sheet.name, method, row: this.row, col: this.col,
            rows: this.numRows, cols: this.numCols });
          nested = true;
          try { return read.call(this); } finally { nested = previous; }
        };
      }
      return range;
    };
  }
  return reads;
}

function populatedLedger(env, count = 1500) {
  const ledger = env.allSheets.find(s => s.name === '_FCTC_Operations');
  ledger.ensure_(ledger.getLastRow(), 128);
  let selected;
  for (let i = 0; i < count; i++) {
    const operationId = (0x90000000 + i).toString(16) + '-1234-4123-8123-123456789012';
    const operation = { operationId, requestDigest: 'a'.repeat(64), status: 'completed',
      response: { ok: true, marker: i }, plannedRequests: ['x'.repeat(12000)] };
    const text = JSON.stringify(operation), chunks = text.match(/.{1,6000}/g);
    const row = [operationId, operation.status, chunks.length, ...chunks];
    while (row.length < 128) row.push('');
    ledger.values.push(row);
    if (i === count - 1) selected = operation;
  }
  return { ledger, selected };
}

test('state reads only the operation header from a populated ledger', () => {
  const env = environment(); setup(env); populatedLedger(env);
  const reads = observeReads(env);
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).ok, true);
  const ledgerReads = reads.filter(r => r.sheet === '_FCTC_Operations');
  assert.equal(ledgerReads.length, 1);
  assert.ok(ledgerReads.every(r => r.row === 1 && r.rows === 1 && r.cols <= 3), JSON.stringify(ledgerReads));
});

test('receipt lookup reads the ID column and only its matching payload row', () => {
  const env = environment(); setup(env);
  const { selected } = populatedLedger(env), reads = observeReads(env);
  assert.deepEqual(env.post({ action: 'getOperationStatus', operationId: selected.operationId }).operation.response, selected.response);
  const ledgerReads = reads.filter(r => r.sheet === '_FCTC_Operations');
  assert.equal(ledgerReads.length, 2);
  assert.ok(ledgerReads.some(r => r.col === 1 && r.cols === 1 && r.rows > 1000));
  assert.ok(ledgerReads.filter(r => r.cols > 1).every(r => r.rows === 1 && r.cols <= 128));
  reads.length = 0;
  assert.equal(env.post({ action: 'getOperationStatus', operationId: 'ffffffff-1234-4123-8123-123456789012' }).operation, null);
  assert.ok(reads.every(r => r.col === 1 && r.cols === 1), JSON.stringify(reads));
});

test('mutation scans IDs twice without transferring historical receipt payloads', () => {
  const env = environment(); setup(env);
  const { ledger } = populatedLedger(env), reads = observeReads(env);
  assert.equal(guest(env, 'New guest').displayName, 'New guest');
  const ledgerReads = reads.filter(r => r.sheet === '_FCTC_Operations');
  assert.ok(ledgerReads.filter(r => r.cols > 1).every(r => r.rows === 1), JSON.stringify(ledgerReads));
  assert.ok(ledgerReads.reduce((sum, r) => sum + r.rows * r.cols, 0) <= 2 * ledger.getLastRow() + 130);
});

test('narrow receipt lookup preserves duplicate and row-integrity rejection', () => {
  for (const damage of ['duplicate', 'operationId', 'status', 'zeroChunks', 'tooManyChunks']) {
    const env = environment(), request = setup(env);
    const ledger = env.allSheets.find(s => s.name === '_FCTC_Operations');
    const row = ledger.values[1];
    if (damage === 'duplicate') ledger.values.push(row.slice());
    else if (damage === 'operationId') {
      const record = JSON.parse(row.slice(3, 3 + row[2]).join(''));
      record.operationId = 'ffffffff-1234-4123-8123-123456789012';
      row[2] = 1; row[3] = JSON.stringify(record);
    } else if (damage === 'status') row[1] = 'pending';
    else row[2] = damage === 'zeroChunks' ? 0 : 121;
    assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).conflict.reason, 'invalid_operation', damage);
  }
});

test('an empty ledger stays readable and its first mutation appends after the header', () => {
  const env = environment(), request = setup(env);
  const ledger = env.allSheets.find(s => s.name === '_FCTC_Operations');
  ledger.values.splice(1);
  assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).operation, null);
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).ok, true);
  guest(env);
  assert.equal(ledger.values.length, 2);
  assert.equal(ledger.values[0][0], 'FCTC_V2');
});

test('the operations header and existing capacity still fail closed before mutation', () => {
  const env = environment(); setup(env);
  const ledger = env.allSheets.find(s => s.name === '_FCTC_Operations');
  ledger.values[0][0] = 'wrong';
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).conflict.reason, 'invalid_table');
  ledger.values[0][0] = 'FCTC_V2';
  ledger.maxRows = ledger.values.length;
  const before = env.batches.length;
  const request = mutation('createGuest', { guestId: 'eeeeeeee-1234-4123-8123-123456789012', displayName: 'Capacity', confirmDistinct: false });
  assert.equal(env.post(request).conflict.reason, 'table_capacity');
  assert.equal(env.batches.length, before);
  assert.equal(ledger.maxRows, 2);
  assert.equal(env.context.PropertiesService.getScriptProperties().getProperty('FCTC_PENDING_OPERATION'), null);
});

test('a 33-member overwrite verifies the changed row with one grouped values read', () => {
  const members = Array.from({ length: 33 }, (_, i) => `Member ${i + 1}`);
  const env = createEnvironment({ sheetName: '2026', properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' }, grid: [
    ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', ...members, "+1's", 'Total Attendance per run'],
    ['Fri, 3-Jan', 'Beach', 'Soft Sand', 7.5, '', ...members.map(() => ''), 0, '=COUNTIF(F2:AL2,"x")+AM2'],
  ] });
  setup(env);
  const request = attendance(env, [], { attendees: members, actualKm: null });
  const reads = observeReads(env), response = env.post(request);
  assert.equal(response.status, 'completed', JSON.stringify(response));
  assert.equal(response.written, 33);
  const values = reads.filter(r => r.sheet === '2026' && r.method === 'getValues');
  assert.equal(values.length, 2, 'One store snapshot and one verification range');
  assert.ok(values.some(r => r.row === 2 && r.rows === 1 && r.col === 6 && r.cols === 33));
});

test('grouped verification checks every value and formula, preserving blank normalization', () => {
  const env = environment(); setup(env);
  const id = env.sheet.getSheetId();
  env.sheet.values[2][5] = '=1'; env.sheet.values[2][6] = '=2';
  const target = { cells: [{ sheetId: id, row: 2, col: 6, value: 'x' }, { sheetId: id, row: 3, col: 5, value: null }],
    formulas: [{ sheetId: id, row: 3, col: 6, formula: '=1' }, { sheetId: id, row: 3, col: 7, formula: '=2' }] };
  const reads = observeReads(env);
  assert.equal(env.context.guestVerifyTargets_(env.spreadsheet, target), true);
  assert.equal(reads.length, 2, 'One values read and one formulas read for this sheet');
  env.sheet.values[2][6] = '=3';
  assert.equal(env.context.guestVerifyTargets_(env.spreadsheet, target), false);
  env.sheet.values[2][6] = '=2'; env.sheet.values[1][5] = '';
  assert.equal(env.context.guestVerifyTargets_(env.spreadsheet, target), false);
});

test('sparse verification reads bounded ranges without loading the empty gap', () => {
  const env = environment(); setup(env);
  const sheet = env.allSheets.find(s => s.name === '_FCTC_GuestAttendance');
  sheet.ensure_(20000, 3); sheet.values[19999][2] = 'last';
  const target = { cells: [{ sheetId: sheet.sheetId, row: 1, col: 1, value: 'FCTC_V2' },
    { sheetId: sheet.sheetId, row: 20000, col: 3, value: 'last' }] };
  const reads = observeReads(env);
  assert.equal(env.context.guestVerifyTargets_(env.spreadsheet, target), true);
  assert.ok(reads.every(r => r.rows * r.cols <= 10000));
  assert.ok(reads.reduce((sum, r) => sum + r.rows * r.cols, 0) < 20000);
});

test('a formula mismatch keeps a completed receipt fenced until exact repair', () => {
  const env = environment(), request = setup(env);
  const saved = env.context.guestReadOperation_(env.spreadsheet, request.operationId);
  saved.targetState.formulas = [{ sheetId: env.sheet.sheetId, row: 2, col: 9, formula: '=WRONG()' }];
  env.context.Sheets.Spreadsheets.batchUpdate({ requests: [env.context.guestOperationRequest_(saved)] }, env.spreadsheet.getId());
  env.context.guestReserveJournal_({ ...saved, status: 'pending' });
  env.context.PropertiesService.getScriptProperties().setProperty('FCTC_JOURNAL_PHASE', 'dispatching');
  assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'pending');
  assert.equal(env.context.PropertiesService.getScriptProperties().getProperty('FCTC_PENDING_OPERATION'), request.operationId);
  env.sheet.values[1][8] = '=WRONG()';
  assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'completed');
  assert.equal(env.context.PropertiesService.getScriptProperties().getProperty('FCTC_PENDING_OPERATION'), null);
});
