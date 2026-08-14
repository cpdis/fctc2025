/**
 * SheetOps tests — the scaffold checks (U1) plus the sheet-geometry suite (U2).
 *
 * The geometry half is table-driven over BOTH season fixtures on purpose. 2025 and
 * 2026 differ in every way that breaks a parser written against one snapshot: the
 * header row sits at 10 vs 11 (the notes/summary band above it grew), the member
 * band is 30 vs 33 columns wide, and the run labels are punctuated differently
 * ("Half- Invasion Day" vs "Half - Invasion Day"). Anything asserted here is
 * asserted for both, so "works on this season" can never pass for "works".
 *
 * Facts the tests compare against live in `support/seasons.js`, written out by hand
 * from the CSVs — a regression in the parser must not be able to redefine correct.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const APPS_SCRIPT_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(APPS_SCRIPT_DIR, '..');
const SheetOps = require(path.join(APPS_SCRIPT_DIR, 'SheetOps.js'));
const { parseCsv } = require('./support/csv.js');
const { SEASON_YEARS, SEASON_FACTS, seasonGrid } = require('./support/seasons.js');

/** Member names of a season fixture, read the way the sheet is read: by content. */
function readRosterHeader(year) {
  const csv = fs.readFileSync(
    path.join(REPO_ROOT, 'fixtures', 'attendance', `${year}.csv`),
    'utf8'
  );
  const headerLine = csv
    .split('\n')
    .find((line) => line.startsWith('Date,Meet,Run'));
  assert.ok(headerLine, `no header row found in ${year}.csv`);
  return headerLine.replace(/\r$/, '').split(',');
}

/** Convenience: grid + resolved geometry for a season. */
function season(year) {
  const grid = seasonGrid(year);
  const headerRow = SheetOps.findHeaderRow(grid);
  return {
    year,
    grid,
    headerRow,
    bounds: SheetOps.bandBounds(grid, headerRow),
    band: SheetOps.memberBand(grid, headerRow),
    facts: SEASON_FACTS[year],
  };
}

test.describe('SheetOps module (dual-environment pattern)', () => {
  test.it('loads in Node via module.exports', () => {
    assert.equal(typeof SheetOps, 'object');
    assert.equal(typeof SheetOps.cellText, 'function');
    assert.equal(typeof SheetOps.sheetOpsHealth, 'function');
  });

  test.it('reports a version consistent with its own constant', () => {
    const health = SheetOps.sheetOpsHealth();
    assert.equal(health.module, 'SheetOps');
    assert.equal(health.version, SheetOps.SHEETOPS_VERSION);
    assert.ok(Array.isArray(health.implemented));
    for (const name of health.implemented) {
      assert.equal(
        typeof SheetOps[name],
        'function',
        `sheetOpsHealth() claims ${name} but it is not exported`
      );
    }
  });

  test.it('cellText trims without normalizing the canonical member key', () => {
    assert.equal(SheetOps.cellText('  Alex Kr '), 'Alex Kr');
    assert.equal(SheetOps.cellText(null), '');
    assert.equal(SheetOps.cellText(undefined), '');
    assert.equal(SheetOps.cellText(0), '0');
    // Case and emoji are part of the key and must survive untouched.
    assert.equal(SheetOps.cellText('Alex 👑'), 'Alex 👑');
    assert.equal(SheetOps.cellText("+1's"), "+1's");
  });

  test.it('member-band boundary constants exist in both season headers', () => {
    for (const year of SEASON_YEARS) {
      const header = readRosterHeader(year);
      const start = header.indexOf(SheetOps.MEMBER_BAND_START_AFTER);
      const end = header.indexOf(SheetOps.MEMBER_BAND_END_BEFORE);
      assert.ok(start >= 0, `${year}: no "${SheetOps.MEMBER_BAND_START_AFTER}" column`);
      assert.ok(end > start, `${year}: "${SheetOps.MEMBER_BAND_END_BEFORE}" must follow it`);
      assert.ok(end - start > 20, `${year}: member band looks implausibly small`);
    }
  });
});

