'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const GuestOps = require('../GuestOps.js');
const { createEnvironment } = require('./support/fakeAppsScript.js');

const fixture = () => [
  ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', 'Toby', "+1's", 'Total Attendance per run'],
  ['Fri, 3-Jan', 'Beach', 'Soft Sand', 7.5, 7.2, 'x', '-', 1, '=COUNTIF(F2:G2,"x")+H2'],
  ['Fri, 10-Jan', 'Beach', 'Soft Sand', 7.5, '', '', '', '', '=COUNTIF(F3:G3,"x")+H3'],
];
let sequence = 1;
const uuid = () => (sequence++).toString(16).padStart(8, '0') + '-1234-4123-8123-123456789012';
function mutation(action, fields = {}) {
  const request = { apiVersion: 2, operationId: uuid(), action, ...fields };
  request.requestDigest = crypto.createHash('sha256').update(GuestOps.canonicalRequest(request)).digest('hex');
  return request;
}
function environment() {
  return createEnvironment({ grid: fixture(), sheetName: '2026', properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
}
function setup(env) {
  const book = env.context.SpreadsheetApp.getActiveSpreadsheet();
  const request = mutation('setupSharedGuests', { spreadsheetId: book.getId(), seasonSheetIds: [env.sheet.getSheetId()] });
  const result = env.post(request);
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.status, 'completed', JSON.stringify(result));
  env.context.PropertiesService.getScriptProperties().setProperty('SHARED_GUESTS_ENABLED', 'true');
  return request;
}
function guest(env, name = 'Rene') {
  const request = mutation('createGuest', { guestId: uuid(), displayName: name, confirmDistinct: false });
  const result = env.post(request);
  assert.equal(result.status, 'completed', JSON.stringify(result));
  return result.guest;
}
function attendance(env, namedGuestIds, overrides = {}) {
  const state = env.post({ action: 'getState', apiVersion: 2 });
  const run = state.runs[0];
  return mutation('submitAttendance', {
    spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, runId: run.runId,
    rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run, attendees: ['Col'],
    namedGuestIds, unnamedGuests: 0, actualKm: 7.2, mode: 'overwrite', baseRevision: state.sheetRevision,
    ...overrides,
  });
}

test('shared guest routes are gated until explicit setup and enablement', () => {
  const env = environment();
  const result = env.post(mutation('createGuest', { guestId: uuid(), displayName: 'Rene', confirmDistinct: false }));
  assert.equal(result.error, 'shared_guests_disabled');
  assert.equal(env.writes().length, 0);
});
test('setup creates hidden tables and stable run identities without changing season cells', () => {
  const env = environment();
  const before = env.grid();
  const request = setup(env);
  const state = env.post({ action: 'getState', apiVersion: 2 });
  assert.equal(state.capabilities.sharedGuests, true);
  assert.equal(state.capabilities.guestPromotion, false);
  assert.equal(state.runs.length, 2);
  assert.notEqual(state.runs[0].runId, state.runs[1].runId);
  assert.deepEqual(env.grid(), before);
  assert.deepEqual(env.post(request), env.post(request));
  assert.equal(env.post({ action: 'addMember', name: 'Sam' }).error, 'update_required');
});
test('two clients see one shared guest attendance, name-only edits and durable receipts', () => {
  const env = environment(); setup(env);
  const rene = guest(env);
  const request = attendance(env, [rene.guestId]);
  const saved = env.post(request);
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  assert.deepEqual(env.post(request), saved);
  const state = env.post({ action: 'getState', apiVersion: 2 });
  assert.equal(state.runs[0].plusOnes, 1);
  assert.equal(state.runs[0].unnamedGuests, 0);
  assert.deepEqual(state.runs[0].namedGuestIds, [rene.guestId]);
  assert.equal(state.guests[0].confirmedRuns, 1);
  assert.equal(env.grid()[1][6], '-', 'An absence annotation must survive unrelated attendance edits');
  const history = env.post({ action: 'getGuestHistory', guestId: rene.guestId });
  assert.equal(history.attendance[0].runId, state.runs[0].runId);
  const rename = env.post(mutation('renameGuest', { guestId: rene.guestId, displayName: 'René', baseGuestRevision: 1 }));
  assert.equal(rename.status, 'completed', JSON.stringify(rename));
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).guests[0].displayName, 'René');
  const altered = { ...request, actualKm: 8 };
  altered.requestDigest = crypto.createHash('sha256').update(GuestOps.canonicalRequest(altered)).digest('hex');
  assert.equal(env.post(altered).conflict.reason, 'operation_id_reused');
  assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'completed');
});

