/**
 * Web App tests — `doPost` routing, auth, conflicts, writes and response shapes (U2).
 *
 * `Code.gs` runs for real here, inside the fake Apps Script runtime in
 * `support/fakeAppsScript.js`, against a grid parsed from the actual season CSVs.
 * That means these are not shape assertions over hand-written example objects: each
 * response below was produced by the same code path a phone will hit, and every
 * write it performed is inspectable.
 *
 * Two things get asserted everywhere:
 *   1. **The frozen contract** — `docs/plans/packets/_conventions.md`. `assertOk` /
 *      `assertError` police the envelope; the per-action tests police the bodies.
 *   2. **The sheet-safety invariant** — `assertWritesStayInBand` re-derives the band
 *      from the CSV and refuses any recorded write that fell outside it. It runs on
 *      every mutating test, so a future refactor cannot quietly widen the blast
 *      radius.
 *
 * Out of scope (no formula engine in the fake — see `test/smoke.md`): whether the
 * sheet's own COUNTA/SUM ranges widen when `addMember` inserts a column, and whether
 * the copied formulas in an `addRun` row recalculate.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const SheetOps = require('../SheetOps.js');
const { createEnvironment } = require('./support/fakeAppsScript.js');
const { SEASON_YEARS, SEASON_FACTS, seasonGrid } = require('./support/seasons.js');

/**
 * A fresh API environment over a season fixture.
 *
 * @param {number} year
 * @param {!Object=} options Passed through to `createEnvironment`.
 * @return {!Object}
 */
function api(year, options) {
  return createEnvironment(
    Object.assign({ grid: seasonGrid(year), sheetName: String(year) }, options || {})
  );
}

/**
 * Assert the success envelope and return the response.
 *
 * @param {!Object} response
 * @return {!Object}
 */
function assertOk(response) {
  assert.equal(response.ok, true, `expected ok:true, got ${JSON.stringify(response)}`);
  assert.ok(!('error' in response), 'a successful response carries no error code');
  return response;
}

/**
 * Assert the error envelope — exactly `{ ok:false, error, message }`.
 *
 * @param {!Object} response
 * @param {string} code
 * @return {!Object}
 */
function assertError(response, code) {
  assert.deepEqual(Object.keys(response).sort(), ['error', 'message', 'ok']);
  assert.equal(response.ok, false);
  assert.equal(response.error, code, `expected error ${code}, got ${JSON.stringify(response)}`);
  assert.equal(typeof response.message, 'string');
  assert.ok(response.message.length > 0, 'an error must explain itself');
  return response;
}

/**
 * Validate a `getState` body against the frozen contract, key by key.
 *
 * Used for both the `getState` response itself (where the envelope's `ok` rides
 * alongside the body) and the `state` nested inside a conflict, which is why the
 * envelope key is discounted rather than forbidden.
 *
 * @param {!Object} state
 * @param {number} year
 */
function assertStateShape(state, year) {
  assert.deepEqual(
    Object.keys(state).filter((key) => key !== 'ok').sort(),
    ['roster', 'runs', 'seasonYear', 'sheetRevision'],
    'getState body must carry exactly the documented keys'
  );
  assert.equal(state.seasonYear, year);
  assert.match(state.sheetRevision, /^[0-9a-f]{16}$/);

  assert.ok(Array.isArray(state.roster));
  for (const entry of state.roster) {
    assert.deepEqual(Object.keys(entry).sort(), ['colIndex', 'name']);
    assert.equal(typeof entry.name, 'string');
    assert.equal(typeof entry.colIndex, 'number');
  }

  assert.ok(Array.isArray(state.runs));
  for (const run of state.runs) {
    assert.deepEqual(Object.keys(run).sort(), [
      'actualKm',
      'approxKm',
      'attendees',
      'date',
      'meet',
      'plusOnes',
      'rowIndex',
      'run',
    ]);
    assert.equal(typeof run.rowIndex, 'number');
    assert.equal(typeof run.date, 'string');
    assert.equal(typeof run.meet, 'string');
    assert.equal(typeof run.run, 'string');
    assert.ok(run.approxKm === null || typeof run.approxKm === 'number');
    assert.ok(run.actualKm === null || typeof run.actualKm === 'number');
    assert.ok(Array.isArray(run.attendees));
    assert.equal(typeof run.plusOnes, 'number');
  }
}

