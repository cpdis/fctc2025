'use strict';
/**
 * Run cancelled (docs/plans/2026-11-23-1050-feat-run-cancelled-plan.md, U1).
 *
 * The shared fixture holds the marker rule every stack reads. The server writes
 * the marker into the Run cell through the v2 operation journal, refuses to cancel
 * a run with attendance, and refuses attendance on a cancelled run.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const SheetOps = require('../SheetOps.js');
const { environment, setup, mutation } = require('./guest-api.checks.js');
const cancellation = require('../../fixtures/attendance/run-cancellation.json');

// Fixture rows: row 2 "Fri, 3-Jan" has Col and one +1; row 3 "Fri, 10-Jan" is blank.
const BLANK = 1;
const RUN_CELL = [2, 2]; // grid[2][2] is C3, the blank run's Run cell.

function sharedState(env) {
  return env.post({ action: 'getState', apiVersion: 2 });
}
function cancelRequest(env, index, cancelled) {
  const state = sharedState(env), run = state.runs[index];
  return mutation('setRunCancelled', {
    spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, runId: run.runId,
    rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run, cancelled,
  });
}
// A merge save of Col to the blank run, built from the state the phone last saw.
function saveRequest(env) {
  const state = sharedState(env), run = state.runs[BLANK];
  return mutation('submitAttendance', {
    spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, runId: run.runId,
    rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run, attendees: ['Col'],
    namedGuestIds: [], unnamedGuests: 0, actualKm: null, mode: 'merge', baseRevision: state.sheetRevision,
  });
}
// Every cell that differs between two grids, as "row,col".
function changedCells(before, after) {
  const changed = [];
  after.forEach((row, r) => row.forEach((value, c) => {
    if (String(value ?? '') !== String((before[r] || [])[c] ?? '')) changed.push(`${r},${c}`);
  }));
  return changed;
}

test('every fixture Run cell parses to its label and marked flag', () => {
  for (const sample of cancellation.cases) {
    assert.deepEqual(SheetOps.runCancellation(sample.raw), { label: sample.label, marked: sample.marked }, sample.raw);
  }
  for (const sample of cancellation.written) {
    assert.equal(SheetOps.cancelledRunLabel(sample.label), sample.cell);
  }
});

test('a marked row is cancelled only while it has no attendance', () => {
  const run = { run: 'River Loop (cancelled)', attendees: [], plusOnes: 0 };
  assert.equal(SheetOps.isCancelledRun(run), true);
  assert.equal(SheetOps.isCancelledRun({ ...run, attendees: ['Dan'] }), false);
  assert.equal(SheetOps.isCancelledRun({ ...run, plusOnes: 1 }), false);
  assert.equal(SheetOps.isCancelledRun({ ...run, run: 'River Loop' }), false);
});

test('run identity ignores the marker, so a queued save still finds its run', () => {
  assert.equal(SheetOps.sameRunIdentity('Fri, 8-May', 'River Loop (cancelled)', 'Fri, 8-May', 'River Loop'), true);
  assert.equal(SheetOps.sameRunIdentity('Fri, 8-May', 'River Loop (cancelled)', 'Fri, 8-May', 'Cruise'), false);
});

test('shared state advertises run cancellation only once shared guests are enabled', () => {
  const env = environment();
  assert.equal(sharedState(env).capabilities.runCancellation, false);
  setup(env);
  assert.equal(sharedState(env).capabilities.runCancellation, true);
});

test('cancel writes only the marker to the blank run and restore removes it', () => {
  const env = environment(); setup(env);
  const before = env.grid();
  const cancel = cancelRequest(env, BLANK, true);
  const saved = env.post(cancel);
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  assert.equal(env.grid()[RUN_CELL[0]][RUN_CELL[1]], 'Soft Sand (cancelled)');
  assert.deepEqual(changedCells(before, env.grid()), [RUN_CELL.join(',')]);
  assert.equal(sharedState(env).runs[BLANK].run, 'Soft Sand (cancelled)', 'getState keeps the raw Run cell');
  assert.equal(saved.sheetRevision, sharedState(env).sheetRevision, 'The predicted revision matches the saved sheet');
  assert.deepEqual(env.post(cancel), saved, 'A repeated operation ID replays its receipt');

  const again = env.post(cancelRequest(env, BLANK, true));
  assert.equal(again.status, 'completed', JSON.stringify(again));
  assert.equal(again.written, 0, 'Cancelling a cancelled run changes nothing');

  const restore = env.post(cancelRequest(env, BLANK, false));
  assert.equal(restore.status, 'completed', JSON.stringify(restore));
  assert.deepEqual(env.grid(), before);
});

test('a run with a mark or a +1 cannot be cancelled', () => {
  const env = environment(); setup(env);
  const before = env.grid();
  const marked = env.post(cancelRequest(env, 0, true));
  assert.equal(marked.conflict?.reason, 'run_has_attendance', JSON.stringify(marked));
  assert.equal(marked.conflict.state.runs[0].attendees[0], 'Col', 'The refusal returns fresh state');

  env.sheet.values[2][7] = 1; // One +1 on the blank run, and no member marks.
  const guestOnly = env.post(cancelRequest(env, BLANK, true));
  assert.equal(guestOnly.conflict?.reason, 'run_has_attendance', JSON.stringify(guestOnly));
  before[2][7] = 1;
  assert.deepEqual(env.grid(), before);
});

test('a formula in the Run cell is never overwritten', () => {
  const env = environment(); setup(env);
  env.sheet.values[RUN_CELL[0]][RUN_CELL[1]] = '="Soft Sand"';
  const result = env.post(cancelRequest(env, BLANK, true));
  assert.equal(result.conflict?.reason, 'unsafe_formula', JSON.stringify(result));
  assert.equal(env.grid()[RUN_CELL[0]][RUN_CELL[1]], '="Soft Sand"');
});

test('attendance to a cancelled run is refused until it is restored', () => {
  const env = environment(); setup(env);
  const save = saveRequest(env); // Queued before the cancel, so it still names "Soft Sand".
  assert.equal(env.post(cancelRequest(env, BLANK, true)).status, 'completed');
  const refused = env.post(save);
  assert.equal(refused.conflict?.reason, 'run_cancelled', JSON.stringify(refused));
  assert.equal(env.grid()[2][5], '', 'No mark is written');

  assert.equal(env.post(cancelRequest(env, BLANK, false)).status, 'completed');
  const retried = env.post(saveRequest(env));
  assert.equal(retried.status, 'completed', JSON.stringify(retried));
  assert.equal(env.grid()[2][5], 'x');
});

test('a hand-typed marker on a row with a mark is a normal run that accepts attendance', () => {
  const env = environment(); setup(env);
  env.sheet.values[2][2] = 'Soft Sand (cancelled)';
  env.sheet.values[2][6] = 'x'; // Toby, typed by hand.
  const saved = env.post(saveRequest(env));
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  assert.deepEqual(sharedState(env).runs[BLANK].attendees, ['Col', 'Toby']);
});

test('the legacy writer refuses attendance on a cancelled run', () => {
  const env = environment();
  env.sheet.values[2][2] = 'Soft Sand (cancelled)';
  const state = env.post({ action: 'getState' });
  const result = env.post({ action: 'submitAttendance', rowIndex: 3, expectedDate: 'Fri, 10-Jan',
    expectedRun: 'Soft Sand', attendees: ['Col'], plusOnes: 0, actualKm: null, mode: 'merge',
    baseRevision: state.sheetRevision });
  assert.equal(result.conflict?.reason, 'run_cancelled', JSON.stringify(result));
  assert.equal(env.grid()[2][5], '');
});

test('a cancel behind another client\'s unverified write waits and changes nothing', () => {
  const env = environment(); setup(env);
  const state = sharedState(env);
  const member = mutation('addMember', { name: 'Sam', baseRevision: state.sheetRevision });
  const api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
  let calls = 0;
  api.batchUpdate = (batch, id) => { if (++calls === 2) env.failNextBatch('before'); return original(batch, id); };
  assert.equal(env.post(member).conflict.reason, 'pending_verification');
  api.batchUpdate = original;
  const before = env.grid();
  const cancel = env.post(mutation('setRunCancelled', {
    spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, runId: state.runs[BLANK].runId,
    rowIndex: state.runs[BLANK].rowIndex, expectedDate: state.runs[BLANK].date, expectedRun: state.runs[BLANK].run,
    cancelled: true }));
  assert.equal(cancel.conflict?.reason, 'pending_verification', JSON.stringify(cancel));
  assert.deepEqual(env.grid(), before);
});

test('a cancel for a changed run or with a non-boolean flag is refused without a write', () => {
  const env = environment(); setup(env);
  const before = env.grid();
  const state = sharedState(env), run = state.runs[BLANK];
  const fields = { spreadsheetId: state.spreadsheetId, seasonSheetId: state.seasonSheetId, runId: run.runId,
    rowIndex: run.rowIndex, expectedDate: run.date };
  const moved = env.post(mutation('setRunCancelled', { ...fields, expectedRun: 'Cruise', cancelled: true }));
  assert.equal(moved.conflict?.reason, 'row_mismatch', JSON.stringify(moved));
  const vague = env.post(mutation('setRunCancelled', { ...fields, expectedRun: run.run, cancelled: 'yes' }));
  assert.equal(vague.conflict?.reason, 'invalid_operation', JSON.stringify(vague));
  assert.deepEqual(env.grid(), before);
});

test('restoring a run that is not cancelled completes without a write', () => {
  const env = environment(); setup(env);
  const before = env.grid();
  const restore = env.post(cancelRequest(env, BLANK, false));
  assert.equal(restore.status, 'completed', JSON.stringify(restore));
  assert.equal(restore.written, 0);
  assert.deepEqual(env.grid(), before);
});