test.describe('Apps Script sources', () => {
  const sources = ['Code.gs', 'SheetOps.js'];

  test.it('exist and parse as JavaScript', () => {
    for (const file of sources) {
      const full = path.join(APPS_SCRIPT_DIR, file);
      assert.ok(fs.existsSync(full), `${file} is missing`);
      // Throws a SyntaxError (failing the test) if the file does not parse.
      new Function(fs.readFileSync(full, 'utf8'));
    }
  });

  test.it('contain no require()/import — Apps Script has no module loader', () => {
    // Comments talk ABOUT require(); only code matters, so strip them first.
    const stripComments = (src) =>
      src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');

    for (const file of sources) {
      const src = stripComments(fs.readFileSync(path.join(APPS_SCRIPT_DIR, file), 'utf8'));
      assert.ok(!/\brequire\s*\(/.test(src), `${file} must not call require()`);
      assert.ok(!/^\s*import\s/m.test(src), `${file} must not use import`);
    }
  });

  test.it('appsscript.json is a valid V8 anonymous web app', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(APPS_SCRIPT_DIR, 'appsscript.json'), 'utf8')
    );
    assert.equal(manifest.runtimeVersion, 'V8');
    assert.equal(manifest.webapp.access, 'ANYONE_ANONYMOUS');
    assert.equal(manifest.webapp.executeAs, 'USER_DEPLOYING');
  });

  test.it('.clasp.json.example ships a placeholder, never a real script id', () => {
    const example = JSON.parse(
      fs.readFileSync(path.join(APPS_SCRIPT_DIR, '.clasp.json.example'), 'utf8')
    );
    assert.match(example.scriptId, /REPLACE_ME/);
  });

  /** Source with comments removed — prose mentions the services it describes. */
  const code = (file) =>
    fs
      .readFileSync(path.join(APPS_SCRIPT_DIR, file), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|\s)\/\/.*$/gm, '$1');

  test.it('SheetOps stays free of the Apps Script services — geometry must be pure', () => {
    const src = code('SheetOps.js');
    for (const service of [
      'SpreadsheetApp',
      'PropertiesService',
      'LockService',
      'ContentService',
    ]) {
      assert.ok(!new RegExp(`\\b${service}\\b`).test(src), `SheetOps must not touch ${service}`);
    }
  });

  test.it('Code.gs never reads the grid itself — it hands it to SheetOps', () => {
    const src = code('Code.gs');
    // Indexing the grid IS deriving geometry. The shell may pass `ctx.grid` around,
    // but the moment it subscripts one, the band logic has been duplicated.
    assert.ok(!/grid\s*\[/.test(src), 'Code.gs must not index into the grid');
    assert.ok(!/\.indexOf\s*\(/.test(src), 'Code.gs must not scan header cells');
  });

  test.it('Code.gs calls every geometry helper through the SheetOps namespace', () => {
    const src = code('Code.gs');
    const geometry = SheetOps.sheetOpsHealth().implemented;
    let used = 0;
    for (const name of geometry) {
      const bare = new RegExp(`(^|[^.\\w])${name}\\s*\\(`, 'g');
      const viaNamespace = new RegExp(`SheetOps\\.${name}\\s*\\(`, 'g');
      const bareCalls = (src.match(bare) || []).length;
      const namespaced = (src.match(viaNamespace) || []).length;
      assert.equal(
        bareCalls,
        0,
        `Code.gs calls ${name}() directly; go through SheetOps.${name}()`
      );
      if (namespaced) used++;
    }
    assert.ok(used >= 10, `expected Code.gs to lean on SheetOps; only ${used} helpers used`);
  });

  test.it('Code.gs defines no function that shadows a SheetOps export', () => {
    const src = code('Code.gs');
    const declared = (src.match(/function\s+([A-Za-z0-9_]+)\s*\(/g) || []).map((m) =>
      m.replace(/function\s+/, '').replace(/\s*\($/, '')
    );
    for (const name of declared) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(SheetOps, name),
        `Code.gs re-implements ${name}, which SheetOps already exports`
      );
    }
  });
});

test.describe('test CSV parser (quoted commas)', () => {
  test.it('keeps a comma inside a quoted field', () => {
    const rows = parseCsv('"Fri, 2-Jan",Il Lido,Soft Sand\n');
    assert.deepEqual(rows, [['Fri, 2-Jan', 'Il Lido', 'Soft Sand']]);
  });

  test.it('handles escaped quotes, CRLF, and a missing trailing newline', () => {
    const rows = parseCsv('a,"b""c"\r\n"d,e",f');
    assert.deepEqual(rows, [
      ['a', 'b"c'],
      ['d,e', 'f'],
    ]);
  });

  test.it('preserves empty cells so column indices stay meaningful', () => {
    assert.deepEqual(parseCsv('x,,y')[0], ['x', '', 'y']);
  });

  test.it('reads every quoted season date without splitting it', () => {
    for (const year of SEASON_YEARS) {
      const { grid, headerRow, facts } = season(year);
      assert.equal(grid[facts.firstRunRow - 1][0], facts.firstRun.date);
      assert.ok(headerRow > 0);
    }
  });
});

