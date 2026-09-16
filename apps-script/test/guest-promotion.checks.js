'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const GuestOps = require('../GuestOps.js');
const { createEnvironment } = require('./support/fakeAppsScript');

let sequence = 6000;
const uuid = () => (sequence++).toString(16).padStart(8, '0') + '-1234-4123-8123-123456789012';
function mutation(action, fields) {
  const request = { apiVersion: 2, operationId: uuid(), action, ...fields };
  request.requestDigest = crypto.createHash('sha256').update(GuestOps.canonicalRequest(request)).digest('hex');
  return request;
}
function grid(count) {
  return [
    ['', '', '', '', '', '=COUNTIF(F4:F20,"x")', '=COUNTIF(G4:G20,"x")'],
    ['', '', '', '', '', '=SUMIF(F4:F20,"x",E4:E20)', '=SUMIF(G4:G20,"x",E4:E20)'],
    ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', 'Toby', "+1's", 'Total Attendance per run'],
    ...Array.from({ length: count }, (_, i) => [`Fri, ${i + 1}-Jan`, 'Beach', 'Soft Sand', 7.5, 7.2 + i / 10,
      'x', '-', 2, `=COUNTIF(F${i + 4}:G${i + 4},"x")+H${i + 4}`]),
  ];
}
function seeded({ current = 8, historical = 3 } = {}) {
  const env = createEnvironment({ grid: grid(current), sheetName: '2026',
    extraSheets: [{ name: '2025', sheetId: 25, grid: grid(historical) }],
    properties: { SHARED_GUESTS_SETUP_ALLOWED: 'true' } });
  assert.equal(env.post(mutation('setupSharedGuests', { spreadsheetId: env.spreadsheet.getId(), seasonSheetIds: [25, 26] })).status, 'completed');
  env.properties.SHARED_GUESTS_ENABLED = 'true';
  const guestId = uuid();
  assert.equal(env.post(mutation('createGuest', { guestId, displayName: 'Rene', confirmDistinct: false })).status, 'completed');
  for (const seasonSheetId of [25, 26]) {
    const runs = env.post({ action: 'getState', apiVersion: 2, seasonSheetId }).runs;
    for (const run of runs) {
      const state = env.post({ action: 'getState', apiVersion: 2, seasonSheetId });
      const response = env.post(mutation('submitAttendance', { spreadsheetId: state.spreadsheetId, seasonSheetId,
        runId: run.runId, rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run,
        attendees: ['Col'], namedGuestIds: [guestId], unnamedGuests: 1, actualKm: run.actualKm,
        mode: 'overwrite', baseRevision: state.sheetRevision }));
      assert.equal(response.status, 'completed', JSON.stringify(response));
    }
  }
  return { env, guestId };
}
function preview(env, guestId, memberName = 'Rene', targetMode = 'create') {
  return env.post({ action: 'previewPromotion', guestId, memberName, targetMode });
}
function promotion(guestId, result) {
  return mutation('commitPromotion', { guestId, memberName: result.memberName,
    targetMode: result.targetMode, previewToken: result.previewToken });
}
function seasonState(env, id) { return env.post({ action: 'getState', apiVersion: 2, seasonSheetId: id }); }

test('formula shape follows open ranges without masking text, functions or names', () => {
  const shape = createEnvironment({ grid: grid(1), sheetName: '2026' }).context.guestFormulaShape_;
  for (const [before, after] of [
    ['=COUNTIF(AJ11:AJ,"x")', '=COUNTIF(AK11:AK,"x")'],
    ['=SUM($AJ:$AJ11)', '=SUM($AK:$AK11)'],
    ['=SUM(AJ:AK)', '=SUM(AK:AL)'],
    ['=SUM($11:$20)', '=SUM($12:$21)'],
    ['=SUM(AJ11:AK20)+$A$1', '=SUM(AK11:AL20)+$B$1'],
  ]) assert.equal(shape(before), shape(after), before);
  assert.equal(shape('=LOG10(A1)+RateA1'), '=LOG10(@)+RateA1');
  assert.equal(shape("='Tab A1'!A1+A1!B2"), "='Tab A1'!@+A1!@");
  assert.equal(shape('=INDIRECT("A1:A")'), '=INDIRECT("A1:A")');
  assert.notEqual(shape('=SUM(A1:A)+B1'), shape('=SUM(B1:B)-C1'));
  assert.notEqual(shape('=COUNTIF(A1:A,"A1")'), shape('=COUNTIF(B1:B,"B1")'));
});