module.exports = { fixture, mutation, environment, setup, guest, attendance };

function failMutationBatch(env, failure) {
  const api = env.context.Sheets.Spreadsheets;
  const original = api.batchUpdate;
  let calls = 0;
  api.batchUpdate = (request, id) => {
    if (++calls === 2) env.failNextBatch(failure);
    return original(request, id);
  };
}

test('merge unions named identities across stale clients and overwrite requires review', () => {
  const env = environment(); setup(env);
  const rene = guest(env), priya = guest(env, 'Priya');
  const first = attendance(env, [rene.guestId]);
  const second = attendance(env, [priya.guestId], { mode: 'merge' });
  const stale = attendance(env, []);
  assert.equal(env.post(first).status, 'completed');
  assert.equal(env.post(second).status, 'completed');
  const run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  assert.deepEqual(run.namedGuestIds, [rene.guestId, priya.guestId].sort());
  assert.equal(run.plusOnes, 2);
  assert.equal(env.post(stale).conflict.reason, 'stale_revision');
  assert.equal(env.post(attendance(env, [rene.guestId], { mode: 'merge' })).status, 'completed');
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).guests.find(g => g.guestId === rene.guestId).confirmedRuns, 1);
});

test('same-name creation needs an explicit choice and forged digests cannot write', () => {
  const env = environment(); setup(env); guest(env);
  const duplicate = mutation('createGuest', { guestId: uuid(), displayName: 'Rene', confirmDistinct: false });
  assert.equal(env.post(duplicate).conflict.reason, 'identity_ambiguous');
  const distinct = mutation('createGuest', { guestId: uuid(), displayName: 'Rene', confirmDistinct: true });
  assert.equal(env.post(distinct).status, 'completed');
  const forged = mutation('createGuest', { guestId: uuid(), displayName: 'Other', confirmDistinct: false });
  forged.requestDigest = '0'.repeat(64);
  assert.equal(env.post(forged).error, 'invalid_operation');
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).guests.length, 2);
});

test('lost applied response survives restart, fences writers, and verifies one receipt', () => {
  const env = environment(); setup(env);
  const rene = guest(env), request = attendance(env, [rene.guestId]);
  failMutationBatch(env, 'after');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).pendingOperationId, request.operationId);
  assert.equal(env.post({ action: 'addRun', date: 'Fri, 20-Feb', run: 'Soft Sand' }).conflict.reason, 'pending_verification');
  assert.equal(env.post({ action: 'exportAttendanceSnapshot' }).error, 'busy');
  const restarted = env.restart();
  const receipt = restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation;
  assert.equal(receipt.status, 'completed');
  assert.deepEqual(restarted.post(request), receipt.response);
  const state = restarted.post({ action: 'getState', apiVersion: 2 });
  assert.equal(state.pendingOperationId, null);
  assert.equal(state.guests[0].confirmedRuns, 1);
  const journalText = JSON.stringify(restarted.allSheets.find(s => s.name === '_FCTC_Operations').values);
  assert.equal(journalText.includes('test-secret'), false, 'The canonical operation must omit credentials');
});

test('an absent receipt after dispatch stays fenced after restart; no structural replay', () => {
  const env = environment(); setup(env);
  const state = env.post({ action: 'getState', apiVersion: 2 });
  const request = mutation('addMember', { name: 'Sam', baseRevision: state.sheetRevision });
  const before = env.grid();
  failMutationBatch(env, 'before');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  assert.deepEqual(env.grid(), before);
  const restarted = env.restart();
  assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'pending');
  assert.equal(restarted.post(request).conflict.reason, 'pending_verification');
  assert.equal(restarted.post(mutation('createGuest', { guestId: uuid(), displayName: 'Sam', confirmDistinct: false })).conflict.reason, 'pending_verification');
  assert.deepEqual(restarted.grid(), before);
});

test('a terminated reservation before dispatch is not_applied, never automatically retried', () => {
  const env = environment(); setup(env);
  const request = mutation('createGuest', { guestId: uuid(), displayName: 'Rene', confirmDistinct: false });
  const api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
  api.batchUpdate = (batch, id) => { original(batch, id); throw new Error('Execution stopped after reservation'); };
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  const restarted = env.restart();
  assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'not_applied');
  assert.equal(restarted.post(request).error, 'not_applied');
  assert.equal(restarted.post({ action: 'getState', apiVersion: 2 }).guests.length, 0);
  assert.equal(guest(restarted).displayName, 'Rene');
});

