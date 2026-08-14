/**
 * SheetOps — pure sheet-geometry logic (STUB, U1).
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
 *   function headerRowIndex(rows) { ... }      // <- Apps Script global
 *   if (typeof module !== 'undefined' ...) {   // <- Node only
 *     module.exports = { headerRowIndex };
 *   }
 *
 * Rules that keep this working:
 *   1. No `require()` in this file — it must parse and run in Apps Script.
 *   2. Nothing here touches `SpreadsheetApp`. I/O lives in `Code.gs`; this file gets
 *      plain arrays-of-arrays in and returns plain data out. That is what makes it
 *      testable in Node against the CSV fixtures.
 *   3. `var`/`function` only at top level (no `const`-in-global collisions across
 *      files once clasp concatenates the project's globals).
 *
 * U2 fills this in: header-row detection by content, member-band derivation
 * (columns between `Actual kms` and `+1's`, per src/utils/dataParser.js), run-row
 * lookup by date+run, revision hashing, alphabetical member-column insert position,
 * date-ordered run-row insert position.
 */

/** Bumped by U2 when the geometry logic changes shape. */
var SHEETOPS_VERSION = '0.1.0';

/** Header cells that bound the member band (see src/utils/dataParser.js). */
var MEMBER_BAND_START_AFTER = 'Actual kms';
var MEMBER_BAND_END_BEFORE = "+1's";

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
 * Module health/introspection, used by the Node smoke test and handy from the Apps
 * Script editor to confirm which version is deployed.
 *
 * @return {{module: string, version: string, implemented: !Array<string>}}
 */
function sheetOpsHealth() {
  return {
    module: 'SheetOps',
    version: SHEETOPS_VERSION,
    // U2 appends each function name here as it lands, so the smoke test and the
    // deployed script agree on what exists.
    implemented: ['cellText', 'sheetOpsHealth'],
  };
}

/* eslint-disable no-undef */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    SHEETOPS_VERSION: SHEETOPS_VERSION,
    MEMBER_BAND_START_AFTER: MEMBER_BAND_START_AFTER,
    MEMBER_BAND_END_BEFORE: MEMBER_BAND_END_BEFORE,
    cellText: cellText,
    sheetOpsHealth: sheetOpsHealth,
  };
}