test('a wrong-column summary cannot erase existing member credit during promotion', () => {
  for (const name of ['Aaron', 'Sam', 'Zoe', 'Toby']) {
    const env = createEnvironment({ grid: grid(1), sheetName: '2026' });
    env.sheet.values[0][5] = '=COUNTIF(F4:F,"x")';
    const ctx = env.context.readContext_(env.sheet, '2026'); ctx.sheetId = 26;
    ctx.runs = env.context.SheetOps.listRuns(ctx.grid, ctx.headerRow);
    // Supply an observed calculated value; the fake does not evaluate formulas.
    ctx.grid[0][5] = 1;
    ctx.grid[0][6] = 0;
    const member = name === 'Toby' ? { column: 7 }
      : env.context.guestPlanMember_(env.context.guestPlan_(), ctx, name);
    const snapshot = env.context.guestPromotionSnapshot_(ctx, member, name);
    const values = snapshot.values.map(row => row.slice());
    const formulas = snapshot.formulas.map(row => row.slice());
    const target = { sheetId: 26, height: values.length, width: values[0].length,
      digest: env.context.guestPreservationDigest_(values, formulas, snapshot.notes), derived: snapshot.derived };
    const book = { getSheetById: () => ({ getRange: () => ({ getValues: () => values,
      getFormulas: () => formulas, getNotes: () => snapshot.notes }) }) };
    assert.equal(env.context.guestVerifyPromotion_(book, [target]), true, name);
    if (name === 'Toby') {
      values[0][6] = 11; // The explicitly linked member is allowed to gain credit.
      assert.equal(env.context.guestVerifyPromotion_(book, [target]), true, name);
    }
    const col = env.context.guestProjectedColumn_(6, member) - 1;
    formulas[0][col] = '=COUNTIF(Z4:Z,"x")'; values[0][col] = 0;
    assert.equal(env.context.guestVerifyPromotion_(book, [target]), false, name);
  }
});

test('eleven runs across two seasons transfer into ordinary member cells exactly once', () => {
  const { env, guestId } = seeded();
  const before = [25, 26].map(id => seasonState(env, id));
  const result = preview(env, guestId);
  assert.equal(result.confirmedRuns, 11, JSON.stringify(result));
  assert.deepEqual(result.seasons.map(s => s.runs), [3, 8]);
  assert.ok(result.changes.every(c => c.totalBefore === c.totalAfter && c.actualKmBefore === c.actualKmAfter));
  const request = promotion(guestId, result), saved = env.post(request);
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  assert.equal(saved.confirmedRuns, 11);
  assert.equal(saved.sheetRevision, seasonState(env, 26).sheetRevision);
  assert.deepEqual(env.post(request), saved);
  for (const old of before) {
    const state = seasonState(env, old.seasonSheetId), sheet = env.spreadsheet.getSheetById(old.seasonSheetId);
    const member = state.roster.find(m => m.name === 'Rene');
    for (const run of state.runs) {
      const prior = old.runs.find(r => r.runId === run.runId);
      assert.equal(run.plusOnes, prior.plusOnes - 1);
      assert.equal(run.actualKm, prior.actualKm);
      assert.equal(run.unnamedGuests, 1);
      assert.deepEqual(run.namedGuestIds, []);
      assert.equal(sheet.values[run.rowIndex - 1][member.colIndex - 1], 'x');
      assert.equal(run.attendees.length + run.plusOnes, prior.attendees.length + prior.plusOnes);
    }
  }
  const history = env.post({ action: 'getGuestHistory', guestId });
  assert.ok(history.attendance.every(a => a.classification === 'transferred'));
  assert.equal(history.guest.confirmedRuns, 11);
  assert.equal(seasonState(env, 26).lifetimeTotals.find(t => t.name === 'Rene').runs, 11);
});