test('row insertion keeps metadata identity and stale coordinates resolve to the moved run', () => {
  const env = environment(); setup(env);
  const rene = guest(env), saved = attendance(env, [rene.guestId]);
  assert.equal(env.post(saved).status, 'completed');
  const staleCoordinates = attendance(env, [rene.guestId], { mode: 'merge' });
  const state = env.post({ action: 'getState', apiVersion: 2 });
  const added = env.post(mutation('addRun', { date: 'Thu, 2-Jan', meet: 'Beach', run: 'Trail', approxKm: 4,
    spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, baseRevision: state.sheetRevision }));
  assert.equal(added.status, 'completed', JSON.stringify(added));
  assert.equal(env.post(staleCoordinates).status, 'completed');
  const history = env.post({ action: 'getGuestHistory', guestId: rene.guestId });
  assert.equal(history.attendance[0].runId, saved.runId);
  assert.equal(history.attendance[0].rowIndex, 3);
  const historical = env.post({ action: 'getState', apiVersion: 2, seasonSheetId: state.seasonSheetId });
  assert.equal(historical.runs.find(r => r.runId === saved.runId).namedGuestIds[0], rene.guestId);
});

test('missing or duplicate row metadata blocks changes without guessing by date', () => {
  for (const kind of ['missing', 'duplicate']) {
    const env = environment(); setup(env);
    const rene = guest(env), request = attendance(env, [rene.guestId]);
    if (kind === 'missing') env.sheet.metadata.shift();
    else env.sheet.metadata.push(structuredClone(env.sheet.metadata[0]));
    const before = env.grid();
    const result = env.post(request);
    assert.equal(result.conflict.reason, kind === 'missing' ? 'run_missing' : 'duplicate_run_identity');
    assert.deepEqual(env.grid(), before);
  }
});

test('promoted identities return an actionable mapping and cannot restore guest allocation', () => {
  const env = environment(); setup(env);
  const rene = guest(env), stale = attendance(env, [rene.guestId]);
  const table = env.allSheets.find(s => s.name === '_FCTC_Guests');
  table.values[1][1] = JSON.stringify({ ...rene, status: 'promoted', memberName: 'Rene Member', revision: 2 });
  const response = env.post(stale);
  assert.equal(response.conflict.reason, 'guest_promoted');
  assert.equal(response.conflict.memberName, 'Rene Member');
  assert.ok(response.conflict.state);
  assert.equal(env.grid()[1][7], 1);
});

test('notes, formulas and absence annotations survive named assignment', () => {
  const env = environment(); setup(env);
  const rene = guest(env), beforeFormula = env.grid()[1][8];
  env.sheet.notes['1,7'] = 'Original note';
  assert.equal(env.post(attendance(env, [rene.guestId])).status, 'completed');
  assert.equal(env.sheet.notes['1,7'], 'Original note');
  assert.equal(env.grid()[1][6], '-');
  assert.equal(env.grid()[1][8], beforeFormula);
});

test('invalid final subrequest rolls back attendance and guest history together', () => {
  const env = environment(); setup(env);
  const rene = guest(env), request = attendance(env, [rene.guestId]);
  const before = env.grid(), api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
  let calls = 0;
  api.batchUpdate = (batch, id) => {
    if (++calls === 2) batch.requests.push({ updateCells: { start: { sheetId: -999, rowIndex: 0, columnIndex: 0 },
      rows: [{ values: [{ userEnteredValue: { stringValue: 'invalid' } }] }], fields: 'userEnteredValue' } });
    return original(batch, id);
  };
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  assert.deepEqual(env.grid(), before);
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).guests[0].confirmedRuns, 0);
  assert.equal(env.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'pending');
});

test('setup response loss recovers its bootstrap journal without duplicate metadata or tables', () => {
  const env = environment(), book = env.context.SpreadsheetApp.getActiveSpreadsheet();
  const request = mutation('setupSharedGuests', { spreadsheetId: book.getId(), seasonSheetIds: [env.sheet.getSheetId()] });
  env.failNextBatch('after');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  assert.equal(env.allSheets.length, 4);
  assert.equal(env.sheet.metadata.length, 2);
  const restarted = env.restart();
  const status = restarted.post({ action: 'getOperationStatus', operationId: request.operationId });
  assert.equal(status.operation.status, 'completed');
  assert.equal(restarted.post(request).status, 'completed');
  assert.equal(restarted.allSheets.length, 4);
  assert.equal(restarted.sheet.metadata.length, 2);
  assert.equal(restarted.properties.SHARED_GUESTS_ENABLED, undefined, 'Setup must not enable writes');
});

