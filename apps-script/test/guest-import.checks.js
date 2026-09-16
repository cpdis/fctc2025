'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { environment, setup, guest, mutation, attendance, fixture } = require('./guest-api.checks.js');
const { createEnvironment } = require('./support/fakeAppsScript.js');

function entry(run) {
  return { spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId,
    expectedDate: run.date, expectedRun: run.run, assignment: 'existing_unnamed_slot' };
}
function preview(env, person, entries) {
  return env.post({ action: 'previewGuestImport', guestId: person.guestId, entries });
}
function importRequest(person, reviewed) {
  return mutation('importGuestHistory', { guestId: person.guestId, entries: reviewed.entries,
    baseGuestRevision: reviewed.baseGuestRevision, baseRevision: reviewed.baseRevision });
}

test('reviewed history import names an existing slot without changing attendance cells', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  const reviewed = preview(env, person, [entry(run), entry(run)]);
  assert.equal(reviewed.ok, true, JSON.stringify(reviewed));
  assert.equal(reviewed.entries.length, 1, 'Repeated phone submissions identify one run');
  assert.equal(reviewed.changes[0].unnamedBefore, 1);
  assert.equal(reviewed.changes[0].unnamedAfter, 0);
  const before = env.grid(), request = importRequest(person, reviewed);
  const saved = env.post(request);
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  assert.equal(saved.confirmedRuns, 1);
  assert.deepEqual(env.grid(), before);
  assert.deepEqual(env.post(request), saved);
  const state = env.post({ action: 'getState', apiVersion: 2 });
  assert.equal(state.guests[0].confirmedRuns, 1);
  assert.equal(state.runs[0].plusOnes, 1);
  assert.equal(state.runs[0].unnamedGuests, 0);
});

test('two phones importing the same reviewed allocation receive one shared credit', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  const reviewed = preview(env, person, [entry(run)]);
  assert.equal(reviewed.ok, true, JSON.stringify(reviewed));
  const first = importRequest(person, reviewed), second = importRequest(person, reviewed);
  assert.equal(env.post(first).status, 'completed');
  const repeated = env.post(second);
  assert.equal(repeated.status, 'completed', JSON.stringify(repeated));
  assert.equal(repeated.importedRuns, 0);
  assert.equal(repeated.confirmedRuns, 1);
  assert.equal(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance.length, 1);
});

test('one missing allocation prevents the whole historical import', () => {
  const env = environment(); setup(env);
  const person = guest(env), runs = env.post({ action: 'getState', apiVersion: 2 }).runs;
  const before = env.grid(), reviewed = preview(env, person, runs.map(entry));
  assert.equal(reviewed.conflict?.reason, 'allocation_missing', JSON.stringify(reviewed));
  assert.deepEqual(env.grid(), before);
  assert.equal(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance.length, 0);
});

test('a changed allocation invalidates the preview before any import', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  const reviewed = preview(env, person, [entry(run)]);
  assert.equal(reviewed.ok, true, JSON.stringify(reviewed));
  assert.equal(env.post(attendance(env, [], { unnamedGuests: 2 })).status, 'completed');
  const saved = env.post(importRequest(person, reviewed));
  assert.equal(saved.conflict?.reason, 'stale_revision', JSON.stringify(saved));
  assert.equal(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance.length, 0);
});

test('history import requires exact run identity and an active shared guest', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  for (const invalid of [
    { ...entry(run), seasonSheetId: 25 },
    { ...entry(run), spreadsheetId: 'another-workbook' },
    { ...entry(run), expectedDate: 'Fri, 24-Jan' },
    { ...entry(run), assignment: 'invent_new_credit' },
  ]) assert.ok(preview(env, person, [invalid]).conflict);
  const table = env.allSheets.find(s => s.name === '_FCTC_Guests');
  table.values[1][1] = JSON.stringify({ ...person, status: 'promoted', memberName: 'Rene Member', revision: 2 });
  assert.equal(preview(env, person, [entry(run)]).conflict?.reason, 'guest_promoted');
});

test('preview is authenticated and respects a pending workbook fence', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  assert.equal(env.raw(JSON.stringify({ secret: 'wrong', action: 'previewGuestImport', guestId: person.guestId, entries: [entry(run)] })).error, 'bad_secret');
  env.properties.FCTC_PENDING_OPERATION = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  assert.equal(preview(env, person, [entry(run)]).conflict?.reason, 'pending_verification');
});

test('the same yearless date in two seasons requires two explicit run identities', () => {
  const env = createEnvironment({ grid: fixture(), sheetId: 26, sheetName: '2026',
    extraSheets: [{ name: '2025', sheetId: 25, grid: fixture() }],
    properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
  assert.equal(env.post(mutation('setupSharedGuests', {
    spreadsheetId: env.spreadsheet.getId(), seasonSheetIds: [25, 26]
  })).status, 'completed');
  env.properties.SHARED_GUESTS_ENABLED = 'true';
  const person = guest(env);
  const runs = [25, 26].map(seasonSheetId => env.post({ action: 'getState', apiVersion: 2, seasonSheetId }).runs[0]);
  assert.equal(runs[0].date, runs[1].date);
  const reviewed = preview(env, person, runs.map(entry));
  assert.equal(reviewed.entries.length, 2);
  assert.equal(env.post(importRequest(person, reviewed)).confirmedRuns, 2);
  assert.deepEqual(env.post({ action: 'getGuestHistory', guestId: person.guestId }).attendance.map(a => a.seasonYear).sort(), [2025, 2026]);
  assert.equal(env.allSheets.find(s => s.sheetId === 25).values[1][7], 1);
  assert.equal(env.sheet.values[1][7], 1);
});

test('lost import response recovers its receipt after process restart without consuming another slot', () => {
  const env = environment(); setup(env);
  const person = guest(env), run = env.post({ action: 'getState', apiVersion: 2 }).runs[0];
  const request = importRequest(person, preview(env, person, [entry(run)]));
  const api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
  let calls = 0;
  api.batchUpdate = (batch, id) => {
    if (++calls === 2) env.failNextBatch('after');
    return original(batch, id);
  };
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  const restarted = env.restart();
  const receipt = restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation;
  assert.equal(receipt.status, 'completed');
  assert.deepEqual(restarted.post(request), receipt.response);
  assert.equal(restarted.post({ action: 'getGuestHistory', guestId: person.guestId }).guest.confirmedRuns, 1);
  assert.equal(restarted.grid()[1][7], 1);
});
