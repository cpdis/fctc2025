'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const SheetOps = require('../SheetOps.js');
const { createEnvironment } = require('./support/fakeAppsScript.js');
const { fixture, mutation, setup, guest, attendance } = require('./guest-api.checks.js');

// Match the organiser's layout: header at row 11, birthdays inserted at row 12.
// The dates are synthetic. No birthday values from the real workbook are used.
function environment() {
  return createEnvironment({ grid: [...Array.from({ length: 10 }, () => []), ...fixture()],
    sheetName: '2026', properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
}
const birthday = ['', '', '', '', 'BIRTHDAY', '10-May', '20-Jun', '', ''];
function insertBirthdays(env) {
  env.sheet.insertRowBefore(12);
  env.sheet.getRange(12, 1, 1, birthday.length).setValues([birthday]);
}

test('birthdays below the header do not change runs, member totals, or insertion order', () => {
  const env = environment(), before = env.grid();
  const runs = SheetOps.listRuns(before, 11), totals = SheetOps.attendanceTotals(before);
  insertBirthdays(env);
  const after = env.grid(), shifted = SheetOps.listRuns(after, 11);
  assert.equal(SheetOps.findHeaderRow(after), 11);
  assert.deepEqual(shifted, runs.map(run => ({ ...run, rowIndex: run.rowIndex + 1 })));
  assert.deepEqual(SheetOps.attendanceTotals(after), totals);
  assert.equal(SheetOps.readRun(after, SheetOps.bandBounds(after, 11), SheetOps.memberBand(after, 11), 12), null);
  assert.deepEqual(SheetOps.runInsertTarget(shifted, 11, 'Thu, 2-Jan'), { position: 0, rowIndex: 13, append: false });
});

test('legacy phones receive a row conflict instead of writing into the birthday row', () => {
  const env = environment();
  const before = env.post({ action: 'getState' }), run = before.runs[0];
  insertBirthdays(env);
  const writesBefore = env.writes().length;
  const result = env.post({ action: 'submitAttendance', rowIndex: run.rowIndex, expectedDate: run.date,
    expectedRun: run.run, attendees: ['Toby'], plusOnes: 2, actualKm: 8, mode: 'merge', baseRevision: before.sheetRevision });
  assert.equal(result.conflict.reason, 'row_mismatch');
  assert.equal(result.conflict.state.runs[0].rowIndex, 13);
  assert.equal(env.writes().length, writesBefore);
  assert.deepEqual(env.grid()[11], birthday);
});

test('shared run identity follows a birthday insertion without adding guest credit or changing birthdays', () => {
  const env = environment(); setup(env);
  const person = guest(env), original = attendance(env, [person.guestId]);
  assert.equal(env.post(original).status, 'completed');
  const staleMerge = attendance(env, [person.guestId], { mode: 'merge', actualKm: 8 });
  const staleOverwrite = attendance(env, [person.guestId]);
  insertBirthdays(env);

  const state = env.post({ action: 'getState', apiVersion: 2 });
  assert.equal(state.runs.length, 2);
  assert.equal(state.runs[0].rowIndex, 13);
  assert.equal(state.runs[0].runId, original.runId);
  assert.equal(state.guests[0].confirmedRuns, 1);
  assert.equal(env.post(staleOverwrite).conflict.reason, 'stale_revision');
  assert.equal(env.post(staleMerge).status, 'completed');
  assert.deepEqual(env.grid()[11], birthday);
  assert.equal(env.grid()[12][4], 8);
  assert.equal(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance[0].rowIndex, 13);
  assert.equal(env.post({ action: 'getState', apiVersion: 2 }).guests[0].confirmedRuns, 1);

  const fresh = env.post({ action: 'getState', apiVersion: 2 });
  const added = env.post(mutation('addRun', { date: 'Thu, 2-Jan', meet: 'Beach', run: 'Trail', approxKm: 4,
    spreadsheetId: fresh.spreadsheetId, seasonSheetId: fresh.seasonSheetId, baseRevision: fresh.sheetRevision }));
  assert.equal(added.status, 'completed', JSON.stringify(added));
  assert.deepEqual(env.grid()[11], birthday);
  assert.equal(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance[0].rowIndex, 14);
});
