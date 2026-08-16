/**
 * SheetOps — pure sheet-geometry logic (U2).
 *
 * DUAL-ENVIRONMENT MODULE PATTERN
 * ------------------------------------------------------------------------------
 * Apps Script has no module system: every top-level `function`/`var` in a pushed
 * `.js`/`.gs` file is a global, and `Code.gs` calls them directly. Node needs
 * `module.exports`. So: write plain top-level functions (Apps Script sees globals),
 * then export the same identifiers at the bottom behind a `typeof module` guard
 * (Node sees a CommonJS module, Apps Script skips the block because `module` is
 * undefined there).
 *
 * Rules that keep this working:
 *   1. No `require()` in this file — it must parse and run in Apps Script.
 *   2. Nothing here touches `SpreadsheetApp`. I/O lives in `Code.gs`; this file gets
 *      plain arrays-of-arrays in and returns plain data out. That is what makes it
 *      testable in Node against the CSV fixtures.
 *   3. `var`/`function` only at top level (no `const`-in-global collisions across
 *      files once clasp concatenates the project's globals).
 *   4. The bottom of the file gathers those functions into one `SheetOps` object.
 *      That object IS the Node export and IS the global `Code.gs` calls through, so
 *      there is a single spelling (`SheetOps.findHeaderRow`) in both environments.
 *
 * INDEX CONVENTION (read this before touching anything)
 * ------------------------------------------------------------------------------
 * Every row/column index this module ACCEPTS or RETURNS is a **1-based sheet
 * coordinate**, matching `Sheet.getRange(row, column, ...)` and the row/column
 * numbers a human sees in Google Sheets. The `grid` argument is the 0-based
 * array-of-arrays from `Range.getValues()` covering the sheet from A1, so
 * `grid[rowIndex - 1][colIndex - 1]` is the cell. `0` is the "no such row/column"
 * sentinel (there is no row 0), and it is what `findHeaderRow`/`findRunRow` return
 * when they find nothing.
 *
 * The wire contract inherits this: `roster[].colIndex` and `runs[].rowIndex` in a
 * `getState` response are sheet coordinates, so `submitAttendance { rowIndex }`
 * needs no translation and a bug report can say "row 42" and mean row 42.
 */

/** Bumped when the geometry logic changes shape. */
var SHEETOPS_VERSION = '1.0.0';

/** Header cells that bound the member band (see src/utils/dataParser.js). */
var MEMBER_BAND_START_AFTER = 'Actual kms';
var MEMBER_BAND_END_BEFORE = "+1's";

/** Fixed columns that precede the member band, in order (mirrors dataParser.js). */
var FIXED_LEADING_COLS = ['Date', 'Meet', 'Run', 'Approx kms', 'Actual kms'];

/** Sentinel for "no such row/column" (sheet coordinates are 1-based). */
var NO_INDEX = 0;

/** Month order used to sort `12-Jan`-style season dates. */
var MONTH_ABBREVS = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/** Day-of-week prefixes used when a Date object has to be rendered sheet-style. */
var DAY_ABBREVS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** Title-cased month abbreviations, for the same rendering. */
var MONTH_TITLES = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/** The mark written into a member cell for "attended". */
var ATTENDED_MARK = 'x';

/**
 * Trim a raw cell to the string form the rest of the logic compares against.
 * Deliberately conservative: it must NOT normalize case or strip emoji, because
 * sheet header text (e.g. "Alex 👑") is the canonical member key.
 *
 * @param {*} value Raw cell value from the sheet or a parsed CSV.
 * @return {string} The cell as a trimmed string ('' for null/undefined).
 */