/**
 * The sheet-safety invariant, checked against the recorded writes.
 *
 * @param {!Object} env From `api()`.
 * @param {number} year
 * @param {{allowHeaderCell?: boolean, allowInsertedRow?: number}=} grants
 *     `allowHeaderCell` permits the single member-band header write `addMember`
 *     makes; `allowInsertedRow` permits writes anywhere on a row `addRun` inserted.
 */
function assertWritesStayInBand(env, year, grants) {
  const facts = SEASON_FACTS[year];
  const allowances = grants || {};
  for (const write of env.writes()) {
    if (write.kind !== 'setValues' && write.kind !== 'copyTo') continue;
    const row = write.kind === 'copyTo' ? write.toRow : write.row;
    const col = write.kind === 'copyTo' ? write.toCol : write.col;
    const width = write.numCols;

    if (allowances.allowInsertedRow && row === allowances.allowInsertedRow) continue;
    if (
      allowances.allowHeaderCell &&
      row === facts.headerRow &&
      width === 1 &&
      col > facts.actualKmCol &&
      col <= facts.plusOnesCol
    ) {
      continue;
    }

    assert.ok(row > facts.headerRow, `write landed on row ${row}, at or above the header`);
    assert.ok(
      col >= facts.actualKmCol && col + width - 1 <= facts.plusOnesCol,
      `write spanned columns ${col}-${col + width - 1}, outside Actual kms..+1's`
    );
  }
}

/** The 2026 Invasion Day 10k — a run that shares its date with another run. */
function invasionDay10k(env) {
  const state = assertOk(env.post({ action: 'getState' }));
  const run = state.runs.find(
    (r) => r.date === SEASON_FACTS[2026].sharedDate && /^10k/.test(r.run)
  );
  assert.ok(run, 'expected the Invasion Day 10k in the 2026 fixture');
  return { state, run };
}

test.describe('auth and routing', () => {
  test.it('rejects a wrong secret before doing anything else', () => {
    const env = api(2026);
    const response = env.raw(JSON.stringify({ secret: 'nope', action: 'getState' }));
    assertError(response, 'bad_secret');
    assert.equal(env.writes().length, 0);
  });

  test.it('rejects a missing secret, and a secret of the wrong length', () => {
    const env = api(2026);
    assertError(env.raw(JSON.stringify({ action: 'getState' })), 'bad_secret');
    assertError(
      env.raw(JSON.stringify({ secret: 'test-secretttt', action: 'getState' })),
      'bad_secret'
    );
    assertError(env.raw(JSON.stringify({ secret: '', action: 'getState' })), 'bad_secret');
  });

  test.it('refuses everyone when SHARED_SECRET is unset', () => {
    const env = createEnvironment({
      grid: seasonGrid(2026),
      sheetName: '2026',
      properties: { SHARED_SECRET: undefined },
    });
    // Property present-but-empty and property absent must behave the same.
    const unset = createEnvironment({ grid: seasonGrid(2026), sheetName: '2026', secret: '' });
    assertError(unset.raw(JSON.stringify({ secret: '', action: 'getState' })), 'bad_secret');
    assertError(env.raw(JSON.stringify({ action: 'getState' })), 'bad_secret');
  });

  test.it('rejects an unknown action once the secret checks out', () => {
    const env = api(2026);
    const response = assertError(env.post({ action: 'deleteEverything' }), 'unknown_action');
    assert.match(response.message, /getState/);
  });

  test.it('rejects a body that is not a JSON object', () => {
    const env = api(2026);
    assertError(env.raw('not json at all'), 'bad_payload');
    assertError(env.raw('[]'), 'bad_secret'); // an array is an object, but has no secret
    assert.equal(JSON.parse(env.context.doPost({}).getContent()).error, 'bad_payload');
  });

  test.it('answers GET with a well-formed refusal, not an HTML stack trace', () => {
    const env = api(2026);
    const response = JSON.parse(env.context.doGet().getContent());
    assert.equal(response.ok, false);
    assert.equal(response.error, 'method_not_allowed');
  });

  test.it('reports an unreadable or unconfigured season tab', () => {
    const missing = createEnvironment({
      grid: seasonGrid(2026),
      sheetName: '2026',
      properties: { SEASON_SHEET_NAME: '2027' },
    });
    assertError(missing.post({ action: 'getState' }), 'sheet_unreadable');

    const unset = createEnvironment({
      grid: seasonGrid(2026),
      sheetName: '2026',
      properties: { SEASON_SHEET_NAME: '' },
    });
    assertError(unset.post({ action: 'getState' }), 'sheet_unreadable');

    const shapeless = createEnvironment({
      grid: [['Notes:'], ['nothing that looks like a header']],
      sheetName: '2026',
    });
    assertError(shapeless.post({ action: 'getState' }), 'sheet_unreadable');
  });
});