test('v2 first, middle and last insertions stay inside the old member band', () => {
  for (const name of ['Aaron', 'Sam', 'Zoe']) {
    const env = createEnvironment({ grid: grid(1), sheetName: '2026' });
    const ctx = env.context.readContext_(env.sheet, '2026'); ctx.sheetId = env.sheet.sheetId;
    const plan = env.context.guestPlan_(), member = env.context.guestPlanMember_(plan, ctx, name);
    assert.ok(member.insertion.insertBefore > ctx.bounds.firstMemberCol, name);
    assert.ok(member.insertion.insertBefore <= ctx.band.at(-1).colIndex, name);
    assert.ok(plan.requests.some(r => r.copyPaste?.pasteType === 'PASTE_FORMULA'), name);
  }
});

test('promotion after ten runs leaves the next member attendance as run eleven', () => {
  const { env, guestId } = seeded({ current: 7, historical: 3 });
  assert.equal(env.post(promotion(guestId, preview(env, guestId))).status, 'completed');
  let state = seasonState(env, 26);
  const added = env.post(mutation('addRun', { spreadsheetId: state.spreadsheetId, seasonSheetId: 26,
    date: 'Fri, 20-Feb', meet: 'Beach', run: 'Soft Sand', approxKm: 7.5, baseRevision: state.sheetRevision }));
  assert.equal(added.status, 'completed');
  state = seasonState(env, 26);
  const run = state.runs.find(r => r.runId === added.runId);
  assert.equal(env.post(mutation('submitAttendance', { spreadsheetId: state.spreadsheetId, seasonSheetId: 26,
    runId: run.runId, rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run, attendees: ['Rene'],
    namedGuestIds: [], unnamedGuests: 0, actualKm: 7.5, mode: 'overwrite', baseRevision: state.sheetRevision })).status, 'completed');
  assert.equal(seasonState(env, 26).lifetimeTotals.find(t => t.name === 'Rene').runs, 11);
});

test('historical-only guests gain an active-season member column without new attendance', () => {
  const { env, guestId } = seeded({ current: 0 });
  const result = preview(env, guestId);
  assert.deepEqual(result.seasons.map(s => s.runs), [3, 0]);
  assert.equal(env.post(promotion(guestId, result)).status, 'completed');
  const state = seasonState(env, 26);
  assert.equal(state.roster.filter(m => m.name === 'Rene').length, 1);
  assert.equal(state.runs.length, 0);
  assert.equal(state.lifetimeTotals.find(t => t.name === 'Rene').runs, 3);
});

test('explicit linking preserves existing identity and rejects an already attended target', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  const before = env.allSheets.map(s => structuredClone(s.values));
  assert.equal(preview(env, guestId, 'Toby').conflict.reason, 'member_exists');
  assert.equal(preview(env, guestId, 'Rene', 'link').conflict.reason, 'member_missing');
  assert.equal(preview(env, guestId, 'Col', 'link').conflict.reason, 'member_already_attended');
  assert.equal(preview(env, guestId, 'toby', 'link').conflict.reason, 'member_identity_ambiguous');
  assert.deepEqual(env.allSheets.map(s => s.values), before);
  assert.equal(env.post(promotion(guestId, preview(env, guestId, 'Toby', 'link'))).status, 'completed');
  assert.equal(seasonState(env, 26).roster.length, 2);
  assert.equal(seasonState(env, 26).lifetimeTotals.find(t => t.name === 'Toby').runs, 2);
});

test('changed history, labels, notes, formulas or target choice invalidate the preview', () => {
  const cases = {
    distance: env => { env.sheet.values[3][4] = 9; },
    label: env => { env.sheet.values[3][2] = 'Trail'; },
    note: env => { env.sheet.notes['3,5'] = 'Manual correction'; },
    formula: env => { env.sheet.values[0][5] = '=COUNTIF(F4:F30,"x")'; },
    target: (_, request) => { request.memberName = 'Zoe'; },
  };
  for (const [kind, change] of Object.entries(cases)) {
    const { env, guestId } = seeded({ current: 1, historical: 1 });
    let request = promotion(guestId, preview(env, guestId));
    change(env, request);
    request.requestDigest = crypto.createHash('sha256').update(GuestOps.canonicalRequest(request)).digest('hex');
    const before = env.allSheets.map(s => structuredClone(s.values)), count = env.batches.length;
    assert.equal(env.post(request).conflict.reason, 'promotion_changed', kind);
    assert.deepEqual(env.allSheets.map(s => s.values), before, kind);
    assert.equal(env.batches.length, count, kind);
  }
});