function cellText(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

/**
 * Render a Date cell the way the sheet's own Date column is written
 * ("Fri, 3-Jan"), and pass strings through untouched.
 *
 * `Range.getValues()` hands back a real `Date` when the cell is date-typed and a
 * `String` when it is text. The FCTC sheet uses text today, but a single
 * re-typed cell would otherwise turn a run's identity into
 * "Fri Jan 03 2025 00:00:00 GMT+0800 (...)" and break `expectedDate` matching.
 *
 * @param {*} value Raw Date cell value.
 * @return {string} Sheet-style date text.
 */
function dateCellText(value) {
  if (value instanceof Date && !isNaN(value.getTime())) {
    return (
      DAY_ABBREVS[value.getDay()] +
      ', ' +
      value.getDate() +
      '-' +
      MONTH_TITLES[value.getMonth()]
    );
  }
  return cellText(value);
}

/**
 * Fold a name/label to the key used for comparison and ordering:
 * diacritic-, case-, emoji- and punctuation-insensitive.
 *
 * `Alex 👑` and `alex` collapse to the same key, which is what makes "Alex 👑
 * sorts as Alex" and "`col` duplicates `Col`" both fall out of one rule.
 *
 * @param {*} value Raw name.
 * @return {string} Normalized comparison key ('' when there is nothing to compare).
 */
function normalizeKey(value) {
  var text = cellText(value);
  if (!text) return '';
  if (typeof text.normalize === 'function') {
    // Split accents off their base letters, then drop the combining marks.
    text = text.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }
  text = text.toLowerCase();
  // Anything that is not a latin letter or digit (emoji, apostrophes, dashes,
  // stray punctuation) becomes a separator rather than part of the key.
  text = text.replace(/[^a-z0-9]+/g, ' ');
  return text.replace(/\s+/g, ' ').replace(/^ | $/g, '');
}

/**
 * Order two names the way the member band is ordered.
 *
 * Compares normalized keys with plain code-unit `<`/`>` — NOT `localeCompare`,
 * whose collation differs between Node and Apps Script and would make the
 * alphabetical insert position environment-dependent.
 *
 * @param {*} a
 * @param {*} b
 * @return {number} -1, 0 or 1.
 */
function compareNames(a, b) {
  var ka = normalizeKey(a);
  var kb = normalizeKey(b);
  if (ka < kb) return -1;
  if (ka > kb) return 1;
  // Stable tie-break so equal keys ("Col"/"col") still order deterministically.
  var ra = cellText(a);
  var rb = cellText(b);
  if (ra < rb) return -1;
  if (ra > rb) return 1;
  return 0;
}

/**
 * Locate the self-describing header row by CONTENT, not by index — the number of
 * notes/summary rows above it drifts between seasons (2025: row 10, 2026: row 11).
 *
 * Ported from `src/utils/dataParser.js`: first cell is `Date`, and the row also
 * contains `Run` and `Actual kms`.
 *
 * @param {!Array<!Array<*>>} grid Sheet values from A1, 0-based array-of-arrays.
 * @return {number} 1-based header row, or `NO_INDEX` (0) when absent.
 */
function findHeaderRow(grid) {
  if (!grid || !grid.length) return NO_INDEX;
  for (var r = 0; r < grid.length; r++) {
    var row = grid[r];
    if (!row || !row.length) continue;
    if (cellText(row[0]) !== 'Date') continue;
    var hasRun = false;
    var hasActualKms = false;
    for (var c = 0; c < row.length; c++) {
      var text = cellText(row[c]);
      if (text === 'Run') hasRun = true;
      else if (text === MEMBER_BAND_START_AFTER) hasActualKms = true;
    }
    if (hasRun && hasActualKms) return r + 1;
  }
  return NO_INDEX;
}

/**
 * Index of a header cell whose text matches exactly.
 *
 * @param {!Array<*>} headerCells Raw header row.
 * @param {string} label
 * @return {number} 1-based column, or `NO_INDEX`.
 */
function headerColumn(headerCells, label) {
  for (var c = 0; c < headerCells.length; c++) {
    if (cellText(headerCells[c]) === label) return c + 1;
  }
  return NO_INDEX;
}

/**
 * Column geometry of a season tab: where the fixed columns are, and exactly which
 * columns the member band occupies.
 *
 * Every writer in `Code.gs` goes through this so the sheet-safety invariant ("never
 * write outside the member band + Actual kms + +1's") has ONE definition.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based, from `findHeaderRow`.
 * @return {?{headerRow: number, dateCol: number, meetCol: number, runCol: number,
 *     approxKmCol: number, actualKmCol: number, plusOnesCol: number,
 *     firstMemberCol: number, lastMemberCol: number, memberCount: number}}
 *     Null when the header row does not describe a usable band.
 */
function bandBounds(grid, headerRow) {
  if (!grid || !headerRow || headerRow < 1 || headerRow > grid.length) return null;
  var headerCells = grid[headerRow - 1] || [];
  var actualKmCol = headerColumn(headerCells, MEMBER_BAND_START_AFTER);
  var plusOnesCol = headerColumn(headerCells, MEMBER_BAND_END_BEFORE);
  if (!actualKmCol || !plusOnesCol || plusOnesCol <= actualKmCol) return null;
  return {
    headerRow: headerRow,
    dateCol: headerColumn(headerCells, 'Date'),
    meetCol: headerColumn(headerCells, 'Meet'),
    runCol: headerColumn(headerCells, 'Run'),
    approxKmCol: headerColumn(headerCells, 'Approx kms'),
    actualKmCol: actualKmCol,
    plusOnesCol: plusOnesCol,
    firstMemberCol: actualKmCol + 1,
    lastMemberCol: plusOnesCol - 1,
    memberCount: plusOnesCol - actualKmCol - 1,
  };
}

/**
 * The member roster, read from the header row: every column STRICTLY between
 * `Actual kms` and `+1's` (2025 → 30 members, 2026 → 33).
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @return {!Array<{name: string, colIndex: number}>} In sheet order; `colIndex` is
 *     the 1-based sheet column.
 */
function memberBand(grid, headerRow) {
  var bounds = bandBounds(grid, headerRow);
  if (!bounds) return [];
  var headerCells = grid[headerRow - 1] || [];
  var band = [];
  for (var col = bounds.firstMemberCol; col <= bounds.lastMemberCol; col++) {
    var name = cellText(headerCells[col - 1]);
    // A blank header cell inside the band is a spacer, not a member; skipping it
    // keeps the roster honest without disturbing anyone's column index.
    if (!name) continue;
    band.push({ name: name, colIndex: col });
  }
  return band;
}

/**
 * Header row + band bounds + roster in one call — the single geometry entry point
 * `Code.gs` uses, so the impure shell never re-derives any of it.
 *
 * @param {!Array<!Array<*>>} grid
 * @return {?{headerRow: number, bounds: !Object, band: !Array<!Object>}}
 *     Null when the tab has no recognisable header row / band.
 */
function sheetGeometry(grid) {
  var headerRow = findHeaderRow(grid);
  if (!headerRow) return null;
  var bounds = bandBounds(grid, headerRow);
  if (!bounds) return null;
  return { headerRow: headerRow, bounds: bounds, band: memberBand(grid, headerRow) };
}

/**
 * Parse a season date cell ("Fri, 3-Jan", "26-Jan", or a real Date) into sortable
 * parts. The sheet carries no year — a season tab IS the year.
 *
 * @param {*} value
 * @return {?{month: number, day: number}} month is 0-based; null when unparseable.
 */
function parseSheetDate(value) {
  if (value instanceof Date && !isNaN(value.getTime())) {
    return { month: value.getMonth(), day: value.getDate() };
  }
  var text = cellText(value);
  if (!text) return null;
  var match = text.match(/(\d{1,2})\s*[-/ ]\s*([A-Za-z]{3,})/);
  if (!match) return null;
  var month = MONTH_ABBREVS.indexOf(match[2].slice(0, 3).toLowerCase());
  if (month < 0) return null;
  var day = parseInt(match[1], 10);
  if (!(day >= 1 && day <= 31)) return null;
  return { month: month, day: day };
}

/**
 * Sort key for a season date: month * 100 + day. Unparseable dates sort last.
 *
 * @param {*} value
 * @return {number}
 */
function dateOrdinal(value) {
  var parsed = parseSheetDate(value);
  if (!parsed) return Number.MAX_SAFE_INTEGER;
  return parsed.month * 100 + parsed.day;
}

/**
 * Numeric cell value, or null when the cell is blank/not a number. Blank must stay
 * distinguishable from 0 — "no distance recorded yet" is not "ran 0 km".
 *
 * @param {*} value
 * @return {?number}
 */
function numberOrNull(value) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value === 'number') return isNaN(value) ? null : value;
  var text = cellText(value).replace(/,/g, '');
  if (!text) return null;
  var parsed = parseFloat(text);
  return isNaN(parsed) ? null : parsed;
}