test.describe('getState', () => {
  for (const year of SEASON_YEARS) {
    test.it(`serves the ${year} season in the documented shape`, () => {
      const env = api(year);
      const state = assertOk(env.post({ action: 'getState' }));
      assertStateShape(state, year);

      const facts = SEASON_FACTS[year];
      assert.equal(state.roster.length, facts.memberCount);
      assert.deepEqual(state.roster.map((m) => m.name), facts.members);
      assert.equal(state.roster[0].colIndex, facts.firstMemberCol);
      assert.equal(state.runs[0].rowIndex, facts.firstRunRow);
      assert.equal(state.runs[0].date, facts.firstRun.date);
      assert.equal(env.writes().length, 0, 'getState must not write');
    });
  }

  test.it('agrees with SheetOps run-for-run (the shell adds no interpretation)', () => {
    for (const year of SEASON_YEARS) {
      const env = api(year);
      const state = assertOk(env.post({ action: 'getState' }));
      const grid = seasonGrid(year);
      const headerRow = SheetOps.findHeaderRow(grid);
      assert.deepEqual(state.runs, SheetOps.listRuns(grid, headerRow));
      assert.deepEqual(state.roster, SheetOps.memberBand(grid, headerRow));
      assert.equal(state.sheetRevision, SheetOps.revisionHash(grid, headerRow));
    }
  });

  test.it('serves both runs that share the Invasion Day date', () => {
    for (const year of SEASON_YEARS) {
      const env = api(year);
      const state = assertOk(env.post({ action: 'getState' }));
      const shared = state.runs.filter((r) => r.date === SEASON_FACTS[year].sharedDate);
      assert.equal(shared.length, 2);
      assert.notEqual(shared[0].rowIndex, shared[1].rowIndex);
      assert.notEqual(shared[0].run, shared[1].run);
    }
  });

  test.it('takes seasonYear from the configured tab name', () => {
    const env = createEnvironment({ grid: seasonGrid(2026), sheetName: '2026' });
    assert.equal(assertOk(env.post({ action: 'getState' })).seasonYear, 2026);
    const odd = createEnvironment({ grid: seasonGrid(2026), sheetName: 'Season 2027' });
    assert.equal(assertOk(odd.post({ action: 'getState' })).seasonYear, 2027);
  });
});