test.describe('findHeaderRow', () => {
  test.it('finds the header on both seasons despite the drift', () => {
    for (const year of SEASON_YEARS) {
      const { grid, facts } = season(year);
      assert.equal(SheetOps.findHeaderRow(grid), facts.headerRow, `${year} header row`);
    }
    // The whole point: the two seasons do NOT agree on the position.
    assert.notEqual(SEASON_FACTS[2025].headerRow, SEASON_FACTS[2026].headerRow);
  });

  test.it('tolerates an arbitrary summary band above the header', () => {
    const { grid, facts } = season(2026);
    const padded = [['Notes:'], [], ['COUNTUNIQUE', 1, 2], ...grid];
    assert.equal(SheetOps.findHeaderRow(padded), facts.headerRow + 3);
  });

  test.it('ignores a row that says Date but is not the header', () => {
    const rows = [
      ['Date', 'of last sync', '2026-08-14'],
      ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms', 'Col', "+1's"],
    ];
    assert.equal(SheetOps.findHeaderRow(rows), 2);
  });

  test.it('returns NO_INDEX when there is no header row at all', () => {
    assert.equal(SheetOps.findHeaderRow([['Notes:'], ['nothing here']]), SheetOps.NO_INDEX);
    assert.equal(SheetOps.findHeaderRow([]), SheetOps.NO_INDEX);
    assert.equal(SheetOps.findHeaderRow(null), SheetOps.NO_INDEX);
  });
});

test.describe('memberBand', () => {
  test.it('extracts exactly the columns between Actual kms and +1\'s', () => {
    for (const year of SEASON_YEARS) {
      const { band, facts } = season(year);
      assert.equal(band.length, facts.memberCount, `${year} member count`);
      assert.deepEqual(
        band.map((m) => m.name),
        facts.members,
        `${year} member names`
      );
      assert.equal(band[0].colIndex, facts.firstMemberCol);
      assert.equal(band[band.length - 1].colIndex, facts.lastMemberCol);
    }
  });

  test.it('reports the column bounds the writers are allowed to touch', () => {
    for (const year of SEASON_YEARS) {
      const { bounds, facts } = season(year);
      assert.equal(bounds.actualKmCol, facts.actualKmCol);
      assert.equal(bounds.plusOnesCol, facts.plusOnesCol);
      assert.equal(bounds.firstMemberCol, facts.firstMemberCol);
      assert.equal(bounds.lastMemberCol, facts.lastMemberCol);
      assert.equal(bounds.memberCount, facts.memberCount);
    }
  });

  test.it('names in the band carry their real sheet column', () => {
    const { grid, band, facts } = season(2026);
    for (const member of band) {
      assert.equal(grid[facts.headerRow - 1][member.colIndex - 1], member.name);
    }
  });

  test.it('keeps the emoji in the canonical key', () => {
    const { band } = season(2026);
    assert.ok(band.some((m) => m.name === 'Alex 👑'));
  });

  test.it('returns nothing when the header row is unusable', () => {
    assert.deepEqual(SheetOps.memberBand([['Date', 'Meet']], 1), []);
    assert.equal(SheetOps.bandBounds([['Date', 'Meet']], 1), null);
  });
});