/**
 * Whether a member cell counts as "attended".
 *
 * Matches `src/utils/dataParser.js`: `x` attends; blank and `-` (the sheet's
 * "away / not recorded" marker) do not.
 *
 * @param {*} value
 * @return {boolean}
 */
function isAttendedMark(value) {
  var text = cellText(value);
  if (!text) return false;
  if (text === '-') return false;
  return true;
}

/**
 * Is this row below the header a real run row?
 *
 * A run row has a parseable date in the Date column. Requiring a PARSEABLE date
 * (not merely a non-empty cell) is what keeps a stray "Totals"/notes row under the
 * run band from being served to the app as a run.
 *
 * @param {!Array<*>} row
 * @param {!Object} bounds
 * @return {boolean}
 */
function isRunRow(row, bounds) {
  if (!row || !row.length) return false;
  return parseSheetDate(row[bounds.dateCol - 1]) !== null;
}

/**
 * Read one run row into the wire shape `getState` serves.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {!Object} bounds From `bandBounds`.
 * @param {!Array<{name: string, colIndex: number}>} band
 * @param {number} rowIndex 1-based sheet row.
 * @return {?{rowIndex: number, date: string, meet: string, run: string,
 *     approxKm: ?number, actualKm: ?number, attendees: !Array<string>,
 *     plusOnes: number}} Null when the row is not a run row.
 */