test.describe('submitAttendance', () => {
  test.it('writes a merge and reports how many cells it touched', () => {
    const env = api(2026);
    const { state, run } = invasionDay10k(env);
    const before = run.attendees.slice();
    assert.ok(before.length > 0, 'fixture precondition: the 10k has attendees');

    const response = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: run.plusOnes,
        actualKm: run.actualKm,
        mode: 'merge',
        baseRevision: state.sheetRevision,
      })
    );
    assert.deepEqual(Object.keys(response).sort(), ['ok', 'sheetRevision', 'written']);
    assert.equal(typeof response.written, 'number');
    assert.ok(response.written >= SEASON_FACTS[2026].memberCount);
    assert.notEqual(response.sheetRevision, state.sheetRevision);

    const after = assertOk(env.post({ action: 'getState' })).runs.find(
      (r) => r.rowIndex === run.rowIndex
    );
    assert.deepEqual(after.attendees, before.concat(['Col']).sort((a, b) =>
      SheetOps.compareNames(a, b)
    ));
    assertWritesStayInBand(env, 2026);
  });

  test.it('overwrite clears attendees the submission omits', () => {
    const env = api(2026);
    const { state, run } = invasionDay10k(env);
    assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: 0,
        actualKm: null,
        mode: 'overwrite',
        baseRevision: state.sheetRevision,
      })
    );
    const after = assertOk(env.post({ action: 'getState' })).runs.find(
      (r) => r.rowIndex === run.rowIndex
    );
    assert.deepEqual(after.attendees, ['Col']);
    assert.equal(after.plusOnes, 0);
    assertWritesStayInBand(env, 2026);
  });

  test.it('is idempotent — the retry queue can send the same payload twice', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    const payload = {
      action: 'submitAttendance',
      rowIndex: run.rowIndex,
      expectedDate: run.date,
      expectedRun: run.run,
      attendees: ['Col', 'Alex 👑'],
      plusOnes: 1,
      actualKm: 10,
      mode: 'overwrite',
    };
    assertOk(env.post(payload));
    const afterFirst = assertOk(env.post({ action: 'getState' }));
    assertOk(env.post(payload));
    const afterSecond = assertOk(env.post({ action: 'getState' }));
    assert.equal(afterSecond.sheetRevision, afterFirst.sheetRevision);
    assert.deepEqual(afterSecond.runs, afterFirst.runs);
  });

  test.it('writes Actual kms and +1\'s, and leaves them alone when unstated', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    const base = { action: 'submitAttendance', rowIndex: run.rowIndex,
      expectedDate: run.date, expectedRun: run.run, attendees: [], mode: 'merge' };

    assertOk(env.post(Object.assign({}, base, { plusOnes: 3, actualKm: 10.42 })));
    let after = assertOk(env.post({ action: 'getState' })).runs.find(
      (r) => r.rowIndex === run.rowIndex
    );
    assert.equal(after.plusOnes, 3);
    assert.equal(after.actualKm, 10.42);

    // null means "the phone had nothing to say", not "set it to zero/blank".
    assertOk(env.post(Object.assign({}, base, { plusOnes: null, actualKm: null })));
    after = assertOk(env.post({ action: 'getState' })).runs.find(
      (r) => r.rowIndex === run.rowIndex
    );
    assert.equal(after.plusOnes, 3);
    assert.equal(after.actualKm, 10.42);
    assertWritesStayInBand(env, 2026);
  });

  test.it('targets the right row when two runs share a date', () => {
    const env = api(2026);
    const state = assertOk(env.post({ action: 'getState' }));
    const [half, tenK] = state.runs.filter(
      (r) => r.date === SEASON_FACTS[2026].sharedDate
    );
    assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: tenK.rowIndex,
        expectedDate: tenK.date,
        expectedRun: tenK.run,
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'overwrite',
        baseRevision: state.sheetRevision,
      })
    );
    const after = assertOk(env.post({ action: 'getState' }));
    const halfAfter = after.runs.find((r) => r.rowIndex === half.rowIndex);
    assert.deepEqual(halfAfter.attendees, half.attendees, 'the other run must be untouched');
    assert.deepEqual(
      after.runs.find((r) => r.rowIndex === tenK.rowIndex).attendees,
      ['Col']
    );
  });

  test.it('conflicts with fresh state when the row identity moved', () => {
    const env = api(2026);
    const { state, run } = invasionDay10k(env);
    const response = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: 'Soft Sand', // this row is the Invasion Day 10k, not Soft Sand
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'merge',
        baseRevision: state.sheetRevision,
      })
    );
    assert.equal(response.conflict.reason, 'row_mismatch');
    assertStateShape(response.conflict.state, 2026);
    assert.ok(!('written' in response), 'a conflict is not a write');
    assert.equal(env.writes().length, 0, 'a conflict must not touch the sheet');
  });

  test.it('conflicts when the revision is stale, and hands back the truth', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    const response = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'merge',
        baseRevision: '0000000000000000',
      })
    );
    assert.equal(response.conflict.reason, 'stale_revision');
    assertStateShape(response.conflict.state, 2026);
    assert.equal(env.writes().length, 0);
    // The state it returns is usable as the next attempt's baseRevision.
    const retry = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'merge',
        baseRevision: response.conflict.state.sheetRevision,
      })
    );
    assert.ok(retry.written > 0);
  });

  test.it('conflicts after someone else edits the sheet between get and submit', () => {
    const env = api(2026);
    const { state, run } = invasionDay10k(env);
    // Colin ticks a box in the browser.
    const facts = SEASON_FACTS[2026];
    env.sheet.getRange(run.rowIndex, facts.firstMemberCol).setValue('x');
    env.sheet.writes.length = 0;

    const response = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'merge',
        baseRevision: state.sheetRevision,
      })
    );
    assert.equal(response.conflict.reason, 'stale_revision');
    assert.ok(
      response.conflict.state.runs
        .find((r) => r.rowIndex === run.rowIndex)
        .attendees.includes(facts.members[0]),
      'the fresh state must show the edit that caused the conflict'
    );
    assert.equal(env.writes().length, 0);
  });

  test.it('accepts a submission with no baseRevision (first-run / recovered app)', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: run.rowIndex,
        expectedDate: run.date,
        expectedRun: run.run,
        attendees: ['Col'],
        plusOnes: 0,
        mode: 'merge',
      })
    );
  });

  test.it('rejects a payload the sheet cannot honour', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    const good = {
      action: 'submitAttendance',
      rowIndex: run.rowIndex,
      expectedDate: run.date,
      expectedRun: run.run,
      attendees: ['Col'],
      plusOnes: 0,
      mode: 'merge',
    };
    assertError(
      env.post(Object.assign({}, good, { attendees: ['Nigel'] })),
      'bad_payload'
    );
    assertError(env.post(Object.assign({}, good, { attendees: 'Col' })), 'bad_payload');
    assertError(env.post(Object.assign({}, good, { mode: 'clobber' })), 'bad_payload');
    assertError(env.post(Object.assign({}, good, { rowIndex: 1 })), 'bad_payload');
    assertError(env.post(Object.assign({}, good, { rowIndex: 'abc' })), 'bad_payload');
    assert.equal(env.writes().length, 0, 'a rejected payload writes nothing');
  });

  test.it('treats a vanished run row as a conflict, not a crash', () => {
    const env = api(2026);
    const state = assertOk(env.post({ action: 'getState' }));
    const last = state.runs[state.runs.length - 1];
    const response = assertOk(
      env.post({
        action: 'submitAttendance',
        rowIndex: last.rowIndex + 50, // below every run row
        expectedDate: last.date,
        expectedRun: last.run,
        attendees: [],
        plusOnes: 0,
        mode: 'merge',
      })
    );
    assert.equal(response.conflict.reason, 'row_mismatch');
  });

  for (const year of SEASON_YEARS) {
    test.it(`writes only inside the ${year} member band`, () => {
      const env = api(year);
      const state = assertOk(env.post({ action: 'getState' }));
      const run = state.runs[0];
      assertOk(
        env.post({
          action: 'submitAttendance',
          rowIndex: run.rowIndex,
          expectedDate: run.date,
          expectedRun: run.run,
          attendees: SEASON_FACTS[year].members.slice(0, 3),
          plusOnes: 2,
          actualKm: 7.5,
          mode: 'overwrite',
          baseRevision: state.sheetRevision,
        })
      );
      assertWritesStayInBand(env, year);
      const facts = SEASON_FACTS[year];
      // The derived columns right of +1's were never addressed.
      for (const write of env.writes()) {
        assert.ok(write.col + write.numCols - 1 <= facts.plusOnesCol);
      }
    });
  }
});