test('history opens the exact season and counts distinct same-date runs across seasons', () => {
  const env = createEnvironment({ grid: fixture(), sheetName: '2026', extraSheets: [{ name: '2025', sheetId: 25, grid: fixture() }],
    properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
  const book = env.context.SpreadsheetApp.getActiveSpreadsheet();
  assert.equal(env.post(mutation('setupSharedGuests', { spreadsheetId: book.getId(), seasonSheetIds: [25, 26] })).status, 'completed');
  env.properties.SHARED_GUESTS_ENABLED = 'true';
  const rene = guest(env);
  assert.equal(env.post(attendance(env, [rene.guestId])).status, 'completed');
  const state = env.post({ action: 'getState', apiVersion: 2, seasonSheetId: 25 }), run = state.runs[0];
  const request = mutation('submitAttendance', { spreadsheetId: state.spreadsheetId, seasonSheetId: 25, runId: run.runId,
    rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run, attendees: ['Col'], namedGuestIds: [rene.guestId],
    unnamedGuests: 0, actualKm: 7.2, mode: 'overwrite', baseRevision: state.sheetRevision });
  assert.equal(env.post(request).status, 'completed');
  const history = env.post({ action: 'getGuestHistory', guestId: rene.guestId });
  assert.equal(history.guest.confirmedRuns, 2);
  assert.equal(history.guest.lastAttendance.seasonYear, 2026);
  assert.deepEqual(history.attendance.map(a => a.seasonSheetId).sort(), [25, 26]);
  const reopened = env.post({ action: 'getState', apiVersion: 2, seasonSheetId: history.attendance[1].seasonSheetId });
  assert.ok(reopened.runs.some(r => r.runId === history.attendance[1].runId));
});

test('structural member receipts replay without adding a second column and preserve displaced notes', () => {
  for (const name of ['Aaron', 'Sam', 'Zoe']) {
    const env = environment(); setup(env);
    env.sheet.notes['1,6'] = 'Toby note';
    const state = env.post({ action: 'getState', apiVersion: 2 });
    const request = mutation('addMember', { name, baseRevision: state.sheetRevision });
    const saved = env.post(request);
    assert.equal(saved.status, 'completed', JSON.stringify(saved));
    const after = env.grid();
    assert.deepEqual(env.post(request), saved);
    assert.deepEqual(env.grid(), after);
    const fresh = env.post({ action: 'getState', apiVersion: 2 });
    assert.equal(fresh.roster.length, 3);
    assert.equal(saved.sheetRevision, fresh.sheetRevision);
    assert.deepEqual(saved.roster, fresh.roster);
    const toby = fresh.roster.find(member => member.name === 'Toby');
    assert.equal(env.grid()[1][toby.colIndex - 1], '-');
    assert.equal(env.sheet.notes[`1,${toby.colIndex - 1}`], 'Toby note');
  }
});

test('lost structural success is verified before clearing the workbook fence', () => {
  const env = environment(); setup(env);
  const state = env.post({ action: 'getState', apiVersion: 2 });
  const request = mutation('addMember', { name: 'Sam', baseRevision: state.sheetRevision });
  failMutationBatch(env, 'after');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  const restarted = env.restart();
  assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'completed');
  assert.equal(restarted.post(request).status, 'completed');
  assert.equal(restarted.post({ action: 'getState', apiVersion: 2 }).roster.length, 3);
});

test('failed postcondition verification keeps even a completed receipt fenced', () => {
  const env = environment(); setup(env);
  const rene = guest(env), request = attendance(env, [rene.guestId], { actualKm: 8.8 });
  failMutationBatch(env, 'after');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  env.sheet.values[1][4] = 7.2; // A manual edit outside the script lock invalidates the saved target.
  const restarted = env.restart();
  assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'pending');
  assert.equal(restarted.post({ action: 'addMember', name: 'New' }).conflict.reason, 'pending_verification');
});