function readRun(grid, bounds, band, rowIndex) {
  if (!grid || rowIndex < 1 || rowIndex > grid.length) return null;
  var row = grid[rowIndex - 1] || [];
  if (!isRunRow(row, bounds)) return null;
  var attendees = [];
  for (var i = 0; i < band.length; i++) {
    if (isAttendedMark(row[band[i].colIndex - 1])) attendees.push(band[i].name);
  }
  return {
    rowIndex: rowIndex,
    date: dateCellText(row[bounds.dateCol - 1]),
    meet: cellText(row[bounds.meetCol - 1]),
    run: cellText(row[bounds.runCol - 1]),
    approxKm: numberOrNull(row[bounds.approxKmCol - 1]),
    actualKm: numberOrNull(row[bounds.actualKmCol - 1]),
    attendees: attendees,
    plusOnes: numberOrNull(row[bounds.plusOnesCol - 1]) || 0,
  };
}

/**
 * Every run row below the header, in sheet order.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @return {!Array<!Object>} Run records (see `readRun`).
 */
function listRuns(grid, headerRow) {
  var bounds = bandBounds(grid, headerRow);
  if (!bounds) return [];
  var band = memberBand(grid, headerRow);
  var runs = [];
  for (var r = headerRow + 1; r <= grid.length; r++) {
    var run = readRun(grid, bounds, band, r);
    if (run) runs.push(run);
  }
  return runs;
}

/**
 * Lifetime attendance count per member for ONE season tab.
 *
 * Attendance is `isAttendedMark`, not a literal "x". The real sheet also records
 * a per-person distance ("12.30"), the odd emoji, and free text; only blank and
 * "-" mean absent. This matches `src/utils/dataParser.js` on main, which is what
 * the weekly milestone email counts, so both surfaces agree on a person's total.
 *
 * @param {!Array<!Array<*>>} grid One tab's values.
 * @return {!Array<{name: string, runs: number}>} In sheet order. Members with no
 *     attendance are present with `runs: 0`, so a caller can tell "nobody yet"
 *     apart from "not on this tab".
 */
function attendanceTotals(grid) {
  var geometry = sheetGeometry(grid);
  if (!geometry) return [];
  var totals = [];
  for (var i = 0; i < geometry.band.length; i++) {
    var member = geometry.band[i];
    var runs = 0;
    for (var r = geometry.headerRow + 1; r <= grid.length; r++) {
      var row = grid[r - 1] || [];
      // isRunRow keeps summary and notes rows under the band out of the count.
      if (!isRunRow(row, geometry.bounds)) continue;
      if (isAttendedMark(row[member.colIndex - 1])) runs++;
    }
    totals.push({ name: member.name, runs: runs });
  }
  return totals;
}

/**
 * Is this tab name a season, i.e. exactly four digits ("2025", "2026")?
 *
 * Lifetime totals span every season, so `Code.gs` discovers tabs by name rather
 * than carrying a second script property that must be updated each January.
 *
 * @param {*} name
 * @return {boolean}
 */
function isSeasonTabName(name) {
  return /^\d{4}$/.test(cellText(name));
}

/**
 * The raw member-band cell values of a run row, aligned to `band` order.
 *
 * `buildRowWrite` needs the RAW values, not the derived attendee list: a `-`
 * ("away") marker must survive a write that does not concern that member.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @param {number} rowIndex 1-based.
 * @return {!Array<string>} One entry per band member.
 */
