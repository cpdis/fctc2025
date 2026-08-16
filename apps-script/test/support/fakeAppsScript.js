/**
 * An in-memory Google Apps Script runtime, just big enough to run `Code.gs` (U2,
 * test-only).
 *
 * Why this exists: `Code.gs` is the impure half of the unit — the router, the secret
 * check, the lock, the conflict decisions, and above all the WRITES. None of that is
 * exercised by testing `SheetOps.js` alone, and none of it can be run for real
 * without a live spreadsheet. So the two sources are evaluated inside a `node:vm`
 * context whose globals are fakes of the four Apps Script services they touch
 * (`SpreadsheetApp`, `PropertiesService`, `LockService`, `ContentService`).
 *
 * The fake sheet records every `setValue(s)`/insert, which is what lets the tests
 * assert the sheet-safety invariant directly ("no write ever landed outside the
 * member band") instead of taking `Code.gs`'s word for it.
 *
 * Scope note: this is a behavioural stand-in, not an emulator. It does not evaluate
 * formulas, so anything about formula RE-CALCULATION or range auto-expansion on
 * insert is explicitly out of scope here and belongs to `test/smoke.md`, which Colin
 * runs once against a copy of the real sheet.
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const APPS_SCRIPT_DIR = path.join(__dirname, '..', '..');

/**
 * Pad a ragged array-of-arrays (CSV rows differ in length) into a rectangle, the
 * way `Range.getValues()` always hands back a rectangle.
 *
 * @param {!Array<!Array<*>>} grid
 * @return {!Array<!Array<*>>} A rectangular deep copy.
 */
function rectangular(grid) {
  const width = grid.reduce((max, row) => Math.max(max, row.length), 0);
  return grid.map((row) => {
    const copy = row.slice();
    while (copy.length < width) copy.push('');
    return copy;
  });
}

/**
 * A single fake sheet tab backed by a mutable grid.
 */
class FakeSheet {
  /**
   * @param {string} name Tab name.
   * @param {!Array<!Array<*>>} grid Initial values (ragged is fine).
   */
  constructor(name, grid) {
    this.name = name;
    this.values = rectangular(grid);
    /** Every write and structural change, in order, for assertions. */
    this.writes = [];
  }

  getName() {
    return this.name;
  }

  getLastRow() {
    return this.values.length;
  }

  getLastColumn() {
    return this.values.length ? this.values[0].length : 0;
  }

  /** @return {!Array<!Array<*>>} A snapshot copy, like the real API. */
  snapshot() {
    return this.values.map((row) => row.slice());
  }

  getDataRange() {
    return this.getRange(1, 1, this.values.length, this.getLastColumn());
  }

  /**
   * @param {number} row 1-based.
   * @param {number} col 1-based.
   * @param {number=} numRows
   * @param {number=} numCols
   * @return {!FakeRange}
   */
  getRange(row, col, numRows, numCols) {
    return new FakeRange(
      this,
      row,
      col,
      numRows === undefined ? 1 : numRows,
      numCols === undefined ? 1 : numCols
    );
  }

  /**
   * Grow the grid so (row, col) exists, mirroring a real sheet's blank cells.
   *
   * @param {number} row 1-based.
   * @param {number} col 1-based.
   */
  ensure_(row, col) {
    const width = Math.max(this.getLastColumn(), col);
    while (this.values.length < row) this.values.push([]);
    for (const line of this.values) {
      while (line.length < width) line.push('');
    }
  }

  /** @param {number} col 1-based column to insert before. */
  insertColumnBefore(col) {
    for (const row of this.values) row.splice(col - 1, 0, '');
    this.writes.push({ kind: 'insertColumnBefore', col });
  }

  /** @param {number} row 1-based row to insert before. */
  insertRowBefore(row) {
    this.values.splice(row - 1, 0, new Array(this.getLastColumn()).fill(''));
    this.writes.push({ kind: 'insertRowBefore', row });
  }

  /** @param {number} row 1-based row to insert after. */
  insertRowAfter(row) {
    this.values.splice(row, 0, new Array(this.getLastColumn()).fill(''));
    this.writes.push({ kind: 'insertRowAfter', row });
  }
}

/**
 * A rectangular range over a `FakeSheet`.
 */
class FakeRange {
  /**
   * @param {!FakeSheet} sheet
   * @param {number} row 1-based.
   * @param {number} col 1-based.
   * @param {number} numRows
   * @param {number} numCols
   */
  constructor(sheet, row, col, numRows, numCols) {
    this.sheet = sheet;
    this.row = row;
    this.col = col;
    this.numRows = numRows;
    this.numCols = numCols;
  }

  getValues() {
    const out = [];
    for (let r = this.row; r < this.row + this.numRows; r++) {
      const line = this.sheet.values[r - 1] || [];
      const cells = [];
      for (let c = this.col; c < this.col + this.numCols; c++) {
        cells.push(line[c - 1] === undefined ? '' : line[c - 1]);
      }
      out.push(cells);
    }
    return out;
  }

