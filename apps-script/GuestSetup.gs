/** Explicit, idempotent setup. Neither setup nor deployment enables shared writes. */
function guestSetupPlan_(book, request) {
  if (scriptProperty_('SHARED_GUESTS_SETUP_ALLOWED') !== 'true') guestFail_('setup_disabled', 'An operator must enable shared guest setup on this spreadsheet first.');
  if (request.spreadsheetId !== book.getId() || !Array.isArray(request.seasonSheetIds) || !request.seasonSheetIds.length) {
    guestFail_('invalid_run', 'Select the workbook and seasons to set up.');
  }
  var plan = guestPlan_(), sheets = book.getSheets(), nextId = 1, tables = {};
  sheets.forEach(function (sheet) { nextId = Math.max(nextId, sheet.getSheetId() + 1); });
  Object.keys(GUEST_TABLES).forEach(function (key) {
    var name = GUEST_TABLES[key], existing = book.getSheetByName(name);
    if (existing) tables[key] = guestReadTable_(book, name);
    else {
      var id = nextId++;
      plan.requests.push({ addSheet: { properties: { sheetId: id, title: name, hidden: true,
        gridProperties: { rowCount: key === 'attendance' ? 20000 : 3000, columnCount: key === 'operations' ? 128 : 3 } } } });
      tables[key] = { sheetId: id, grid: [['FCTC_V2', 'schema2']] };
      guestPlanCell_(plan, id, 1, 1, ['FCTC_V2', 'schema2']);
    }
    plan.requests.push({ updateSheetProperties: { properties: { sheetId: tables[key].sheetId, hidden: true }, fields: 'hidden' } });
    plan.targetState.sheets.push({ sheetId: tables[key].sheetId, title: name });
  });
  var metadata = guestMetadata_(book), seen = {}, supported = [];
  if (tables.guests.grid[0][2]) supported = JSON.parse(tables.guests.grid[0][2]);
  Object.keys(metadata).forEach(function (id) {
    (metadata[id] || []).forEach(function (entry) {
      if (seen[entry.metadataValue]) guestFail_('duplicate_run_identity', 'Repair duplicate run metadata before setup.');
      seen[entry.metadataValue] = true;
    });
  });
  var requested = [];
  request.seasonSheetIds.forEach(function (sheetId) {
    if (!Number.isSafeInteger(sheetId) || requested.indexOf(sheetId) >= 0) guestFail_('invalid_run', 'Choose each season once.');
    requested.push(sheetId);
    var sheet = book.getSheetById(sheetId);
    if (!sheet || !SheetOps.isSeasonTabName(sheet.getName())) guestFail_('invalid_run', 'Only season tabs can receive run metadata.');
    var ctx = readContext_(sheet, sheet.getName());
    if (!ctx) guestFail_('sheet_unreadable', 'A selected season cannot be read.');
    plan.sourceRevisions[String(sheetId)] = SheetOps.revisionHash(ctx.grid, ctx.headerRow);
    var rows = {};
    (metadata[sheetId] || []).forEach(function (entry) {
      var range = entry.location && entry.location.dimensionRange;
      if (!range || range.sheetId !== sheetId || range.dimension !== 'ROWS' || range.endIndex !== range.startIndex + 1 ||
          !guestIsUUID(entry.metadataValue) || rows[range.startIndex + 1]) guestFail_('duplicate_run_identity', 'Repair invalid or duplicate run metadata before setup.');
      rows[range.startIndex + 1] = entry.metadataValue;
    });
    SheetOps.listRuns(ctx.grid, ctx.headerRow).forEach(function (run) {
      if (!rows[run.rowIndex]) guestPlanMetadata_(plan, sheetId, run.rowIndex, Utilities.getUuid().toLowerCase());
    });
    if (supported.indexOf(sheetId) < 0) supported.push(sheetId);
  });
  supported.sort(function (a, b) { return a - b; });
  guestPlanCell_(plan, tables.guests.sheetId, 1, 3, [JSON.stringify(supported)]);
  plan.response = { spreadsheetId: book.getId(), seasonSheetIds: supported, sharedGuestsEnabled: sharedGuestsEnabled_() };
  return { plan: plan, receiptLocation: { sheetId: tables.operations.sheetId, rowIndex: Math.max(2, tables.operations.grid.length + 1) } };
}