function memberValuesAt(grid, headerRow, rowIndex) {
  var band = memberBand(grid, headerRow);
  var row = (grid && grid[rowIndex - 1]) || [];
  var values = [];
  for (var i = 0; i < band.length; i++) values.push(cellText(row[band[i].colIndex - 1]));
  return values;
}

/**
 * Do two date/run pairs identify the same run?
 *
 * Dates compare on their parsed (month, day) so "26-Jan" matches "Mon, 26-Jan";
 * run labels compare on normalized keys so "Half - Invasion Day" matches
 * "Half- Invasion Day" (the seasons punctuate them differently).
 *
 * @param {*} dateA
 * @param {*} runA
 * @param {*} dateB
 * @param {*} runB
 * @return {boolean}
 */
function sameRunIdentity(dateA, runA, dateB, runB) {
  var pa = parseSheetDate(dateA);
  var pb = parseSheetDate(dateB);
  if (pa && pb) {
    if (pa.month !== pb.month || pa.day !== pb.day) return false;
  } else if (normalizeKey(dateCellText(dateA)) !== normalizeKey(dateCellText(dateB))) {
    return false;
  }
  return normalizeKey(runA) === normalizeKey(runB);
}

/**
 * Every run row matching a date + run label.
 *
 * Two runs can share a date (26-Jan 2026: "Half - Invasion Day" and
 * "10k - Invasion Day"), which is exactly why the run label is part of the
 * identity and why this returns a list.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @param {{date: *, run: *}} identity
 * @return {!Array<number>} 1-based row indices, in sheet order.
 */
function findRunRows(grid, headerRow, identity) {
  var bounds = bandBounds(grid, headerRow);
  if (!bounds || !identity) return [];
  var matches = [];
  for (var r = headerRow + 1; r <= grid.length; r++) {
    var row = grid[r - 1] || [];
    if (!isRunRow(row, bounds)) continue;
    if (
      sameRunIdentity(
        row[bounds.dateCol - 1],
        row[bounds.runCol - 1],
        identity.date,
        identity.run
      )
    ) {
      matches.push(r);
    }
  }
  return matches;
}

/**
 * The single run row matching a date + run label.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @param {{date: *, run: *}} identity
 * @return {number} 1-based row, or `NO_INDEX` when there is no unambiguous match.
 */
function findRunRow(grid, headerRow, identity) {
  var matches = findRunRows(grid, headerRow, identity);
  return matches.length === 1 ? matches[0] : NO_INDEX;
}

/**
 * FNV-1a (32-bit), applied to UTF-16 code units so Node and Apps Script agree.
 *
 * @param {string} text
 * @param {number} seed Offset basis; two seeds give a 64-bit-ish combined digest.
 * @return {number} Unsigned 32-bit hash.
 */
function fnv1a(text, seed) {
  var hash = seed >>> 0;
  for (var i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i) & 0xffff;
    // hash *= 16777619, done in 16-bit halves to stay inside float53 precision.
    hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))) >>> 0;
  }
  return hash >>> 0;
}

/**
 * Left-pad a number's hex form to 8 digits.
 *
 * @param {number} value
 * @return {string}
 */
function toHex8(value) {
  var hex = (value >>> 0).toString(16);
  while (hex.length < 8) hex = '0' + hex;
  return hex;
}

/**
 * Stable revision hash of everything the app can see and change: the header row
 * (roster identity) plus every run row's cells from `Date` through `+1's`.
 *
 * Deliberately EXCLUDES the notes/summary rows above the header and the derived
 * formula columns to the right of `+1's` — those recalculate on their own schedule
 * and would produce phantom conflicts.
 *
 * @param {!Array<!Array<*>>} grid
 * @param {number} headerRow 1-based.
 * @return {string} 16 hex chars, or '' when the tab has no usable band.
 */
function revisionHash(grid, headerRow) {
  var bounds = bandBounds(grid, headerRow);
  if (!bounds) return '';
  var parts = [];
  var lastCol = bounds.plusOnesCol;
  var appendRow = function (rowIndex) {
    var row = grid[rowIndex - 1] || [];
    var cells = [];
    for (var c = 1; c <= lastCol; c++) {
      var value = row[c - 1];
      cells.push(c === bounds.dateCol ? dateCellText(value) : cellText(value));
    }
    parts.push(cells.join(''));
  };
  appendRow(headerRow);
  for (var r = headerRow + 1; r <= grid.length; r++) {
    if (isRunRow(grid[r - 1] || [], bounds)) appendRow(r);
  }
  var text = parts.join('');
  // Two independent seeds, concatenated: collisions need both to collide.
  return toHex8(fnv1a(text, 0x811c9dc5)) + toHex8(fnv1a(text, 0x01000193));
}