test.describe('addMember', () => {
  test.it('inserts Alex B between Alex 👑 and Alex Kr in the 2025 band', () => {
    const env = api(2025);
    const before = assertOk(env.post({ action: 'getState' }));
    const response = assertOk(env.post({ action: 'addMember', name: 'Alex B' }));
    assert.deepEqual(Object.keys(response).sort(), ['ok', 'roster', 'sheetRevision']);

    const names = response.roster.map((m) => m.name);
    assert.equal(names.length, before.roster.length + 1);
    assert.deepEqual(names.slice(2, 5), ['Alex 👑', 'Alex B', 'Alex Kr']);
    // Column indices are re-read from the sheet, so they stay contiguous.
    response.roster.forEach((member, i) => {
      assert.equal(member.colIndex, SEASON_FACTS[2025].firstMemberCol + i);
    });
    assertWritesStayInBand(env, 2025, { allowHeaderCell: true });
  });

  test.it('inserts a prefix name after its shorter twin (Dan B after Dan)', () => {
    const env = api(2025);
    const roster = assertOk(env.post({ action: 'addMember', name: 'Dan B' })).roster;
    const names = roster.map((m) => m.name);
    assert.equal(names[names.indexOf('Dan') + 1], 'Dan B');
    assert.equal(names[names.indexOf('Dan B') + 1], 'Darren');
  });

  test.it('appends a last-alphabetically member inside the band, before +1\'s', () => {
    const env = api(2026);
    const roster = assertOk(env.post({ action: 'addMember', name: 'Zoe' })).roster;
    assert.equal(roster[roster.length - 1].name, 'Zoe');
    // The +1's column moved right by one; the new member sits just inside it.
    assert.equal(roster[roster.length - 1].colIndex, SEASON_FACTS[2026].plusOnesCol);
  });

  test.it('turns 2025 into the 2026 roster by adding the three joiners', () => {
    const env = api(2025);
    for (const name of ['Alex B', 'Dan B', 'Deano']) {
      assertOk(env.post({ action: 'addMember', name }));
    }
    const roster = assertOk(env.post({ action: 'getState' })).roster;
    assert.deepEqual(roster.map((m) => m.name), SEASON_FACTS[2026].members);
  });

  test.it('rejects a duplicate case- and emoji-insensitively', () => {
    const env = api(2026);
    for (const name of ['Col', 'col', '  COL  ', 'Alex']) {
      const response = assertError(
        env.post({ action: 'addMember', name }),
        'duplicate_member'
      );
      assert.match(response.message, /already on the roster/);
    }
    assert.equal(env.writes().length, 0);
  });

  test.it('rejects a name that is empty or has nothing to sort on', () => {
    const env = api(2026);
    assertError(env.post({ action: 'addMember', name: '' }), 'bad_payload');
    assertError(env.post({ action: 'addMember' }), 'bad_payload');
    assertError(env.post({ action: 'addMember', name: '   ' }), 'bad_payload');
    assertError(env.post({ action: 'addMember', name: '👑' }), 'bad_payload');
    assert.equal(env.writes().length, 0);
  });

  test.it('leaves every existing member on their own (shifted) column', () => {
    const env = api(2026);
    const before = assertOk(env.post({ action: 'getState' }));
    const after = assertOk(env.post({ action: 'addMember', name: 'Bruce' }));
    const insertedAt = after.roster.findIndex((m) => m.name === 'Bruce');
    before.roster.forEach((member, i) => {
      const now = after.roster.find((m) => m.name === member.name);
      assert.ok(now, `${member.name} disappeared`);
      assert.equal(now.colIndex, i < insertedAt ? member.colIndex : member.colIndex + 1);
    });
    // Attendance travelled with the columns.
    const beforeRun = before.runs[0];
    const afterRun = assertOk(env.post({ action: 'getState' })).runs.find(
      (r) => r.rowIndex === beforeRun.rowIndex
    );
    assert.deepEqual(afterRun.attendees, beforeRun.attendees);
  });
});

