/**
 * FCTC Attendance — Apps Script Web App (U2).
 *
 * The impure shell: HTTP in, `SpreadsheetApp` out. Every decision about WHERE
 * anything lives in the sheet (header row, member band, run rows, insert
 * positions, revision hash) is delegated to `SheetOps.js`, which is pure and
 * Node-tested against the real season CSVs. Nothing in this file re-derives
 * geometry; if you find yourself scanning a header row here, put it in SheetOps.
 *
 * Contract (FROZEN — see docs/plans/packets/_conventions.md):
 *   POST  { secret, action, ...payload }
 *   200   { ok: true, ... } | { ok: false, error: "code", message: "..." }
 *   Actions:
 *     getState          {} -> { roster, runs, seasonYear, sheetRevision }
 *     submitAttendance  { rowIndex, expectedDate, expectedRun, attendees, plusOnes,
 *                         actualKm, mode, baseRevision }
 *                       -> { ok, written } | { ok, conflict: { reason, state } }
 *     addMember         { name } -> { roster }
 *     addRun            { date, meet, run, approxKm } -> { runs }
 *
 * Indices on the wire are 1-BASED SHEET COORDINATES (see SheetOps.js header):
 * `roster[].colIndex` is a real column, `runs[].rowIndex` a real row.
 *
 * Sheet-safety invariant (every unit): nothing is ever written outside a run row's
 * member band + `Actual kms` + `+1's` cells, the member-band header row, or an
 * inserted run row. Formula/summary rows and columns are sacrosanct. Enforced in
 * code by `writeRowRange_`, which refuses any rectangle
 * `SheetOps.isWriteWithinBand` rejects.
 */

/** Script Property holding the shared secret the iOS app sends. Set it in the editor:
 *  Project Settings > Script Properties > SHARED_SECRET = <a long random string>.
 *  Never commit the value. */
var SECRET_PROPERTY = 'SHARED_SECRET';

/** Script Property naming the season tab (e.g. "2026"). Bump each new season. */
var SEASON_SHEET_PROPERTY = 'SEASON_SHEET_NAME';

/** Structured error codes. The app switches on these; the messages are for humans. */
var ERR_BAD_SECRET = 'bad_secret';
var ERR_UNKNOWN_ACTION = 'unknown_action';
var ERR_ROW_MISMATCH = 'row_mismatch';
var ERR_STALE_REVISION = 'stale_revision';
var ERR_DUPLICATE_MEMBER = 'duplicate_member';
var ERR_BAD_PAYLOAD = 'bad_payload';
/** The configured tab is missing or its header row/member band is unreadable. */
var ERR_SHEET_UNREADABLE = 'sheet_unreadable';
/** Another writer held the script lock for longer than we were willing to wait. */
var ERR_BUSY = 'busy';
/** Anything unforeseen — reported rather than leaking an HTML stack trace. */
var ERR_INTERNAL = 'internal_error';

/** How long a write action waits for the script lock, in ms. */
var LOCK_TIMEOUT_MS = 20000;

/**
 * Web app entry point.
 *
 * @param {GoogleAppsScript.Events.DoPost} e
 * @return {GoogleAppsScript.Content.TextOutput} JSON response.
 */
function doPost(e) {
  try {
    return jsonResponse(handleRequest(parseRequestBody_(e)));
  } catch (err) {
    return jsonResponse(
      errorResult(ERR_INTERNAL, 'Unhandled error: ' + (err && err.message ? err.message : err))
    );
  }
}

/**
 * GET is not part of the contract; answer politely so a browser visit is
 * self-explanatory rather than a stack trace.
 *
 * @return {GoogleAppsScript.Content.TextOutput} JSON response.
 */
function doGet() {
  return jsonResponse({
    ok: false,
    error: 'method_not_allowed',
    message: 'POST JSON to this endpoint. See apps-script/README.md.',
  });
}

/**
 * Auth + routing, split from `doPost` so it is callable from the Apps Script editor
 * (and from the Node harness) with a plain object.
 *
 * @param {*} request Parsed request body.
 * @return {!Object} Response payload (never a `TextOutput`).
 */