/**
 * Position of an existing member in the band, under the same normalization used
 * for duplicate detection (`col` finds `Col`).
 *
 * @param {!Array<{name: string, colIndex: number}|string>} band
 * @param {string} name
 * @return {number} 0-based position within `band`, or -1.
 */
function findMemberIndex(band, name) {
  var key = normalizeKey(name);
  if (!key) return -1;
  for (var i = 0; i < band.length; i++) {
    var entry = band[i];
    var entryName = typeof entry === 'string' ? entry : entry.name;
    if (normalizeKey(entryName) === key) return i;
  }
  return -1;
}

/**
 * Where a new member belongs in the alphabetically-ordered band.
 *
 * Normalization drives the ordering, so `Alex 👑` sorts as `Alex` and `Alex B`
 * lands between `Alex 👑` and `Alex Kr`; a shorter prefix sorts first, so `Dan B`
 * follows `Dan`.
 *
 * @param {!Array<{name: string, colIndex: number}|string>} band
 * @param {string} newName
 * @return {number} 0-based position within `band` (== band.length means append).
 */
function alphabeticalInsertIndex(band, newName) {
  for (var i = 0; i < band.length; i++) {
    var entry = band[i];
    var entryName = typeof entry === 'string' ? entry : entry.name;
    if (compareNames(entryName, newName) > 0) return i;
  }
  return band.length;
}

/**
 * Where and how a new member's column gets inserted, given the band position from
 * `alphabeticalInsertIndex`.
 *
 * The smoke test (2026-08-14, real sheet copy) settled the edge case the U2
 * handoff flagged: Google Sheets widens a run row's COUNTIF range only when a
 * column is inserted strictly INSIDE it. Inserting before `+1's` (the old
 * append strategy) lands one past the range's final column, the range stays
 * narrow, and the new member's `x`s become invisible to the sheet's own totals.
 *
 * So a member who sorts last inserts before the CURRENT last member (inside
 * every range), and the caller then relocates the displaced member's cells into
 * the new column so alphabetical order still holds:
 *
 *   - `insertBefore` — 1-based column to pass to `insertColumnBefore`.
 *   - `relocateDisplaced` — true only for the sorts-last case.
 *   - `displacedCol` — where the displaced member sits AFTER the insert (and
 *     where the new member's header belongs once the relocation is done).
 *
 * @param {!Array<{name: string, colIndex: number}>} band
 * @param {!Object} bounds
 * @param {number} position 0-based band position.
 * @return {{insertBefore: number, relocateDisplaced: boolean,
 *     displacedCol: number}}
 */
function memberInsertPlan(band, bounds, position) {
  if (position < band.length) {
    return {
      insertBefore: band[position].colIndex,
      relocateDisplaced: false,
      displacedCol: 0,
    };
  }
  var lastMemberCol = band.length
    ? band[band.length - 1].colIndex
    : bounds.plusOnesCol;
  return {
    insertBefore: lastMemberCol,
    relocateDisplaced: band.length > 0,
    displacedCol: lastMemberCol + 1,
  };
}

/**
 * Build the exact cell values a `submitAttendance` should write.
 *
 * Modes (Q1 resolved: overwrite may uncheck):
 *   - `merge`     — union with what is already on the row; never clears a mark.
 *   - `overwrite` — absolute; members absent from `attendees` have their `x`
 *                   cleared.
 *
 * In BOTH modes a non-`x` marker that is already in a cell (the sheet's `-`
 * "away / not recorded") is preserved unless that member is now an attendee.
 * Clearing only ever turns an `x` into a blank, so an overwrite cannot silently
 * destroy Colin's hand-entered annotations.
 *
 * `plusOnes`/`actualKm` are absolute values, and `null`/`undefined` means "the
 * client had nothing to say" → keep whatever the sheet has (the app frequently has
 * no distance; the sheet often does).
 *
 * @param {!Array<{name: string, colIndex: number}>} band
 * @param {!Array<string>} attendees Canonical sheet names.
 * @param {?number} plusOnes
 * @param {?number} actualKm
 * @param {{mode: string, existingValues: !Array<*>, existingPlusOnes: ?number,
 *     existingActualKm: ?number}=} options Existing row state; omitting it is
 *     equivalent to writing onto an empty row.
 * @return {{mode: string, memberValues: !Array<string>, attendees: !Array<string>,
 *     plusOnes: ?number, actualKm: ?number, writePlusOnes: boolean,
 *     writeActualKm: boolean, unknownNames: !Array<string>, changedCells: number}}
 */