test.describe('listRuns / readRun', () => {
  test.it('reads the first run of each season, attendance included', () => {
    for (const year of SEASON_YEARS) {
      const { grid, headerRow, facts } = season(year);
      const runs = SheetOps.listRuns(grid, headerRow);
      const first = runs[0];
      assert.equal(first.rowIndex, facts.firstRunRow);
      assert.equal(first.date, facts.firstRun.date);
      assert.equal(first.meet, facts.firstRun.meet);
      assert.equal(first.run, facts.firstRun.run);
      assert.ok(first.attendees.every((name) => facts.members.includes(name)));
    }
  });

  test.it('counts attendance the way the dashboard does (x yes, - and blank no)', () => {
    const { grid, headerRow } = season(2025);
    const runs = SheetOps.listRuns(grid, headerRow);
    // 2025 row 14 ("Wed, 15-Jan") marks Claire and Rhys with "-", not "x".
    const run = runs.find((r) => r.date === 'Wed, 15-Jan');
    assert.ok(run, 'expected a 15-Jan run');
    assert.ok(!run.attendees.includes('Claire'));
    assert.ok(!run.attendees.includes('Rhys'));
    assert.ok(run.attendees.includes('Aaron'));
  });

  test.it('keeps blank distances as null, never 0', () => {
    const { grid, headerRow } = season(2026);
    const runs = SheetOps.listRuns(grid, headerRow);
    const future = runs[runs.length - 1];
    assert.equal(future.actualKm, null);
    assert.equal(future.plusOnes, 0);
    assert.deepEqual(future.attendees, []);
    // ...but a recorded distance still comes through as a number.
    assert.equal(typeof runs[0].actualKm, 'number');
  });

  test.it('skips rows below the band that are not runs', () => {
    const { grid, headerRow } = season(2026);
    const before = SheetOps.listRuns(grid, headerRow).length;
    const withJunk = grid.concat([[''], ['Totals', '', '', '', 999]]);
    assert.equal(SheetOps.listRuns(withJunk, headerRow).length, before);
  });
});

test.describe('findRunRow (two runs can share a date)', () => {
  test.it('disambiguates the Invasion Day pair by run label', () => {
    for (const year of SEASON_YEARS) {
      const { grid, headerRow, facts } = season(year);
      const rows = facts.sharedDateRuns.map((run) =>
        SheetOps.findRunRow(grid, headerRow, { date: facts.sharedDate, run })
      );
      assert.ok(rows[0] > 0 && rows[1] > 0, `${year}: both runs must be found`);
      assert.notEqual(rows[0], rows[1], `${year}: the two runs are different rows`);
      // Both really are on the same date...
      assert.equal(SheetOps.findRunRows(grid, headerRow, {
        date: facts.sharedDate,
        run: facts.sharedDateRuns[0],
      }).length, 1);
      const sameDate = SheetOps.listRuns(grid, headerRow).filter(
        (r) => r.date === facts.sharedDate
      );
      assert.equal(sameDate.length, 2, `${year}: expected exactly two runs on the shared date`);
    }
  });

  test.it('matches a date with or without its weekday prefix', () => {
    const { grid, headerRow, facts } = season(2026);
    const withPrefix = SheetOps.findRunRow(grid, headerRow, {
      date: facts.sharedDate,
      run: facts.sharedDateRuns[0],
    });
    const withoutPrefix = SheetOps.findRunRow(grid, headerRow, {
      date: '26-Jan',
      run: facts.sharedDateRuns[0],
    });
    assert.equal(withoutPrefix, withPrefix);
  });

  test.it('matches run labels across the seasons\' punctuation drift', () => {
    const { grid, headerRow } = season(2026);
    // 2026 writes "Half - Invasion Day"; 2025 writes "Half- Invasion Day".
    const row = SheetOps.findRunRow(grid, headerRow, {
      date: 'Mon, 26-Jan',
      run: 'Half- Invasion Day',
    });
    assert.ok(row > 0);
    assert.equal(SheetOps.listRuns(grid, headerRow).find((r) => r.rowIndex === row).run,
      'Half - Invasion Day');
  });

  test.it('returns NO_INDEX for a run that is not there', () => {
    const { grid, headerRow } = season(2026);
    assert.equal(
      SheetOps.findRunRow(grid, headerRow, { date: 'Mon, 26-Jan', run: 'Ultra' }),
      SheetOps.NO_INDEX
    );
    assert.equal(
      SheetOps.findRunRow(grid, headerRow, { date: '31-Feb', run: 'Soft Sand' }),
      SheetOps.NO_INDEX
    );
  });
});

