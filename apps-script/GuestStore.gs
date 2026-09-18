/** Shared workbook snapshots. Names label UUIDs; metadata supplies current rows. */
var GUEST_TABLES = { guests: '_FCTC_Guests', attendance: '_FCTC_GuestAttendance', operations: '_FCTC_Operations' };
var GUEST_RUN_METADATA = 'FCTC_RUN_ID';
var GUEST_FENCE_PROPERTY = 'FCTC_PENDING_OPERATION';
var GUEST_JOURNAL_PREFIX = 'FCTC_JOURNAL_';

function sharedGuestsEnabled_() { return scriptProperty_('SHARED_GUESTS_ENABLED') === 'true'; }
function guestDigest_(text) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, text, Utilities.Charset.UTF_8)
    .map(function (b) { return ('0' + ((b + 256) % 256).toString(16)).slice(-2); }).join('');
}
function guestFail_(reason, message, details) {
  var error = new Error(message);
  error.guestConflict = Object.assign({ reason: reason, message: message }, details || {});
  throw error;
}
function guestRequire_(result) {
  if (!result.ok) guestFail_(result.conflict.reason, result.conflict.message, result.conflict);
  return result;
}
function guestReadTable_(book, name, headerOnly) {
  var sheet = book.getSheetByName(name);
  if (!sheet) guestFail_('setup_required', 'Set up shared guest tables before enabling this feature.');
  // Store snapshots need the operations schema and append position, never the
  // historical request payloads. Setup keeps its existing full-table contract.
  var grid = headerOnly ? sheet.getRange(1, 1, 1, 3).getValues() : sheet.getDataRange().getValues();
  if (!grid.length || grid[0][0] !== 'FCTC_V2') guestFail_('invalid_table', 'The reserved guest table has an unexpected header.');
  return { sheet: sheet, sheetId: sheet.getSheetId(), grid: grid, lastRow: sheet.getLastRow() };
}
function guestTableRecords_(table, validator) {
  var records = [];
  table.grid.slice(1).forEach(function (row, index) {
    if (!row[0] && !row[1]) return;
    var record;
    try { record = JSON.parse(row[1]); } catch (error) { guestFail_('invalid_table', 'A guest table record is unreadable.'); }
    guestRequire_(validator(record));
    records.push({ value: record, rowIndex: index + 2 });
  });
  return records;
}
/** Only row-associated metadata is accepted. Invalid or duplicate IDs block reads/writes. */
function guestMetadata_ (book) {
  // Sheet resources omit row-associated metadata. Search by key so setup,
  // reads and receipt verification all receive the actual row locators.
  var response = Sheets.Spreadsheets.DeveloperMetadata.search({ dataFilters: [
    { developerMetadataLookup: { metadataKey: GUEST_RUN_METADATA } }
  ] }, book.getId());
  var bySheet = {};
  (response.matchedDeveloperMetadata || []).forEach(function (match) {
    var metadata = match.developerMetadata, range = metadata && metadata.location && metadata.location.dimensionRange;
    if (!range) guestFail_('invalid_run', 'Repair run metadata that is not associated with a season row.');
    // Advanced-service responses omit numeric defaults, including sheet ID 0
    // on the original season. Normalize them before strict identity checks.
    range = Object.assign({ sheetId: 0, startIndex: 0 }, range);
    if (!Number.isSafeInteger(range.sheetId) || range.sheetId < 0) {
      guestFail_('invalid_run', 'Repair run metadata that is not associated with a season row.');
    }
    metadata = Object.assign({}, metadata, { location: Object.assign({}, metadata.location, { dimensionRange: range }) });
    if (!bySheet[range.sheetId]) bySheet[range.sheetId] = [];
    bySheet[range.sheetId].push(metadata);
  });
  return bySheet;
}
function guestReadStore_() {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var tables = {};
  Object.keys(GUEST_TABLES).forEach(function (key) { tables[key] = guestReadTable_(book, GUEST_TABLES[key], key === 'operations'); });
  var guestRows = guestTableRecords_(tables.guests, GuestOps.validateGuest);
  var attendanceRows = guestTableRecords_(tables.attendance, GuestOps.validateAttendance);
  var guests = guestRows.map(function (r) { return r.value; });
  var attendance = attendanceRows.map(function (r) { return r.value; });
  // Detect contradictory duplicates before deriving counts or allocating a slot.
  var seenGuests = {};
  guests.forEach(function (g) {
    if (seenGuests[g.guestId]) guestFail_('duplicate_guest_identity', 'Repair duplicated shared guest identities.');
    seenGuests[g.guestId] = true;
    guestRequire_(GuestOps.attendanceSummary(g.guestId, attendance));
  });
  attendance.forEach(function (a) {
    if (a.spreadsheetId !== book.getId() || !seenGuests[a.guestId]) guestFail_('invalid_attendance', 'A guest attendance has no matching workbook or person.');
  });
  var metadata = guestMetadata_(book), seasons = [], runs = [], seenIds = {};
  var supported = JSON.parse(tables.guests.grid[0][2] || '[]');
  if (!Array.isArray(supported) || !supported.length) guestFail_('setup_required', 'Set up at least one supported season.');
  supported.forEach(function (id) {
    var sheet = book.getSheetById(id);
    if (!sheet || !SheetOps.isSeasonTabName(sheet.getName())) guestFail_('run_missing', 'A supported season tab is missing.');
    var ctx = readContext_(sheet, sheet.getName());
    if (!ctx) guestFail_('sheet_unreadable', 'A season tab cannot be read safely.');
    ctx.sheetId = sheet.getSheetId();
    var rows = {}, locators = metadata[ctx.sheetId] || [];
    locators.forEach(function (m) {
      var dimension = m.location && m.location.dimensionRange;
      if (!dimension || dimension.dimension !== 'ROWS' || dimension.sheetId !== ctx.sheetId ||
          dimension.endIndex !== dimension.startIndex + 1 || !guestIsUUID(m.metadataValue)) {
        guestFail_('invalid_run', 'Repair invalid run metadata before recording attendance.');
      }
      if (seenIds[m.metadataValue] || rows[dimension.startIndex + 1]) guestFail_('duplicate_run_identity', 'A run has duplicate metadata. Repair its identity.');
      seenIds[m.metadataValue] = true;
      rows[dimension.startIndex + 1] = m.metadataValue;
    });
    ctx.runs = SheetOps.listRuns(ctx.grid, ctx.headerRow).map(function (run) {
      if (!rows[run.rowIndex]) guestFail_('run_missing', 'Set up metadata for every run before enabling shared guests.');
      var identity = { spreadsheetId: book.getId(), seasonSheetId: ctx.sheetId, runId: rows[run.rowIndex] };
      var named = [];
      attendance.forEach(function (a) {
        if (guestRunKey(a) === guestRunKey(identity) && a.state === 'present' && a.classification === 'guest' && named.indexOf(a.guestId) < 0) named.push(a.guestId);
      });
      var allocation = guestRequire_(GuestOps.validateAllocation({ namedGuestIds: named, unnamedGuests: run.plusOnes - named.length }, guests));
      return Object.assign({}, run, identity, allocation.allocation, { seasonYear: ctx.seasonYear });
    });
    runs = runs.concat(ctx.runs); seasons.push(ctx);
  });
  // Removed rows remain audit history, but cannot be silently omitted from a guest's history.
  attendance.forEach(function (a) { guestRequire_(GuestOps.resolveRun(runs, a)); });
  return { book: book, tables: tables, guests: guests, guestRows: guestRows, attendance: attendance,
    attendanceRows: attendanceRows, seasons: seasons, runs: runs,
    guestRevision: guestRevision_(guests, attendance) };
}
function guestRevision_(guests, attendance) { return guestDigest_(JSON.stringify([guests, attendance])); }
function guestSeason_(store, sheetId) {
  var id = sheetId;
  if (id === undefined) {
    var active = store.book.getSheetByName(scriptProperty_(SEASON_SHEET_PROPERTY));
    id = active && active.getSheetId();
  }
  var ctx = store.seasons.filter(function (s) { return s.sheetId === id; })[0];
  if (!ctx) guestFail_('run_missing', 'Select a supported season in this workbook.');
  return ctx;
}
function guestSheetRevision_(ctx, guestRevision) {
  return guestDigest_(JSON.stringify([SheetOps.revisionHash(ctx.grid, ctx.headerRow), guestRevision, ctx.runs.map(function (r) { return [r.rowIndex, r.runId]; })]));
}
function guestSummary_(store, guest) {
  var summary = guestRequire_(GuestOps.attendanceSummary(guest.guestId, store.attendance));
  var runs = summary.runIdentities.map(function (id) { return guestRequire_(GuestOps.resolveRun(store.runs, id)).run; });
  runs.sort(function (a, b) {
    return b.seasonYear - a.seasonYear || SheetOps.dateOrdinal(b.date) - SheetOps.dateOrdinal(a.date) || b.rowIndex - a.rowIndex;
  });
  var last = runs[0];
  return Object.assign({}, guest, { confirmedRuns: summary.confirmedRuns, lastAttendance: last ? {
    spreadsheetId: last.spreadsheetId, seasonSheetId: last.seasonSheetId, runId: last.runId, date: last.date, seasonYear: last.seasonYear
  } : null });
}
function guestState_(store, sheetId) {
  var ctx = guestSeason_(store, sheetId);
  return Object.assign(stateOf_(ctx), { apiVersion: 2, capabilities: guestCapabilities_(),
    spreadsheetId: store.book.getId(), seasonSheetId: ctx.sheetId, runs: ctx.runs,
    supportedSeasons: store.seasons.map(function (season) { return { seasonSheetId: season.sheetId, seasonYear: season.seasonYear }; }),
    guests: store.guests.map(function (g) { return guestSummary_(store, g); }),
    guestRevision: store.guestRevision, sheetRevision: guestSheetRevision_(ctx, store.guestRevision),
    pendingOperationId: scriptProperty_(GUEST_FENCE_PROPERTY) || null });
}
function guestCapabilities_() {
  var enabled = sharedGuestsEnabled_();
  return { apiVersion: 2, sharedGuests: enabled, stableRunIdentity: enabled, guestHistory: enabled,
    guestPromotion: enabled && typeof guestPreviewPromotion_ === 'function', operationReceipts: enabled };
}
function guestHistory_(store, guestId) {
  var guest = store.guests.filter(function (g) { return g.guestId === guestId; })[0];
  if (!guest) guestFail_('guest_missing', 'Select a saved shared guest.');
  return okResult({ guest: guestSummary_(store, guest), guestRevision: store.guestRevision,
    attendance: store.attendance.filter(function (a) { return a.guestId === guestId; }).map(function (a) {
      var run = guestRequire_(GuestOps.resolveRun(store.runs, a)).run;
      return Object.assign({}, a, { seasonYear: run.seasonYear, date: run.date, run: run.run, rowIndex: run.rowIndex });
    }) });
}