test('missing history metadata, insufficient allocation and formula targets cause no mutation', () => {
  const cases = {
    metadata: [env => { env.sheet.metadata.shift(); }, 'run_missing'],
    allocation: [env => { env.sheet.values[3][7] = 0; }, 'invalid_allocation'],
    formula: [env => { env.sheet.values[3][7] = '=2'; }, 'invalid_allocation'],
    duplicate: [env => {
      const table = env.allSheets.find(s => s.name === '_FCTC_GuestAttendance');
      table.values.push(table.values[1].slice());
    }, 'duplicate_attendance_identity'],
  };
  for (const [kind, [change, reason]] of Object.entries(cases)) {
    const { env, guestId } = seeded({ current: 1, historical: 1 });
    change(env);
    const before = env.allSheets.map(s => structuredClone(s.values)), count = env.batches.length;
    assert.equal(preview(env, guestId).conflict.reason, reason, kind);
    assert.deepEqual(env.allSheets.map(s => s.values), before, kind);
    assert.equal(env.batches.length, count, kind);
  }
});

test('lost promotion response, restart and a second organiser cannot repeat a transfer', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  const result = preview(env, guestId), request = promotion(guestId, result), other = promotion(guestId, result);
  const api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
  let calls = 0;
  api.batchUpdate = (batch, id) => { if (++calls === 2) env.failNextBatch('after'); return original(batch, id); };
  assert.equal(env.post(request).conflict.reason, 'pending_verification');
  assert.equal(env.post(other).conflict.reason, 'pending_verification');
  const restarted = env.restart();
  assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'completed');
  assert.equal(restarted.post(request).status, 'completed');
  assert.equal(restarted.post(other).conflict.reason, 'guest_promoted');
  assert.equal(seasonState(restarted, 26).roster.filter(m => m.name === 'Rene').length, 1);
  assert.equal(seasonState(restarted, 26).runs[0].plusOnes, 1);
});

test('postcondition failures on original marks, notes and formulas retain the write fence', () => {
  for (const change of [
    env => { env.sheet.values[3][5] = ''; },
    env => { env.sheet.notes['3,5'] = 'Unexpected edit'; },
    env => { env.sheet.values[3][9] = '=SUM(F4:H4)+I4'; },
  ]) {
    const { env, guestId } = seeded({ current: 1, historical: 1 });
    const request = promotion(guestId, preview(env, guestId)), api = env.context.Sheets.Spreadsheets, original = api.batchUpdate;
    let calls = 0;
    api.batchUpdate = (batch, id) => { const result = original(batch, id); if (++calls === 2) change(env); return result; };
    assert.equal(env.post(request).conflict.reason, 'pending_verification');
    const restarted = env.restart();
    assert.equal(restarted.post({ action: 'getOperationStatus', operationId: request.operationId }).operation.status, 'pending');
    assert.equal(seasonState(restarted, 26).pendingOperationId, request.operationId);
  }
});

test('first, middle and last promotions preserve all existing member notes and marks', () => {
  for (const name of ['Aaron', 'Sam', 'Zoe']) {
    const { env, guestId } = seeded({ current: 1, historical: 1 });
    for (const id of [25, 26]) {
      const sheet = env.spreadsheet.getSheetById(id);
      sheet.notes['3,5'] = 'Col note'; sheet.notes['3,6'] = 'Toby note';
    }
    assert.equal(env.post(promotion(guestId, preview(env, guestId, name))).status, 'completed', name);
    for (const id of [25, 26]) {
      const state = seasonState(env, id), sheet = env.spreadsheet.getSheetById(id);
      for (const [oldName, mark] of [['Col', 'x'], ['Toby', '-']]) {
        const col = state.roster.find(m => m.name === oldName).colIndex - 1;
        assert.equal(sheet.values[3][col], mark, name);
        assert.equal(sheet.notes[`3,${col}`], oldName + ' note', name);
      }
    }
  }
});