test.describe('revisionHash', () => {
  test.it('is stable across repeated reads of the same grid', () => {
    for (const year of SEASON_YEARS) {
      const a = season(year);
      const b = season(year);
      assert.equal(
        SheetOps.revisionHash(a.grid, a.headerRow),
        SheetOps.revisionHash(b.grid, b.headerRow)
      );
    }
  });

  test.it('is 16 hex characters and differs between the seasons', () => {
    const a = season(2025);
    const b = season(2026);
    const ha = SheetOps.revisionHash(a.grid, a.headerRow);
    const hb = SheetOps.revisionHash(b.grid, b.headerRow);
    assert.match(ha, /^[0-9a-f]{16}$/);
    assert.match(hb, /^[0-9a-f]{16}$/);
    assert.notEqual(ha, hb);
  });

  test.it('changes when any attendance mark changes', () => {
    const { grid, headerRow, band, facts } = season(2026);
    const before = SheetOps.revisionHash(grid, headerRow);
    grid[facts.firstRunRow - 1][band[0].colIndex - 1] = 'x';
    assert.notEqual(SheetOps.revisionHash(grid, headerRow), before);
  });

  test.it('changes when the roster changes', () => {
    const { grid, headerRow } = season(2026);
    const before = SheetOps.revisionHash(grid, headerRow);
    grid[headerRow - 1][7] = 'Alex Renamed';
    assert.notEqual(SheetOps.revisionHash(grid, headerRow), before);
  });

  test.it('ignores the notes band above the header and the formulas to the right', () => {
    const { grid, headerRow, bounds, facts } = season(2026);
    const before = SheetOps.revisionHash(grid, headerRow);
    grid[0][0] = 'Notes: rewritten';
    grid[facts.firstRunRow - 1][bounds.plusOnesCol] = 999; // derived column
    assert.equal(SheetOps.revisionHash(grid, headerRow), before);
  });

  test.it('is empty for a grid with no usable band', () => {
    assert.equal(SheetOps.revisionHash([['Date', 'Meet']], 1), '');
  });
});

test.describe('normalizeKey / compareNames', () => {
  test.it('folds case, emoji and diacritics but keeps the words', () => {
    assert.equal(SheetOps.normalizeKey('Alex 👑'), 'alex');
    assert.equal(SheetOps.normalizeKey('  ALEX  Kr '), 'alex kr');
    assert.equal(SheetOps.normalizeKey('Chloé'), 'chloe');
    assert.equal(SheetOps.normalizeKey("O'Brien"), 'o brien');
    assert.equal(SheetOps.normalizeKey('👑'), '');
  });

  test.it('orders the way the band is ordered', () => {
    assert.ok(SheetOps.compareNames('Alex 👑', 'Alex B') < 0);
    assert.ok(SheetOps.compareNames('Alex B', 'Alex Kr') < 0);
    assert.ok(SheetOps.compareNames('Dan', 'Dan B') < 0);
    assert.equal(SheetOps.compareNames('col', 'col'), 0);
  });

  test.it('agrees with how both seasons actually ordered their bands', () => {
    for (const year of SEASON_YEARS) {
      const { band } = season(year);
      for (let i = 1; i < band.length; i++) {
        assert.ok(
          SheetOps.compareNames(band[i - 1].name, band[i].name) < 0,
          `${year}: ${band[i - 1].name} should sort before ${band[i].name}`
        );
      }
    }
  });
});