function buildRowWrite(band, attendees, plusOnes, actualKm, options) {
  var opts = options || {};
  var mode = opts.mode === 'overwrite' ? 'overwrite' : 'merge';
  var existingValues = opts.existingValues || [];

  // Map every requested attendee onto a band position, collecting the misses so
  // the caller can reject the payload rather than silently dropping a person.
  var wanted = {};
  var unknownNames = [];
  var requested = attendees || [];
  for (var i = 0; i < requested.length; i++) {
    var position = findMemberIndex(band, requested[i]);
    if (position < 0) {
      if (cellText(requested[i])) unknownNames.push(cellText(requested[i]));
      continue;
    }
    wanted[position] = true;
  }

  var memberValues = [];
  var finalAttendees = [];
  var changedCells = 0;
  for (var p = 0; p < band.length; p++) {
    var existing = cellText(existingValues[p]);
    var existingAttended = isAttendedMark(existing);
    var value;
    if (wanted[p]) {
      value = ATTENDED_MARK;
    } else if (mode === 'overwrite' && existingAttended) {
      value = '';
    } else {
      // merge: keep the mark. Either mode: keep a non-attendance marker ('-').
      value = existing;
    }
    if (value !== existing) changedCells++;
    memberValues.push(value);
    if (isAttendedMark(value)) finalAttendees.push(band[p].name);
  }

  var submittedPlusOnes = numberOrNull(plusOnes);
  var existingPlusOnes = numberOrNull(opts.existingPlusOnes);
  var finalPlusOnes = null;
  if (submittedPlusOnes === null) {
    finalPlusOnes = null; // nothing to say → leave the cell alone
  } else if (mode === 'merge' && existingPlusOnes !== null) {
    // Union-flavoured: merging two partial reports must not lose guests.
    finalPlusOnes = Math.max(submittedPlusOnes, existingPlusOnes);
  } else {
    finalPlusOnes = submittedPlusOnes;
  }
  var writePlusOnes = finalPlusOnes !== null && finalPlusOnes !== existingPlusOnes;
  if (writePlusOnes) changedCells++;

  var submittedActualKm = numberOrNull(actualKm);
  var existingActualKm = numberOrNull(opts.existingActualKm);
  var writeActualKm = submittedActualKm !== null && submittedActualKm !== existingActualKm;
  if (writeActualKm) changedCells++;

  return {
    mode: mode,
    memberValues: memberValues,
    attendees: finalAttendees,
    plusOnes: finalPlusOnes,
    actualKm: submittedActualKm,
    writePlusOnes: writePlusOnes,
    writeActualKm: writeActualKm,
    unknownNames: unknownNames,
    changedCells: changedCells,
  };
}

/**
 * Where a new run belongs among the existing run rows, by season date.
 *
 * Ties append AFTER the runs already on that date, so a second 26-Jan run lands
 * below the first. Runs whose date will not parse are treated as "end of season"
 * and stay at the bottom.
 *
 * @param {!Array<{date: *}>} runs Run records in sheet order (from `listRuns`).
 * @param {*} newDate
 * @return {number} 0-based position within `runs` (== runs.length means append).
 */
function dateOrderedInsertIndex(runs, newDate) {
  var target = dateOrdinal(newDate);
  var list = runs || [];
  for (var i = 0; i < list.length; i++) {
    if (dateOrdinal(list[i].date) > target) return i;
  }
  return list.length;
}

/**
 * The 1-based sheet row a new run's inserted row should occupy.
 *
 * @param {!Array<{rowIndex: number, date: *}>} runs In sheet order.
 * @param {number} headerRow 1-based.
 * @param {*} newDate
 * @return {{position: number, rowIndex: number, append: boolean}} `append` means
 *     "there is no row to insert before; add after the last run row".
 */
function runInsertTarget(runs, headerRow, newDate) {
  var list = runs || [];
  var position = dateOrderedInsertIndex(list, newDate);
  if (position < list.length) {
    return { position: position, rowIndex: list[position].rowIndex, append: false };
  }
  var lastRow = list.length ? list[list.length - 1].rowIndex : headerRow;
  return { position: position, rowIndex: lastRow + 1, append: true };
}