  /**
   * @param {!Array<!Array<*>>} values
   * @return {!FakeRange} this
   */
  setValues(values) {
    this.sheet.ensure_(this.row + this.numRows - 1, this.col + this.numCols - 1);
    for (let r = 0; r < this.numRows; r++) {
      for (let c = 0; c < this.numCols; c++) {
        this.sheet.values[this.row + r - 1][this.col + c - 1] = values[r][c];
      }
    }
    this.sheet.writes.push({
      kind: 'setValues',
      row: this.row,
      col: this.col,
      numRows: this.numRows,
      numCols: this.numCols,
      values: values.map((line) => line.slice()),
    });
    return this;
  }

  /**
   * @param {*} value
   * @return {!FakeRange} this
   */
  setValue(value) {
    return this.setValues([[value]]);
  }

  /**
   * Formula copy. The fake has no formulas, so this records the intent (which is
   * what the tests assert) and copies the literal values across.
   *
   * @param {!FakeRange} target
   */
  copyTo(target) {
    const values = this.getValues();
    this.sheet.writes.push({
      kind: 'copyTo',
      fromRow: this.row,
      fromCol: this.col,
      toRow: target.row,
      toCol: target.col,
      numRows: this.numRows,
      numCols: this.numCols,
    });
    target.setValues(values);
  }
}

/**
 * Build a runnable Apps Script environment around one season grid.
 *
 * @param {{grid: !Array<!Array<*>>, sheetName?: string, secret?: string,
 *     properties?: !Object<string, string>, lockHeld?: boolean}} options
 * @return {{sheet: !FakeSheet, context: !Object, secret: string,
 *     post: function(!Object): !Object, raw: function(string): !Object,
 *     writes: function(): !Array<!Object>, grid: function(): !Array<!Array<*>>}}
 */
function createEnvironment(options) {
  const sheetName = options.sheetName || '2026';
  const secret = options.secret === undefined ? 'test-secret' : options.secret;
  const sheet = new FakeSheet(sheetName, options.grid);
  // Lifetime totals read every season tab, so the fake spreadsheet has to be able
  // to hold more than the one writable season.
  const extraSheets = (options.extraSheets || []).map(
    (extra) => new FakeSheet(extra.name, extra.grid)
  );
  const allSheets = [sheet].concat(extraSheets);
  const properties = Object.assign(
    { SHARED_SECRET: secret, SEASON_SHEET_NAME: sheetName },
    options.properties || {}
  );

  let lockHeld = Boolean(options.lockHeld);
  const lockLog = [];

  const sandbox = {
    console,
    SpreadsheetApp: {
      getActiveSpreadsheet: () => ({
        getSheetByName: (name) => allSheets.find((s) => s.name === name) || null,
        getSheets: () => allSheets.slice(),
      }),
      flush: () => {},
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (key) =>
          Object.prototype.hasOwnProperty.call(properties, key) ? properties[key] : null,
      }),
    },
    LockService: {
      getScriptLock: () => ({
        waitLock: (timeout) => {
          lockLog.push({ kind: 'waitLock', timeout });
          if (lockHeld) throw new Error('Could not obtain lock');
        },
        releaseLock: () => lockLog.push({ kind: 'releaseLock' }),
      }),
    },
    ContentService: {
      MimeType: { JSON: 'application/json' },
      createTextOutput: (content) => ({
        content,
        mimeType: null,
        setMimeType(type) {
          this.mimeType = type;
          return this;
        },
        getContent() {
          return this.content;
        },
      }),
    },
  };

  const context = vm.createContext(sandbox);
  for (const file of ['SheetOps.js', 'Code.gs']) {
    vm.runInContext(fs.readFileSync(path.join(APPS_SCRIPT_DIR, file), 'utf8'), context, {
      filename: file,
    });
  }

  /**
   * POST a raw body string through `doPost` and decode the JSON response.
   *
   * @param {string} body
   * @return {!Object}
   */
  const raw = (body) => {
    const output = context.doPost({ postData: { contents: body } });
    return JSON.parse(output.getContent());
  };

  return {
    sheet,
    context,
    secret,
    lockLog,
    /** @param {boolean} held Simulate another writer holding the script lock. */
    setLockHeld: (held) => {
      lockHeld = held;
    },
    raw,
    /**
     * POST a payload with the correct secret already attached.
     *
     * @param {!Object} payload
     * @return {!Object} Decoded response.
     */
    post: (payload) => raw(JSON.stringify(Object.assign({ secret }, payload))),
    writes: () => sheet.writes,
    grid: () => sheet.snapshot(),
  };
}

module.exports = { createEnvironment, FakeSheet, FakeRange, rectangular };