test.describe('alphabeticalInsertIndex / findMemberIndex', () => {
  test.it('puts Alex B between Alex 👑 and Alex Kr in the 2025 band', () => {
    const { band } = season(2025);
    const position = SheetOps.alphabeticalInsertIndex(band, 'Alex B');
    assert.equal(band[position - 1].name, 'Alex 👑');
    assert.equal(band[position].name, 'Alex Kr');
    // ...which is exactly where 2026 put it for real.
    assert.equal(SEASON_FACTS[2026].members[position], 'Alex B');
  });

  test.it('puts Dan B after Dan and before Darren (prefix case)', () => {
    const { band } = season(2025);
    const position = SheetOps.alphabeticalInsertIndex(band, 'Dan B');
    assert.equal(band[position - 1].name, 'Dan');
    assert.equal(band[position].name, 'Darren');
  });

  test.it('puts Deano after Darren, matching the real 2026 band', () => {
    const { band } = season(2025);
    const position = SheetOps.alphabeticalInsertIndex(band, 'Deano');
    assert.equal(band[position - 1].name, 'Darren');
    assert.equal(band[position].name, 'Fraser');
  });

  test.it('inserts at the ends when the name sorts first or last', () => {
    const { band } = season(2026);
    assert.equal(SheetOps.alphabeticalInsertIndex(band, 'Aaliyah'), 0);
    assert.equal(SheetOps.alphabeticalInsertIndex(band, 'Zoe'), band.length);
  });

  test.it('reproduces each season band by inserting its own members one by one', () => {
    for (const year of SEASON_YEARS) {
      const { facts } = season(year);
      const rebuilt = [];
      // Shuffle deterministically so insertion order cannot flatter the result.
      const shuffled = facts.members.slice().reverse();
      for (const name of shuffled) {
        rebuilt.splice(SheetOps.alphabeticalInsertIndex(rebuilt, name), 0, name);
      }
      assert.deepEqual(rebuilt, facts.members, `${year}: rebuilt band`);
    }
  });

  test.it('detects duplicates case- and emoji-insensitively', () => {
    const { band } = season(2026);
    assert.ok(SheetOps.findMemberIndex(band, 'col') >= 0);
    assert.equal(band[SheetOps.findMemberIndex(band, 'col')].name, 'Col');
    assert.ok(SheetOps.findMemberIndex(band, '  ALEX KR ') >= 0);
    assert.ok(SheetOps.findMemberIndex(band, 'Alex') >= 0); // matches "Alex 👑"
    assert.equal(SheetOps.findMemberIndex(band, 'Colin'), -1);
    assert.equal(SheetOps.findMemberIndex(band, ''), -1);
  });

  test.it('memberInsertPlan stays strictly inside the band', () => {
    const { band, bounds } = season(2026);
    const middle = SheetOps.alphabeticalInsertIndex(band, 'Bruce');
    const plan = SheetOps.memberInsertPlan(band, bounds, middle);
    assert.ok(plan.insertBefore > bounds.actualKmCol);
    assert.ok(plan.insertBefore <= band[band.length - 1].colIndex);
    assert.equal(plan.relocateDisplaced, false);
  });

  test.it('memberInsertPlan relocates the displaced member for sorts-last', () => {
    // Smoke-test ruling (2026-08-14): inserting before +1's lands one past the
    // run-row COUNTIF ranges and they do NOT widen, so a sorts-last member
    // inserts before the current last member and the displaced member moves
    // into the new column.
    const { band, bounds } = season(2026);
    const lastCol = band[band.length - 1].colIndex;
    const plan = SheetOps.memberInsertPlan(band, bounds, band.length);
    assert.equal(plan.insertBefore, lastCol);
    assert.equal(plan.relocateDisplaced, true);
    assert.equal(plan.displacedCol, lastCol + 1);
    assert.ok(plan.insertBefore < bounds.plusOnesCol);
  });
});