test.describe('addRun', () => {
  test.it('inserts a run in date order and returns the new run list', () => {
    const env = api(2026);
    const before = assertOk(env.post({ action: 'getState' }));
    const response = assertOk(
      env.post({
        action: 'addRun',
        date: 'Sat, 24-Jan',
        meet: 'Il Lido',
        run: 'Parkrun',
        approxKm: 5,
      })
    );
    assert.deepEqual(Object.keys(response).sort(), ['ok', 'runs', 'sheetRevision']);
    assert.equal(response.runs.length, before.runs.length + 1);

    const index = response.runs.findIndex((r) => r.run === 'Parkrun');
    assert.equal(response.runs[index - 1].date, 'Fri, 23-Jan');
    assert.equal(response.runs[index + 1].date, SEASON_FACTS[2026].sharedDate);
    assert.equal(response.runs[index].meet, 'Il Lido');
    assert.equal(response.runs[index].approxKm, 5);
    assert.deepEqual(response.runs[index].attendees, []);
    assertWritesStayInBand(env, 2026, {
      allowInsertedRow: response.runs[index].rowIndex,
    });
  });

  test.it('lands a second run on an existing date BELOW the first', () => {
    const env = api(2026);
    const response = assertOk(
      env.post({
        action: 'addRun',
        date: SEASON_FACTS[2026].sharedDate,
        meet: 'Filament',
        run: '5k - Invasion Day',
        approxKm: 5,
      })
    );
    const sameDate = response.runs.filter((r) => r.date === SEASON_FACTS[2026].sharedDate);
    assert.equal(sameDate.length, 3);
    assert.equal(sameDate[2].run, '5k - Invasion Day');
    assert.ok(sameDate[2].rowIndex > sameDate[1].rowIndex);
  });

  test.it('appends a run dated after the whole season', () => {
    const env = api(2026);
    const before = assertOk(env.post({ action: 'getState' }));
    const response = assertOk(
      env.post({ action: 'addRun', date: 'Thu, 31-Dec', meet: 'Filament', run: 'NYE', approxKm: 8 })
    );
    const last = response.runs[response.runs.length - 1];
    assert.equal(last.run, 'NYE');
    assert.equal(last.rowIndex, before.runs[before.runs.length - 1].rowIndex + 1);
  });

  test.it('copies the derived formula columns into the inserted row', () => {
    const env = api(2026);
    assertOk(
      env.post({ action: 'addRun', date: 'Sat, 24-Jan', meet: 'Il Lido', run: 'Parkrun' })
    );
    const copies = env.writes().filter((w) => w.kind === 'copyTo');
    assert.equal(copies.length, 1, 'exactly one formula copy per inserted run');
    assert.ok(
      copies[0].toCol > SEASON_FACTS[2026].plusOnesCol,
      'the copy must start right of the +1\'s column'
    );
    assert.notEqual(copies[0].fromRow, copies[0].toRow);
  });

  test.it('refuses a duplicate date+run pair', () => {
    const env = api(2026);
    const response = assertError(
      env.post({
        action: 'addRun',
        date: SEASON_FACTS[2026].sharedDate,
        run: SEASON_FACTS[2026].sharedDateRuns[0],
        meet: 'Filament',
      }),
      'bad_payload'
    );
    assert.match(response.message, /already exists/);
    assert.equal(env.writes().length, 0);
  });

  test.it('refuses a payload without a usable date or run', () => {
    const env = api(2026);
    assertError(env.post({ action: 'addRun', run: 'Soft Sand' }), 'bad_payload');
    assertError(env.post({ action: 'addRun', date: 'someday', run: 'Soft Sand' }), 'bad_payload');
    assertError(env.post({ action: 'addRun', date: 'Fri, 3-Apr' }), 'bad_payload');
    assert.equal(env.writes().length, 0);
  });

  test.it('leaves the surrounding runs exactly as they were', () => {
    const env = api(2025);
    const before = assertOk(env.post({ action: 'getState' }));
    const response = assertOk(
      env.post({ action: 'addRun', date: 'Sat, 25-Jan', meet: 'Il Lido', run: 'Parkrun' })
    );
    const inserted = response.runs.find((r) => r.run === 'Parkrun');
    for (const run of before.runs) {
      const now = response.runs.find(
        (r) => r.date === run.date && r.run === run.run
      );
      assert.ok(now, `${run.date} / ${run.run} went missing`);
      assert.deepEqual(now.attendees, run.attendees);
      assert.equal(now.actualKm, run.actualKm);
      assert.equal(now.rowIndex, run.rowIndex < inserted.rowIndex
        ? run.rowIndex
        : run.rowIndex + 1);
    }
  });
});