test('historical summary references use actual target columns in differing season rosters', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  // A direct historical summary row appears in the current season only.
  env.sheet.values[0][5] = "='2025'!F2";
  env.sheet.values[0][6] = "='2025'!G2";
  const prior = env.spreadsheet.getSheetById(25);
  prior.values.forEach(row => row.splice(6, 0, ''));
  prior.values[2][6] = 'Priya';
  prior.values[0][6] = '=COUNTIF(G4:G20,"x")';
  prior.values[1][6] = '=SUMIF(G4:G20,"x",E4:E20)';
  const result = preview(env, guestId), saved = env.post(promotion(guestId, result));
  assert.equal(saved.status, 'completed', JSON.stringify(saved));
  const currentMember = seasonState(env, 26).roster.find(m => m.name === 'Rene');
  const historicalMember = seasonState(env, 25).roster.find(m => m.name === 'Rene');
  assert.notEqual(currentMember.colIndex, historicalMember.colIndex);
  assert.equal(env.sheet.values[0][currentMember.colIndex - 1], "='2025'!H2");
});

test('unsupported historical formula semantics fail before promotion mutates any cell', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  env.sheet.values[0][5] = "=SUM('2025'!F2,'2025'!F3)";
  const before = env.allSheets.map(s => structuredClone(s.values)), count = env.batches.length;
  assert.equal(preview(env, guestId).conflict.reason, 'unsafe_member_formula');
  assert.deepEqual(env.allSheets.map(s => s.values), before);
  assert.equal(env.batches.length, count);
});

test('first-name relocation preserves existing history references when rosters differ', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  const prior = env.spreadsheet.getSheetById(25);
  prior.values.forEach(row => row.splice(5, 0, ''));
  prior.values[2][5] = 'Aaron';
  prior.values[0][5] = '=COUNTIF(F4:F20,"x")';
  prior.values[1][5] = '=SUMIF(F4:F20,"x",E4:E20)';
  env.sheet.values[0][5] = "='2025'!G2";
  env.sheet.values[0][6] = "='2025'!H2";
  assert.equal(env.post(promotion(guestId, preview(env, guestId, 'Bob'))).status, 'completed');
  const state = seasonState(env, 26);
  assert.equal(env.sheet.values[0][state.roster.find(m => m.name === 'Col').colIndex - 1], "='2025'!H2");
  assert.equal(env.sheet.values[0][state.roster.find(m => m.name === 'Toby').colIndex - 1], "='2025'!I2");
  assert.equal(env.sheet.values[0][state.roster.find(m => m.name === 'Bob').colIndex - 1], "='2025'!G2");
});

test('last-name relocation repairs dependent seasons without adding an unneeded roster entry', () => {
  const { env, guestId } = seeded({ current: 1, historical: 1 });
  const dependent = new env.sheet.constructor('2027', grid(0), 33);
  dependent.values[0][5] = "='2025'!F2";
  dependent.values[0][6] = "='2025'!G2";
  env.allSheets.push(dependent);
  env.allSheets.find(s => s.name === '_FCTC_Guests').values[0][2] = '[25,26,33]';
  env.sheet.values[0][5] = "='2025'!F2";
  env.sheet.values[0][6] = "='2025'!G2";
  const result = preview(env, guestId, 'Zoe');
  assert.ok(result.previewToken, JSON.stringify(result));
  const request = promotion(guestId, result);
  assert.equal(env.post(request).status, 'completed');
  assert.equal(seasonState(env, 33).roster.some(m => m.name === 'Zoe'), false);
  assert.equal(dependent.values[0][6], "='2025'!G2");
  const writes = env.batches.at(-1).requests.filter(r => r.updateCells?.start.sheetId === 33);
  assert.ok(writes.some(r => r.updateCells.start.columnIndex === 6 &&
    r.updateCells.rows[0].values[0].userEnteredValue.formulaValue === "='2025'!G2"));
  // A wrong A1 reference has the same formula shape, so exact guards must catch it.
  const saved = env.context.guestReadOperation_(env.spreadsheet, request.operationId);
  dependent.values[0][6] = "='2025'!H2";
  assert.equal(env.context.guestVerifyTargets_(env.spreadsheet, saved.targetState), false);
});
