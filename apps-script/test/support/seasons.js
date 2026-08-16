/**
 * The season fixtures, loaded as SheetOps `grid`s (U2, test-only).
 *
 * `fixtures/attendance/2025.csv` and `2026.csv` are verbatim exports of the real
 * tabs, so a grid parsed from one is the same array-of-arrays `Range.getValues()`
 * returns for a text-formatted sheet. Everything in the geometry tests runs against
 * both seasons, because the two differ in exactly the ways that break naive parsers:
 * the header sits on a different row (2025: 10, 2026: 11) and the member band is a
 * different width (30 vs 33).
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseCsv } = require('./csv.js');

const FIXTURES_DIR = path.join(__dirname, '..', '..', '..', 'fixtures', 'attendance');

/** Seasons every table-driven test iterates. */
const SEASON_YEARS = [2025, 2026];

/**
 * @param {number} year
 * @return {!Array<!Array<string>>} The season tab as a grid.
 */
function loadSeasonGrid(year) {
  return parseCsv(fs.readFileSync(path.join(FIXTURES_DIR, `${year}.csv`), 'utf8'));
}

/** Cached grids — the CSVs are read-only fixtures; parse each once. */
const GRIDS = {};

/**
 * @param {number} year
 * @return {!Array<!Array<string>>} A fresh mutable copy of the season grid.
 */
function seasonGrid(year) {
  if (!GRIDS[year]) GRIDS[year] = loadSeasonGrid(year);
  return GRIDS[year].map((row) => row.slice());
}

/**
 * The facts about each fixture that the tests assert against, written out by hand
 * from the CSVs so a regression in the parser cannot quietly redefine "correct".
 */
const SEASON_FACTS = {
  2025: {
    headerRow: 10,
    memberCount: 30,
    actualKmCol: 5,
    plusOnesCol: 36,
    firstMemberCol: 6,
    lastMemberCol: 35,
    firstRunRow: 11,
    firstRun: { date: 'Fri, 3-Jan', meet: 'Il Lido', run: 'Soft Sand' },
    members: [
      'Aaron',
      'Adam',
      'Alex 👑',
      'Alex Kr',
      'Anna',
      'Cam',
      'Celeste',
      'Chartt',
      'Claire',
      'Col',
      'Dan',
      'Darren',
      'Fraser',
      'Grant',
      'Jack',
      'Joe',
      'Kate B',
      'Laura E',
      'Laura K',
      'Liam',
      'Ming',
      'Rhys',
      'Rohan',
      'Sam',
      'Scott',
      'Shane',
      'Tarquin',
      'Tim',
      'Toby',
      'Wes',
    ],
    // 27-Jan 2025 carries two runs: the Invasion Day half and the 10k.
    sharedDate: 'Mon, 27-Jan',
    sharedDateRuns: ['Half- Invasion Day', '10k- Invasion Day'],
  },
  2026: {
    headerRow: 11,
    memberCount: 33,
    actualKmCol: 5,
    plusOnesCol: 39,
    firstMemberCol: 6,
    lastMemberCol: 38,
    firstRunRow: 12,
    firstRun: { date: 'Fri, 2-Jan', meet: 'Il Lido', run: 'Soft Sand' },
    members: [
      'Aaron',
      'Adam',
      'Alex 👑',
      'Alex B',
      'Alex Kr',
      'Anna',
      'Cam',
      'Celeste',
      'Chartt',
      'Claire',
      'Col',
      'Dan',
      'Dan B',
      'Darren',
      'Deano',
      'Fraser',
      'Grant',
      'Jack',
      'Joe',
      'Kate B',
      'Laura E',
      'Laura K',
      'Liam',
      'Ming',
      'Rhys',
      'Rohan',
      'Sam',
      'Scott',
      'Shane',
      'Tarquin',
      'Tim',
      'Toby',
      'Wes',
    ],
    // 26-Jan 2026 carries two runs: the Invasion Day half and the 10k.
    sharedDate: 'Mon, 26-Jan',
    sharedDateRuns: ['Half - Invasion Day', '10k - Invasion Day'],
  },
};

module.exports = { FIXTURES_DIR, SEASON_YEARS, SEASON_FACTS, seasonGrid };