test.describe('serialization (LockService)', () => {
  test.it('holds and releases the script lock around every write action', () => {
    for (const payload of [
      { action: 'addMember', name: 'Bruce' },
      { action: 'addRun', date: 'Sat, 24-Jan', run: 'Parkrun', meet: 'Il Lido' },
      {
        action: 'submitAttendance',
        rowIndex: SEASON_FACTS[2026].firstRunRow,
        expectedDate: SEASON_FACTS[2026].firstRun.date,
        expectedRun: SEASON_FACTS[2026].firstRun.run,
        attendees: [],
        plusOnes: 0,
        mode: 'merge',
      },
    ]) {
      const env = api(2026);
      assertOk(env.post(payload));
      assert.deepEqual(
        env.lockLog.map((entry) => entry.kind),
        ['waitLock', 'releaseLock'],
        `${payload.action} must take and release the lock exactly once`
      );
    }
  });

  test.it('releases the lock even when the action fails', () => {
    const env = api(2026);
    assertError(env.post({ action: 'addMember', name: 'Col' }), 'duplicate_member');
    assert.deepEqual(env.lockLog.map((e) => e.kind), ['waitLock', 'releaseLock']);
  });

  test.it('does not lock for a read', () => {
    const env = api(2026);
    assertOk(env.post({ action: 'getState' }));
    assert.deepEqual(env.lockLog, []);
  });

  test.it('reports busy rather than writing when another writer holds the lock', () => {
    const env = api(2026, { lockHeld: true });
    assertError(env.post({ action: 'addMember', name: 'Bruce' }), 'busy');
    assert.equal(env.writes().length, 0);
  });
});