function handleRequest(request) {
  if (!request || typeof request !== 'object') {
    return errorResult(ERR_BAD_PAYLOAD, 'Request body must be a JSON object.');
  }
  if (!secretMatches_(request.secret)) {
    return errorResult(ERR_BAD_SECRET, 'Missing or incorrect shared secret.');
  }

  var action = SheetOps.cellText(request.action);
  switch (action) {
    case 'getState':
      return withSheet_(function (ctx) {
        return okResult(stateOf_(ctx));
      });
    case 'submitAttendance':
      return withLock_(function () {
        return withSheet_(function (ctx) {
          return submitAttendance_(ctx, request);
        });
      });
    case 'addMember':
      return withLock_(function () {
        return withSheet_(function (ctx) {
          return addMember_(ctx, request);
        });
      });
    case 'addRun':
      return withLock_(function () {
        return withSheet_(function (ctx) {
          return addRun_(ctx, request);
        });
      });
    default:
      return errorResult(
        ERR_UNKNOWN_ACTION,
        'Unknown action "' + action + '". Expected getState, submitAttendance, addMember or addRun.'
      );
  }
}

// ---------------------------------------------------------------------------
// Request plumbing
// ---------------------------------------------------------------------------

/**
 * @param {GoogleAppsScript.Events.DoPost} e
 * @return {*} Parsed body, or null when there is nothing parseable.
 */
function parseRequestBody_(e) {
  if (!e || !e.postData || !e.postData.contents) return null;
  try {
    return JSON.parse(e.postData.contents);
  } catch (err) {
    return null;
  }
}

/**
 * Compare the presented secret against the script property.
 *
 * Constant-time-ish: always walks the full length of the expected secret so a
 * wrong guess cannot be timed character by character. (Apps Script gives no real
 * constant-time primitive; this removes the obvious signal.)
 *
 * @param {*} presented
 * @return {boolean}
 */
function secretMatches_(presented) {
  var expected = scriptProperty_(SECRET_PROPERTY);
  if (!expected) return false; // unconfigured script accepts nobody
  var given = presented === null || presented === undefined ? '' : String(presented);
  var diff = given.length ^ expected.length;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ given.charCodeAt(i % (given.length || 1));
  }
  return diff === 0;
}

/**
 * @param {string} key
 * @return {string} Property value, or '' when unset.
 */
function scriptProperty_(key) {
  var value = PropertiesService.getScriptProperties().getProperty(key);
  return value === null || value === undefined ? '' : String(value);
}

/**
 * Serialize a payload as a JSON response.
 *
 * @param {!Object} payload
 * @return {GoogleAppsScript.Content.TextOutput}
 */
function jsonResponse(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload)).setMimeType(
    ContentService.MimeType.JSON
  );
}

/**
 * @param {!Object} fields
 * @return {!Object} `{ ok: true, ...fields }`.
 */
function okResult(fields) {
  var result = { ok: true };
  for (var key in fields) {
    if (Object.prototype.hasOwnProperty.call(fields, key)) result[key] = fields[key];
  }
  return result;
}

/**
 * @param {string} code One of the ERR_* constants.
 * @param {string} message Human-readable detail.
 * @return {!Object} `{ ok: false, error, message }`.
 */
function errorResult(code, message) {
  return { ok: false, error: code, message: message };
}

/**
 * Run `body` while holding the script lock, so every read-check-write is
 * serialized against the other phone, the dashboard sync, and Colin's browser.
 *
 * @param {function(): !Object} body
 * @return {!Object}
 */
function withLock_(body) {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(LOCK_TIMEOUT_MS);
  } catch (err) {
    return errorResult(
      ERR_BUSY,
      'The sheet is busy with another write; retry in a moment.'
    );
  }
  try {
    return body();
  } finally {
    lock.releaseLock();
  }
}

// ---------------------------------------------------------------------------
// Sheet context
// ---------------------------------------------------------------------------

/**
 * Read the season tab once and hand `body` a context with the grid and all
 * geometry already resolved by SheetOps.
 *
 * @param {function(!Object): !Object} body
 * @return {!Object}
 */
function withSheet_(body) {
  var sheetName = scriptProperty_(SEASON_SHEET_PROPERTY);
  if (!sheetName) {
    return errorResult(
      ERR_SHEET_UNREADABLE,
      'Script property ' + SEASON_SHEET_PROPERTY + ' is not set (e.g. "2026").'
    );
  }
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  if (!sheet) {
    return errorResult(ERR_SHEET_UNREADABLE, 'No sheet tab named "' + sheetName + '".');
  }
  var ctx = readContext_(sheet, sheetName);
  if (!ctx) {
    return errorResult(
      ERR_SHEET_UNREADABLE,
      'Tab "' + sheetName + '" has no header row with Date/Run/Actual kms and a +1\'s column.'
    );
  }
  return body(ctx);
}