test.describe('buildRowWrite (merge vs overwrite)', () => {
  /** A tiny synthetic band, so the expectations are readable. */
  const band = [
    { name: 'Aaron', colIndex: 6 },
    { name: 'Alex 👑', colIndex: 7 },
    { name: 'Col', colIndex: 8 },
    { name: 'Wes', colIndex: 9 },
  ];
  const existingValues = ['x', '', '-', 'x'];

  test.it('merge unions with the marks already on the row', () => {
    const plan = SheetOps.buildRowWrite(band, ['Alex 👑'], null, null, {
      mode: 'merge',
      existingValues,
    });
    assert.deepEqual(plan.memberValues, ['x', 'x', '-', 'x']);
    assert.deepEqual(plan.attendees, ['Aaron', 'Alex 👑', 'Wes']);
    assert.equal(plan.changedCells, 1);
  });

  test.it('overwrite clears marks the submission omits (Q1: resolved yes)', () => {
    const plan = SheetOps.buildRowWrite(band, ['Alex 👑'], null, null, {
      mode: 'overwrite',
      existingValues,
    });
    assert.deepEqual(plan.memberValues, ['', 'x', '-', '']);
    assert.deepEqual(plan.attendees, ['Alex 👑']);
    // Aaron and Wes lose their x; Alex gains one; Col's "-" is left alone.
    assert.equal(plan.changedCells, 3);
  });

  test.it('never destroys a "-" annotation, in either mode', () => {
    for (const mode of ['merge', 'overwrite']) {
      const plan = SheetOps.buildRowWrite(band, [], null, null, { mode, existingValues });
      assert.equal(plan.memberValues[2], '-', `${mode} must preserve the "-" cell`);
    }
    // ...unless that member is now recorded as attending.
    const promoted = SheetOps.buildRowWrite(band, ['Col'], null, null, {
      mode: 'merge',
      existingValues,
    });
    assert.equal(promoted.memberValues[2], 'x');
  });

  test.it('is idempotent: re-sending the same payload changes nothing', () => {
    const first = SheetOps.buildRowWrite(band, ['Aaron', 'Wes'], 2, 7.5, {
      mode: 'overwrite',
      existingValues,
      existingPlusOnes: 0,
      existingActualKm: null,
    });
    const second = SheetOps.buildRowWrite(band, ['Aaron', 'Wes'], 2, 7.5, {
      mode: 'overwrite',
      existingValues: first.memberValues,
      existingPlusOnes: first.plusOnes,
      existingActualKm: first.actualKm,
    });
    assert.deepEqual(second.memberValues, first.memberValues);
    assert.equal(second.changedCells, 0);
    assert.equal(second.writePlusOnes, false);
    assert.equal(second.writeActualKm, false);
  });

  test.it('treats a missing plusOnes/actualKm as "no opinion", not as zero', () => {
    const plan = SheetOps.buildRowWrite(band, ['Aaron'], null, undefined, {
      mode: 'overwrite',
      existingValues,
      existingPlusOnes: 3,
      existingActualKm: 12.3,
    });
    assert.equal(plan.writePlusOnes, false);
    assert.equal(plan.writeActualKm, false);
    assert.equal(plan.plusOnes, null);
  });

  test.it('merges plusOnes upward but overwrites them absolutely', () => {
    const merged = SheetOps.buildRowWrite(band, [], 1, null, {
      mode: 'merge',
      existingValues,
      existingPlusOnes: 3,
    });
    assert.equal(merged.plusOnes, 3);
    assert.equal(merged.writePlusOnes, false);

    const raised = SheetOps.buildRowWrite(band, [], 4, null, {
      mode: 'merge',
      existingValues,
      existingPlusOnes: 3,
    });
    assert.equal(raised.plusOnes, 4);
    assert.equal(raised.writePlusOnes, true);

    const overwritten = SheetOps.buildRowWrite(band, [], 1, null, {
      mode: 'overwrite',
      existingValues,
      existingPlusOnes: 3,
    });
    assert.equal(overwritten.plusOnes, 1);
    assert.equal(overwritten.writePlusOnes, true);
  });

  test.it('reports names that are not on the roster instead of dropping them', () => {
    const plan = SheetOps.buildRowWrite(band, ['Aaron', 'Nigel'], null, null, {
      mode: 'merge',
      existingValues,
    });
    assert.deepEqual(plan.unknownNames, ['Nigel']);
    assert.ok(!plan.attendees.includes('Nigel'));
  });

  test.it('resolves attendees case-insensitively against the band', () => {
    const plan = SheetOps.buildRowWrite(band, ['alex', 'COL'], null, null, {
      mode: 'overwrite',
      existingValues: ['', '', '', ''],
    });
    assert.deepEqual(plan.memberValues, ['', 'x', 'x', '']);
    assert.deepEqual(plan.unknownNames, []);
  });

  test.it('defaults to merge and to an empty row when told nothing', () => {
    const plan = SheetOps.buildRowWrite(band, ['Wes'], 0, 5);
    assert.equal(plan.mode, 'merge');
    assert.deepEqual(plan.memberValues, ['', '', '', 'x']);
  });

  test.it('produces one value per band member on a real season band', () => {
    for (const year of SEASON_YEARS) {
      const { grid, headerRow, band: real, facts } = season(year);
      const plan = SheetOps.buildRowWrite(real, [facts.members[0]], 1, 7, {
        mode: 'overwrite',
        existingValues: SheetOps.memberValuesAt(grid, headerRow, facts.firstRunRow),
      });
      assert.equal(plan.memberValues.length, facts.memberCount);
    }
  });
});