test.describe('contract shapes (frozen API)', () => {
  test.it('every response is a JSON object with a boolean ok', () => {
    const env = api(2026);
    const responses = [
      env.raw('garbage'),
      env.raw(JSON.stringify({ secret: 'wrong', action: 'getState' })),
      env.post({ action: 'nope' }),
      env.post({ action: 'getState' }),
      env.post({ action: 'addMember', name: 'Col' }),
      env.post({ action: 'addMember', name: 'Bruce' }),
      env.post({ action: 'addRun', date: 'Sat, 24-Jan', run: 'Parkrun', meet: 'Il Lido' }),
    ];
    for (const response of responses) {
      assert.equal(typeof response, 'object');
      assert.equal(typeof response.ok, 'boolean');
      if (response.ok === false) {
        assert.equal(typeof response.error, 'string');
        assert.equal(typeof response.message, 'string');
      }
    }
  });

  test.it('serializes as JSON with the JSON mime type', () => {
    const env = api(2026);
    const output = env.context.doPost({
      postData: { contents: JSON.stringify({ secret: env.secret, action: 'getState' }) },
    });
    assert.equal(output.mimeType, 'application/json');
    assert.doesNotThrow(() => JSON.parse(output.getContent()));
  });

  test.it('uses only the documented error codes', () => {
    const documented = new Set([
      'bad_secret',
      'unknown_action',
      'row_mismatch',
      'stale_revision',
      'duplicate_member',
      'bad_payload',
      // U2 additions, see apps-script/HANDOFF.md.
      'sheet_unreadable',
      'busy',
      'internal_error',
      'method_not_allowed',
    ]);
    const env = api(2026);
    const failures = [
      env.raw('garbage'),
      env.raw(JSON.stringify({ action: 'getState' })),
      env.post({ action: 'nope' }),
      env.post({ action: 'addMember', name: 'Col' }),
      env.post({ action: 'addMember', name: '' }),
      env.post({ action: 'addRun', date: 'nope', run: 'x' }),
      JSON.parse(env.context.doGet().getContent()),
    ];
    for (const response of failures) {
      assert.ok(documented.has(response.error), `undocumented error code ${response.error}`);
    }
  });

  test.it('a conflict is a success envelope carrying reason + fresh state', () => {
    const env = api(2026);
    const { run } = invasionDay10k(env);
    const response = env.post({
      action: 'submitAttendance',
      rowIndex: run.rowIndex,
      expectedDate: run.date,
      expectedRun: 'Not This Run',
      attendees: [],
      plusOnes: 0,
      mode: 'merge',
    });
    assert.deepEqual(Object.keys(response).sort(), ['conflict', 'ok']);
    assert.equal(response.ok, true);
    assert.ok(['row_mismatch', 'stale_revision'].includes(response.conflict.reason));
    assert.equal(typeof response.conflict.message, 'string');
    assertStateShape(response.conflict.state, 2026);
  });
});