/**
 * Sheet-safety gate: is a write rectangle confined to the cells this API is allowed
 * to touch on an existing run row (member band + `Actual kms` + `+1's`)?
 *
 * `Code.gs` calls this immediately before every `setValue(s)` so the invariant is
 * enforced by code, not by careful reading.
 *
 * @param {!Object} bounds From `bandBounds`.
 * @param {number} headerRow 1-based.
 * @param {number} row 1-based.
 * @param {number} col 1-based.
 * @param {number} numRows
 * @param {number} numCols
 * @return {boolean}
 */
function isWriteWithinBand(bounds, headerRow, row, col, numRows, numCols) {
  if (!bounds) return false;
  if (!(numRows === 1)) return false;
  if (!(row > headerRow)) return false;
  var lastCol = col + numCols - 1;
  if (col < bounds.actualKmCol || lastCol > bounds.plusOnesCol) return false;
  return true;
}

/**
 * Module health/introspection, used by the Node smoke test and handy from the Apps
 * Script editor to confirm which version is deployed.
 *
 * @return {{module: string, version: string, implemented: !Array<string>}}
 */
function sheetOpsHealth() {
  return {
    module: 'SheetOps',
    version: SHEETOPS_VERSION,
    implemented: [
      'cellText',
      'dateCellText',
      'normalizeKey',
      'compareNames',
      'findHeaderRow',
      'headerColumn',
      'bandBounds',
      'memberBand',
      'sheetGeometry',
      'parseSheetDate',
      'dateOrdinal',
      'numberOrNull',
      'isAttendedMark',
      'isRunRow',
      'readRun',
      'listRuns',
      'memberValuesAt',
      'sameRunIdentity',
      'findRunRows',
      'findRunRow',
      'revisionHash',
      'findMemberIndex',
      'alphabeticalInsertIndex',
      'memberInsertPlan',
      'buildRowWrite',
      'dateOrderedInsertIndex',
      'runInsertTarget',
      'isWriteWithinBand',
      'sheetOpsHealth',
    ],
  };
}

/**
 * The namespace `Code.gs` calls through (`SheetOps.findHeaderRow(...)`).
 *
 * In Apps Script this is just another global, defined once all the function
 * declarations above have hoisted; in Node it is what `require()` hands back.
 * Having a named namespace (rather than bare globals) is deliberate: it makes
 * "the impure shell asks SheetOps for every geometry decision" visible at each
 * call site in `Code.gs`.
 */
var SheetOps = {
  SHEETOPS_VERSION: SHEETOPS_VERSION,
  MEMBER_BAND_START_AFTER: MEMBER_BAND_START_AFTER,
  MEMBER_BAND_END_BEFORE: MEMBER_BAND_END_BEFORE,
  FIXED_LEADING_COLS: FIXED_LEADING_COLS,
  NO_INDEX: NO_INDEX,
  ATTENDED_MARK: ATTENDED_MARK,
  cellText: cellText,
  dateCellText: dateCellText,
  normalizeKey: normalizeKey,
  compareNames: compareNames,
  findHeaderRow: findHeaderRow,
  headerColumn: headerColumn,
  bandBounds: bandBounds,
  memberBand: memberBand,
  sheetGeometry: sheetGeometry,
  parseSheetDate: parseSheetDate,
  dateOrdinal: dateOrdinal,
  numberOrNull: numberOrNull,
  isAttendedMark: isAttendedMark,
  isRunRow: isRunRow,
  readRun: readRun,
  listRuns: listRuns,
  attendanceTotals: attendanceTotals,
  isSeasonTabName: isSeasonTabName,
  memberValuesAt: memberValuesAt,
  sameRunIdentity: sameRunIdentity,
  findRunRows: findRunRows,
  findRunRow: findRunRow,
  revisionHash: revisionHash,
  findMemberIndex: findMemberIndex,
  alphabeticalInsertIndex: alphabeticalInsertIndex,
  memberInsertPlan: memberInsertPlan,
  buildRowWrite: buildRowWrite,
  dateOrderedInsertIndex: dateOrderedInsertIndex,
  runInsertTarget: runInsertTarget,
  isWriteWithinBand: isWriteWithinBand,
  sheetOpsHealth: sheetOpsHealth,
};

/* eslint-disable no-undef */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = SheetOps;
}
