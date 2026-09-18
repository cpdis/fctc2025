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

test('birthday list follows member columns and discovers metadata before the first run', () => {
  const header = ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', '', 'Toby', "+1's", 'Total'];
  const row = ['', '', '', '', ' birthday ', '10-May', '1-Jan', '20-Jun', '2-Feb', '3-Mar'];
  const grid = [[], [], header, [], row, ['Fri, 3-Jan'], row];
  assert.deepEqual(SheetOps.listBirthdays(grid, 3), [
    { name: 'Col', month: 5, day: 10 }, { name: 'Toby', month: 6, day: 20 },
  ]);
  assert.deepEqual(SheetOps.listBirthdays([header, ['Fri, 3-Jan'], row], 1), []);
  assert.deepEqual(SheetOps.listBirthdays([header, []], 1), []);
  assert.deepEqual(SheetOps.listBirthdays([], 0), []);
});

test('birthday parser accepts valid month names and leap days without retaining a year', () => {
  for (const [text, month, day] of [
    ['1-Sep', 9, 1], [' 29-feb ', 2, 29], ['31 December', 12, 31], ['02/JAN', 1, 2],
  ]) {
    const grid = [fixture()[0], ['', '', '', '', 'BIRTHDAY', text]];
    assert.deepEqual(SheetOps.listBirthdays(grid, 1), [{ name: 'Col', month, day }], text);
  }
  for (const text of ['', null, '31-Apr', '30-Feb', '0-May', '32-Jan', '1-Smarch', '1/9',
    'next 1-Sep', '1-Sep-1980', '1-Septemberish', 44562]) {
    const grid = [fixture()[0], ['', '', '', '', 'BIRTHDAY', text]];
    assert.deepEqual(SheetOps.listBirthdays(grid, 1), [], String(text));
  }
});

test('birthday state is additive on legacy, shared and conflict responses without changing sheet cells', () => {
  const env = environment();
  assert.deepEqual(env.post({ action: 'getState' }).birthdays, []);
  insertBirthdays(env);
  const expected = [{ name: 'Col', month: 5, day: 10 }, { name: 'Toby', month: 6, day: 20 }];
  const before = env.grid(), writes = env.writes().length;
  const state = env.post({ action: 'getState' });
  assert.deepEqual(state.birthdays, expected);
  const conflict = env.post({ action: 'submitAttendance', rowIndex: 12, expectedDate: 'Fri, 3-Jan',
    expectedRun: 'Soft Sand', attendees: [], plusOnes: 0, actualKm: 8, mode: 'merge', baseRevision: state.sheetRevision });
  assert.deepEqual(conflict.conflict.state.birthdays, expected);
  assert.deepEqual(env.grid(), before);
  assert.equal(env.writes().length, writes);
  setup(env);
  assert.deepEqual(env.post({ action: 'getState', apiVersion: 2 }).birthdays, expected);
  const stale = attendance(env, [], { baseRevision: 'stale' });
  assert.deepEqual(env.post(stale).conflict.state.birthdays, expected);
});

test('birthday Date cells use the spreadsheet timezone rather than the script timezone', () => {
  const date = new Date('1999-12-31T16:00:00.000Z'); // Midnight on 1 January in Perth.
  const grid = [fixture()[0], ['', '', '', '', 'BIRTHDAY', date, new Date(NaN)], ...fixture().slice(1)];
  const env = createEnvironment({ grid, sheetName: '2026', timeZone: 'Australia/Perth' });
  assert.deepEqual(env.post({ action: 'getState' }).birthdays, [{ name: 'Col', month: 1, day: 1 }]);
  const utc = createEnvironment({ grid, sheetName: '2026', timeZone: 'Etc/UTC' });
  assert.deepEqual(utc.post({ action: 'getState' }).birthdays, [{ name: 'Col', month: 12, day: 31 }]);
  assert.deepEqual(env.grid()[1][5], date, 'Reading a birthday never changes the original cell');
});

test('birthday state uses the requested season only', () => {
  const env = createEnvironment({ grid: [fixture()[0], birthday, ...fixture().slice(1)], sheetName: '2026',
    extraSheets: [{ name: '2025', sheetId: 25, grid: [fixture()[0], ['', '', '', '', 'BIRTHDAY', '1-Jan'], ...fixture().slice(1)] }],
    properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
  const request = mutation('setupSharedGuests', { spreadsheetId: 'test-workbook', seasonSheetIds: [26, 25] });
  assert.equal(env.post(request).status, 'completed');
  env.context.PropertiesService.getScriptProperties().setProperty('SHARED_GUESTS_ENABLED', 'true');
  assert.deepEqual(env.post({ action: 'getState', apiVersion: 2, seasonSheetId: 25 }).birthdays,
    [{ name: 'Col', month: 1, day: 1 }]);
  assert.deepEqual(env.post({ action: 'getState', apiVersion: 2 }).birthdays,
    [{ name: 'Col', month: 5, day: 10 }, { name: 'Toby', month: 6, day: 20 }]);
});