test('pending journals remain bounded and contain canonical requests, source revisions and targets', () => {
  const env = environment(); setup(env);
  const rene = guest(env), request = attendance(env, [rene.guestId]);
  failMutationBatch(env, 'before');
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  const props = env.properties, count = Number(props.FCTC_JOURNAL_COUNT);
  let text = '';
  for (let i = 0; i < count; i++) {
    const chunk = props[`FCTC_JOURNAL_${i}`];
    assert.ok(Buffer.byteLength(chunk, 'utf8') < 9000);
    text += chunk;
  }
  const operation = JSON.parse(text);
  assert.equal(operation.canonicalRequest, GuestOps.canonicalRequest(request));
  assert.ok(operation.sourceRevisions.sheetRevision);
  assert.ok(operation.sourceRevisions.guestRevision);
  assert.ok(operation.plannedRequests.length);
  assert.ok(operation.targetState.cells.length);
  assert.ok(operation.receiptLocation.rowIndex > 1);
  assert.equal(props.FCTC_JOURNAL_PHASE, 'dispatching');
  assert.ok(!text.includes('test-secret'));
});

test('disabling shared guests cannot reopen legacy writers after shared attendance exists', () => {
  const env = environment(); setup(env);
  const rene = guest(env);
  assert.equal(env.post(attendance(env, [rene.guestId])).status, 'completed');
  env.properties.SHARED_GUESTS_ENABLED = 'false';
  const before = env.grid();
  for (const request of [
    { action: 'submitAttendance', rowIndex: 2, expectedDate: 'Fri, 3-Jan', expectedRun: 'Soft Sand', attendees: [], plusOnes: 0 },
    { action: 'addMember', name: 'Legacy member' },
    { action: 'addRun', date: 'Fri, 20-Feb', meet: 'Beach', run: 'Soft Sand', approxKm: 7.5 },
  ]) assert.equal(env.post(request).error, 'update_required');
  assert.deepEqual(env.grid(), before);
  assert.equal(env.post(mutation('createGuest', { guestId: uuid(), displayName: 'New', confirmDistinct: false })).error, 'shared_guests_disabled');
});

test('authentication precedes every shared read, setup and mutation route', () => {
  const env = environment();
  for (const action of ['getState', 'getGuestHistory', 'getOperationStatus', 'setupSharedGuests', 'createGuest', 'renameGuest',
    'submitAttendance', 'addMember', 'addRun', 'importGuestHistory', 'previewPromotion', 'commitPromotion', 'exportAttendanceSnapshot']) {
    const response = env.raw(JSON.stringify({ secret: 'incorrect-secret', apiVersion: 2, action }));
    assert.equal(response.error, 'bad_secret', action);
  }
  assert.equal(env.writes().length, 0);
  assert.equal(env.batches.length, 0);
});

test('legacy writers recheck format and pending fence after waiting for the lock', () => {
  for (const transition of ['shared-format', 'pending-operation']) {
    for (const request of [
      { action: 'submitAttendance', rowIndex: 2, expectedDate: 'Fri, 3-Jan', expectedRun: 'Soft Sand', attendees: [], plusOnes: 0 },
      { action: 'addMember', name: 'Legacy member' },
      { action: 'addRun', date: 'Fri, 20-Feb', meet: 'Beach', run: 'Soft Sand', approxKm: 7.5 },
    ]) {
      const env = environment(), before = env.grid();
      const original = env.context.LockService.getScriptLock;
      env.context.LockService.getScriptLock = () => {
        const lock = original();
        return { releaseLock: () => lock.releaseLock(), waitLock: timeout => {
          lock.waitLock(timeout);
          if (transition === 'pending-operation') env.properties.FCTC_PENDING_OPERATION = uuid();
          else env.allSheets.push(new env.sheet.constructor('_FCTC_Guests', [['FCTC_V2', 'schema2']], 900));
        } };
      };
      const result = env.post(request);
      assert.equal(transition === 'shared-format' ? result.error : result.conflict?.reason,
        transition === 'shared-format' ? 'update_required' : 'pending_verification', `${transition}: ${request.action}`);
      assert.deepEqual(env.grid(), before);
      assert.deepEqual(env.lockLog.map(entry => entry.kind), ['waitLock', 'releaseLock']);
    }
  }
});

test('getState reads the enabled flag and fence only after acquiring its lock', () => {
  const env = environment(); setup(env);
  env.properties.SHARED_GUESTS_ENABLED = 'false';
  const operationId = uuid(), original = env.context.LockService.getScriptLock;
  env.context.LockService.getScriptLock = () => {
    const lock = original();
    return { releaseLock: () => lock.releaseLock(), waitLock: timeout => {
      lock.waitLock(timeout);
      env.properties.SHARED_GUESTS_ENABLED = 'true';
      env.properties.FCTC_PENDING_OPERATION = operationId;
    } };
  };
  const result = env.post({ action: 'getState' });
  assert.equal(result.apiVersion, 2);
  assert.equal(result.capabilities.sharedGuests, true);
  assert.equal(result.pendingOperationId, operationId);
});