/**
 * Snapshot the tab and resolve its geometry.
 *
 * @param {!GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {string} sheetName
 * @return {?{sheet: !Object, sheetName: string, seasonYear: number,
 *     grid: !Array<!Array<*>>, headerRow: number, bounds: !Object,
 *     band: !Array<!Object>}}
 */
function readContext_(sheet, sheetName) {
  var grid = sheet.getDataRange().getValues();
  var geometry = SheetOps.sheetGeometry(grid);
  if (!geometry) return null;
  return {
    sheet: sheet,
    sheetName: sheetName,
    seasonYear: seasonYearOf_(sheetName),
    grid: grid,
    headerRow: geometry.headerRow,
    bounds: geometry.bounds,
    band: geometry.band,
  };
}

/**
 * Re-read the tab after a write, so responses describe the sheet as it now is.
 *
 * @param {!Object} ctx
 * @return {?Object} A fresh context, or null if the write somehow broke geometry.
 */
function refreshContext_(ctx) {
  return readContext_(ctx.sheet, ctx.sheetName);
}

/**
 * The season year, taken from the tab name ("2026" -> 2026).
 *
 * @param {string} sheetName
 * @return {number} 0 when the tab is not named for a year.
 */
function seasonYearOf_(sheetName) {
  var match = String(sheetName).match(/(\d{4})/);
  return match ? parseInt(match[1], 10) : 0;
}

/**
 * The full `getState` body for a context.
 *
 * @param {!Object} ctx
 * @return {{roster: !Array<!Object>, runs: !Array<!Object>, seasonYear: number,
 *     sheetRevision: string}}
 */
function stateOf_(ctx) {
  return {
    roster: ctx.band,
    runs: SheetOps.listRuns(ctx.grid, ctx.headerRow),
    seasonYear: ctx.seasonYear,
    sheetRevision: SheetOps.revisionHash(ctx.grid, ctx.headerRow),
  };
}

/**
 * A conflict response: no write happened, here is the sheet as it actually is.
 *
 * @param {!Object} ctx
 * @param {string} reason `row_mismatch` or `stale_revision`.
 * @param {string} message
 * @return {!Object}
 */
function conflictResult_(ctx, reason, message) {
  return okResult({
    conflict: { reason: reason, message: message, state: stateOf_(ctx) },
  });
}

// ---------------------------------------------------------------------------
// Guarded writes
// ---------------------------------------------------------------------------

/**
 * Write one row-slice, refusing anything outside the granted cells.
 *
 * This is the ONLY place an existing run row is written, so the sheet-safety
 * invariant has exactly one enforcement point.
 *
 * @param {!Object} ctx
 * @param {number} row 1-based sheet row (must be below the header).
 * @param {number} col 1-based first column.
 * @param {!Array<*>} values One row of values.
 * @return {number} Number of cells written.
 */