test.describe('dateOrderedInsertIndex', () => {
  const runs = [
    { rowIndex: 12, date: 'Fri, 2-Jan' },
    { rowIndex: 13, date: 'Mon, 26-Jan' },
    { rowIndex: 14, date: 'Mon, 26-Jan' },
    { rowIndex: 15, date: 'Wed, 4-Feb' },
    { rowIndex: 16, date: 'Sun, 1-Mar' },
  ];

  test.it('places a new date between its neighbours', () => {
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'Sat, 10-Jan'), 1);
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'Thu, 5-Feb'), 4);
  });

  test.it('appends after runs already on the same date (second 26-Jan run)', () => {
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'Mon, 26-Jan'), 3);
  });

  test.it('handles the ends of the season', () => {
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'Thu, 1-Jan'), 0);
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'Thu, 31-Dec'), runs.length);
    assert.equal(SheetOps.dateOrderedInsertIndex([], 'Thu, 1-Jan'), 0);
  });

  test.it('leaves an unparseable date at the bottom', () => {
    assert.equal(SheetOps.dateOrderedInsertIndex(runs, 'sometime'), runs.length);
  });

  test.it('keeps both seasons in date order, so an insert has meaning', () => {
    for (const year of SEASON_YEARS) {
      const { grid, headerRow } = season(year);
      const seasonRuns = SheetOps.listRuns(grid, headerRow);
      for (let i = 1; i < seasonRuns.length; i++) {
        assert.ok(
          SheetOps.dateOrdinal(seasonRuns[i - 1].date) <=
            SheetOps.dateOrdinal(seasonRuns[i].date),
          `${year}: ${seasonRuns[i - 1].date} should not follow ${seasonRuns[i].date}`
        );
      }
    }
  });

  test.it('runInsertTarget resolves to a real sheet row', () => {
    const midYear = SheetOps.runInsertTarget(runs, 11, 'Sat, 10-Jan');
    assert.deepEqual(midYear, { position: 1, rowIndex: 13, append: false });
    const endOfSeason = SheetOps.runInsertTarget(runs, 11, 'Thu, 31-Dec');
    assert.deepEqual(endOfSeason, { position: 5, rowIndex: 17, append: true });
    const emptySeason = SheetOps.runInsertTarget([], 11, 'Thu, 1-Jan');
    assert.deepEqual(emptySeason, { position: 0, rowIndex: 12, append: true });
  });
});

test.describe('date and number cells', () => {
  test.it('parses the season date formats the sheet uses', () => {
    assert.deepEqual(SheetOps.parseSheetDate('Fri, 3-Jan'), { month: 0, day: 3 });
    assert.deepEqual(SheetOps.parseSheetDate('26-Jan'), { month: 0, day: 26 });
    assert.deepEqual(SheetOps.parseSheetDate('Sun, 14-Dec'), { month: 11, day: 14 });
    assert.equal(SheetOps.parseSheetDate('Total'), null);
    assert.equal(SheetOps.parseSheetDate(''), null);
  });

  test.it('renders a date-typed cell the way the sheet writes text dates', () => {
    // A cell someone re-typed as a real date must not become "Fri Jan 03 2025 ...".
    assert.equal(SheetOps.dateCellText(new Date(2025, 0, 3)), 'Fri, 3-Jan');
    assert.equal(SheetOps.dateCellText('Fri, 3-Jan'), 'Fri, 3-Jan');
    assert.deepEqual(SheetOps.parseSheetDate(new Date(2026, 11, 30)), { month: 11, day: 30 });
  });

  test.it('distinguishes an empty distance from zero', () => {
    assert.equal(SheetOps.numberOrNull(''), null);
    assert.equal(SheetOps.numberOrNull(null), null);
    assert.equal(SheetOps.numberOrNull('n/a'), null);
    assert.equal(SheetOps.numberOrNull(0), 0);
    assert.equal(SheetOps.numberOrNull('7.07'), 7.07);
    assert.equal(SheetOps.numberOrNull(12.5), 12.5);
  });
});

test.describe('isWriteWithinBand (sheet-safety invariant)', () => {
  const { bounds, headerRow } = season(2026);

  test.it('allows the granted cells', () => {
    const row = headerRow + 5;
    assert.ok(
      SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.firstMemberCol, 1,
        bounds.memberCount)
    );
    assert.ok(SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.plusOnesCol, 1, 1));
    assert.ok(SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.actualKmCol, 1, 1));
  });

  test.it('refuses the header row, the summary band, and the formula columns', () => {
    const row = headerRow + 5;
    assert.ok(!SheetOps.isWriteWithinBand(bounds, headerRow, headerRow, bounds.plusOnesCol, 1, 1));
    assert.ok(!SheetOps.isWriteWithinBand(bounds, headerRow, 1, bounds.plusOnesCol, 1, 1));
    assert.ok(!SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.plusOnesCol + 1, 1, 1));
    assert.ok(!SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.dateCol, 1, 1));
    assert.ok(
      !SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.firstMemberCol, 1,
        bounds.memberCount + 2),
      'a slice that runs past +1\'s must be refused'
    );
    assert.ok(
      !SheetOps.isWriteWithinBand(bounds, headerRow, row, bounds.firstMemberCol, 2, 1),
      'multi-row writes are never granted'
    );
  });
});