function writeRowRange_(ctx, row, col, values) {
  if (!SheetOps.isWriteWithinBand(ctx.bounds, ctx.headerRow, row, col, 1, values.length)) {
    throw new Error(
      'Refusing to write outside the member band: row ' +
        row +
        ', columns ' +
        col +
        '-' +
        (col + values.length - 1)
    );
  }
  ctx.sheet.getRange(row, col, 1, values.length).setValues([values]);
  return values.length;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/**
 * `submitAttendance` — verify row identity and revision, then write absolute
 * values across the member band (+ `+1's`, + `Actual kms`).
 *
 * Idempotent by construction: the payload carries absolute state, never deltas,
 * which is what makes the offline outbox safe to retry.
 *
 * @param {!Object} ctx
 * @param {!Object} request
 * @return {!Object}
 */
function submitAttendance_(ctx, request) {
  var rowIndex = parseInt(request.rowIndex, 10);
  if (!(rowIndex > ctx.headerRow)) {
    return errorResult(
      ERR_BAD_PAYLOAD,
      'rowIndex must be a run row below the header row (' + ctx.headerRow + ').'
    );
  }
  if (!isStringArray_(request.attendees)) {
    return errorResult(ERR_BAD_PAYLOAD, 'attendees must be an array of sheet names.');
  }
  var mode = SheetOps.cellText(request.mode) || 'merge';
  if (mode !== 'merge' && mode !== 'overwrite') {
    return errorResult(ERR_BAD_PAYLOAD, 'mode must be "merge" or "overwrite".');
  }

  var live = SheetOps.readRun(ctx.grid, ctx.bounds, ctx.band, rowIndex);
  if (!live) {
    return conflictResult_(
      ctx,
      ERR_ROW_MISMATCH,
      'Row ' + rowIndex + ' is no longer a run row.'
    );
  }
  if (
    !SheetOps.sameRunIdentity(
      live.date,
      live.run,
      request.expectedDate,
      request.expectedRun
    )
  ) {
    return conflictResult_(
      ctx,
      ERR_ROW_MISMATCH,
      'Row ' +
        rowIndex +
        ' is now "' +
        live.date +
        ' / ' +
        live.run +
        '", not "' +
        SheetOps.cellText(request.expectedDate) +
        ' / ' +
        SheetOps.cellText(request.expectedRun) +
        '".'
    );
  }

  var revision = SheetOps.revisionHash(ctx.grid, ctx.headerRow);
  var baseRevision = SheetOps.cellText(request.baseRevision);
  if (baseRevision && baseRevision !== revision) {
    return conflictResult_(
      ctx,
      ERR_STALE_REVISION,
      'The sheet changed since this submission was prepared.'
    );
  }

  var plan = SheetOps.buildRowWrite(
    ctx.band,
    request.attendees,
    request.plusOnes,
    request.actualKm,
    {
      mode: mode,
      existingValues: SheetOps.memberValuesAt(ctx.grid, ctx.headerRow, rowIndex),
      existingPlusOnes: live.plusOnes,
      existingActualKm: live.actualKm,
    }
  );
  if (plan.unknownNames.length) {
    return errorResult(
      ERR_BAD_PAYLOAD,
      'Not on the roster: ' + plan.unknownNames.join(', ') + '. Use addMember first.'
    );
  }

  var written = 0;
  if (plan.memberValues.length) {
    written += writeRowRange_(ctx, rowIndex, ctx.bounds.firstMemberCol, plan.memberValues);
  }
  if (plan.writePlusOnes) {
    written += writeRowRange_(ctx, rowIndex, ctx.bounds.plusOnesCol, [plan.plusOnes]);
  }
  if (plan.writeActualKm) {
    written += writeRowRange_(ctx, rowIndex, ctx.bounds.actualKmCol, [plan.actualKm]);
  }
  SpreadsheetApp.flush();

  var fresh = refreshContext_(ctx) || ctx;
  return okResult({
    written: written,
    sheetRevision: SheetOps.revisionHash(fresh.grid, fresh.headerRow),
  });
}

/**
 * `addMember` — insert a column at the alphabetical position inside the member
 * band and write the header cell.
 *
 * Inserting a column INSIDE the band (rather than appending past `+1's`) is what
 * makes the sheet's own COUNTA/SUM formulas widen themselves; the smoke test
 * (test/smoke.md) verifies that on a real copy.
 *
 * @param {!Object} ctx
 * @param {!Object} request
 * @return {!Object}
 */
function addMember_(ctx, request) {
  var name = SheetOps.cellText(request.name);
  if (!name) return errorResult(ERR_BAD_PAYLOAD, 'name is required.');
  if (!SheetOps.normalizeKey(name)) {
    return errorResult(ERR_BAD_PAYLOAD, 'name must contain at least one letter or digit.');
  }
  var existing = SheetOps.findMemberIndex(ctx.band, name);
  if (existing >= 0) {
    return errorResult(
      ERR_DUPLICATE_MEMBER,
      '"' + ctx.band[existing].name + '" is already on the roster.'
    );
  }

  var position = SheetOps.alphabeticalInsertIndex(ctx.band, name);
  var insertBefore = SheetOps.memberInsertColumn(ctx.band, ctx.bounds, position);
  ctx.sheet.insertColumnBefore(insertBefore);
  ctx.sheet.getRange(ctx.headerRow, insertBefore).setValue(name);
  SpreadsheetApp.flush();

  var fresh = refreshContext_(ctx);
  if (!fresh) {
    return errorResult(
      ERR_SHEET_UNREADABLE,
      'Column inserted but the tab no longer parses; inspect the sheet.'
    );
  }
  return okResult({
    roster: fresh.band,
    sheetRevision: SheetOps.revisionHash(fresh.grid, fresh.headerRow),
  });
}

/**
 * `addRun` — insert a row in date order below the header band and fill the four
 * fixed columns.
 *
 * The derived columns to the right of `+1's` are re-created by copying them from
 * the neighbouring run row, because an inserted row starts formula-less. That copy
 * is confined to the newly inserted row, which the invariant grants.
 *
 * @param {!Object} ctx
 * @param {!Object} request
 * @return {!Object}
 */
function addRun_(ctx, request) {
  var date = SheetOps.cellText(request.date);
  if (!date) return errorResult(ERR_BAD_PAYLOAD, 'date is required (e.g. "Fri, 3-Jan").');
  if (!SheetOps.parseSheetDate(date)) {
    return errorResult(ERR_BAD_PAYLOAD, 'date must look like "Fri, 3-Jan" or "3-Jan".');
  }
  var run = SheetOps.cellText(request.run);
  if (!run) return errorResult(ERR_BAD_PAYLOAD, 'run is required (e.g. "Soft Sand").');
  var meet = SheetOps.cellText(request.meet);
  var approxKm = SheetOps.numberOrNull(request.approxKm);

  var runs = SheetOps.listRuns(ctx.grid, ctx.headerRow);
  if (SheetOps.findRunRows(ctx.grid, ctx.headerRow, { date: date, run: run }).length) {
    return errorResult(
      ERR_BAD_PAYLOAD,
      '"' + date + ' / ' + run + '" already exists; submit attendance against it instead.'
    );
  }

  var target = SheetOps.runInsertTarget(runs, ctx.headerRow, date);
  var templateRow = templateRowFor_(runs, target);
  if (target.append) {
    ctx.sheet.insertRowAfter(target.rowIndex - 1);
  } else {
    ctx.sheet.insertRowBefore(target.rowIndex);
  }
  var newRow = target.rowIndex;
  // Inserting before an existing row pushes the template down by one.
  if (!target.append && templateRow >= newRow) templateRow += 1;

  ctx.sheet
    .getRange(newRow, ctx.bounds.dateCol, 1, 4)
    .setValues([[date, meet, run, approxKm === null ? '' : approxKm]]);
  copyDerivedColumns_(ctx, templateRow, newRow);
  SpreadsheetApp.flush();

  var fresh = refreshContext_(ctx);
  if (!fresh) {
    return errorResult(
      ERR_SHEET_UNREADABLE,
      'Row inserted but the tab no longer parses; inspect the sheet.'
    );
  }
  return okResult({
    runs: SheetOps.listRuns(fresh.grid, fresh.headerRow),
    sheetRevision: SheetOps.revisionHash(fresh.grid, fresh.headerRow),
  });
}

/**
 * The existing run row whose derived formulas the inserted row should copy.
 *
 * @param {!Array<!Object>} runs
 * @param {{position: number, append: boolean}} target
 * @return {number} 1-based row, or 0 when the season has no run rows yet.
 */
function templateRowFor_(runs, target) {
  if (!runs.length) return 0;
  if (target.position > 0) return runs[target.position - 1].rowIndex;
  return runs[0].rowIndex;
}

/**
 * Copy the derived (formula) columns right of `+1's` from a template run row into
 * a freshly inserted run row, so `Total Attendance per run` computes there too.
 *
 * @param {!Object} ctx
 * @param {number} templateRow 1-based; 0 means "no template, skip".
 * @param {number} newRow 1-based.
 * @return {void}
 */
function copyDerivedColumns_(ctx, templateRow, newRow) {
  if (!templateRow || templateRow === newRow) return;
  var firstDerived = ctx.bounds.plusOnesCol + 1;
  var lastColumn = ctx.sheet.getLastColumn();
  if (lastColumn < firstDerived) return;
  var width = lastColumn - firstDerived + 1;
  ctx.sheet
    .getRange(templateRow, firstDerived, 1, width)
    .copyTo(ctx.sheet.getRange(newRow, firstDerived, 1, width));
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/**
 * @param {*} value
 * @return {boolean} True when `value` is an array of strings.
 */
function isStringArray_(value) {
  if (!value || Object.prototype.toString.call(value) !== '[object Array]') return false;
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== 'string') return false;
  }
  return true;
}
