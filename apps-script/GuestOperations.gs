/** Durable single-writer journal. No unknown delivery is retried automatically. */
var GUEST_JOURNAL_CHUNK = 1500; // At most 6 KB UTF-8; Script Properties allow 9 KB per value.
var GUEST_JOURNAL_MAX = 70000; // At most 280 KB plus keys, below the 500 KB property store limit.
function guestReadOperation_(book, operationId) {
  var sheet = book.getSheetByName(GUEST_TABLES.operations);
  if (!sheet) return null;
  var lastRow = sheet.getLastRow(), found = [];
  if (lastRow < 2) return null;
  // Scan only IDs before fetching the one bounded receipt row. Reading all
  // matching IDs first retains duplicate detection without historical payloads.
  sheet.getRange(2, 1, lastRow - 1, 1).getValues().forEach(function (row, index) {
    if (row[0] === operationId) found.push(index + 2);
  });
  if (found.length > 1) guestFail_('invalid_operation', 'Duplicate operation receipts need repair.');
  if (!found.length) return null;
  var row = sheet.getRange(found[0], 1, 1, 123).getValues()[0], count = Number(row[2]);
  if (!Number.isInteger(count) || count < 1 || count > 120) guestFail_('invalid_operation', 'The operation receipt is unreadable. Keep writes paused.');
  var record = JSON.parse(row.slice(3, 3 + count).join(''));
  if (row[0] !== operationId || record.operationId !== operationId || row[1] !== record.status) guestFail_('invalid_operation', 'The operation receipt does not match its reserved row.');
  return record;
}
function guestOperationRequest_(operation) {
  var json = JSON.stringify(operation), chunks = [];
  for (var i = 0; i < json.length; i += 6000) chunks.push(json.slice(i, i + 6000));
  if (chunks.length > 120) guestFail_('operation_too_large', 'This change exceeds the supported recovery journal size.');
  return guestCellRequest_(operation.receiptLocation.sheetId, operation.receiptLocation.rowIndex, 1,
    [operation.operationId, operation.status, chunks.length].concat(chunks));
}
function guestJournal_() {
  var id = scriptProperty_(GUEST_FENCE_PROPERTY);
  if (!id) return null;
  var count = Number(scriptProperty_(GUEST_JOURNAL_PREFIX + 'COUNT'));
  if (!Number.isInteger(count) || count < 1 || count > 100) return null;
  var json = '';
  for (var i = 0; i < count; i++) json += scriptProperty_(GUEST_JOURNAL_PREFIX + i);
  try {
    var operation = JSON.parse(json);
    return operation.operationId === id ? operation : null;
  } catch (error) { return null; }
}
/** Install the fence first. A partial reservation can only fail closed. */
function guestReserveJournal_(operation) {
  var json = JSON.stringify(operation);
  if (json.length > GUEST_JOURNAL_MAX) guestFail_('operation_too_large', 'Split this change before it exceeds the recovery journal limit.');
  var props = PropertiesService.getScriptProperties(), values = {}, count = Math.ceil(json.length / GUEST_JOURNAL_CHUNK);
  var existingBytes = JSON.stringify(props.getProperties()).length * 4;
  if (existingBytes + json.length * 4 + 10000 > 480000) guestFail_('operation_too_large', 'Script property storage cannot safely reserve this change.');
  props.setProperty(GUEST_FENCE_PROPERTY, operation.operationId);
  props.setProperty(GUEST_JOURNAL_PREFIX + 'PHASE', 'preparing');
  for (var i = 0; i < count; i++) values[GUEST_JOURNAL_PREFIX + i] = json.slice(i * GUEST_JOURNAL_CHUNK, (i + 1) * GUEST_JOURNAL_CHUNK);
  values[GUEST_JOURNAL_PREFIX + 'COUNT'] = String(count);
  props.setProperties(values);
  props.setProperty(GUEST_JOURNAL_PREFIX + 'PHASE', 'reserved');
}
function guestClearJournal_() {
  var props = PropertiesService.getScriptProperties();
  // Remove the fence last: interrupted cleanup still prevents a later writer.
  Object.keys(props.getProperties()).forEach(function (key) { if (key.indexOf(GUEST_JOURNAL_PREFIX) === 0) props.deleteProperty(key); });
  props.deleteProperty(GUEST_FENCE_PROPERTY);
}
function guestPublicOperation_(operation) {
  return operation ? { operationId: operation.operationId, requestDigest: operation.requestDigest,
    status: operation.status, response: operation.status === 'pending' ? null : operation.response } : null;
}
function guestPending_(operationId) {
  return okResult({ conflict: { reason: 'pending_verification', message: 'Checking saved changes. Wait for verification before recording more attendance.', operationId: operationId } });
}
/** Read back precise targets after a receipt. Success is never based on absence alone. */
function guestVerifyTargets_(book, target) {
  if (target.promotion && !guestVerifyPromotion_(book, target.promotion)) return false;
  if (!guestVerifyCellTargets_(book, target.cells, target.formulas || [])) return false;
  var sheets = target.sheets || [];
  for (var s = 0; s < sheets.length; s++) {
    var expected = sheets[s], found = book.getSheetById(expected.sheetId);
    if (!found || found.getName() !== expected.title) return false;
  }
  var metadata = target.metadata || [];
  if (metadata.length) {
    var live = guestMetadata_(book);
    for (var m = 0; m < metadata.length; m++) {
      var locator = metadata[m];
      var matches = (live[locator.sheetId] || []).filter(function (entry) {
        var range = entry.location && entry.location.dimensionRange;
        return entry.metadataValue === locator.runId && range && range.startIndex === locator.row - 1 && range.endIndex === locator.row;
      });
      if (matches.length !== 1) return false;
    }
  }
  return true;
}
/** Verify exact coordinates in memory, with no read larger than 10,000 cells. */
function guestVerifyCellTargets_(book, cells, formulas) {
  var groups = {};
  function add(cell, kind) {
    var group = groups[cell.sheetId];
    if (!group) group = groups[cell.sheetId] = { sheetId: cell.sheetId, cells: [], formulas: [],
      minRow: cell.row, maxRow: cell.row, minCol: cell.col, maxCol: cell.col };
    group[kind].push(cell);
    group.minRow = Math.min(group.minRow, cell.row); group.maxRow = Math.max(group.maxRow, cell.row);
    group.minCol = Math.min(group.minCol, cell.col); group.maxCol = Math.max(group.maxCol, cell.col);
  }
  cells.forEach(function (cell) { add(cell, 'cells'); });
  formulas.forEach(function (cell) { add(cell, 'formulas'); });
  var ids = Object.keys(groups), limit = 10000;
  for (var g = 0; g < ids.length; g++) {
    var group = groups[ids[g]], sheet = book.getSheetById(group.sheetId);
    if (!sheet) return false;
    for (var col = group.minCol; col <= group.maxCol; col += limit) {
      var width = Math.min(limit, group.maxCol - col + 1), maxHeight = Math.floor(limit / width);
      for (var row = group.minRow; row <= group.maxRow; row += maxHeight) {
        var height = Math.min(maxHeight, group.maxRow - row + 1);
        function inRange(cell) { return cell.row >= row && cell.row < row + height && cell.col >= col && cell.col < col + width; }
        var valuesToCheck = group.cells.filter(inRange), formulasToCheck = group.formulas.filter(inRange);
        // Sparse targets must not cause reads of untouched bands between them.
        if (!valuesToCheck.length && !formulasToCheck.length) continue;
        var range = sheet.getRange(row, col, height, width);
        var values = valuesToCheck.length ? range.getValues() : null;
        var savedFormulas = formulasToCheck.length ? range.getFormulas() : null;
        for (var v = 0; v < valuesToCheck.length; v++) {
          var cell = valuesToCheck[v], actual = values[cell.row - row][cell.col - col];
          if ((actual === '' ? null : actual) !== (cell.value === '' ? null : cell.value)) return false;
        }
        for (var f = 0; f < formulasToCheck.length; f++) {
          var formula = formulasToCheck[f];
          if (savedFormulas[formula.row - row][formula.col - col] !== formula.formula) return false;
        }
      }
    }
  }
  return true;
}
/** Refuse exhausted table capacity before creating a pending operation. */
function guestValidateCapacity_(book, plan, receiptLocation) {
  var sizes = {};
  book.getSheets().forEach(function (sheet) { sizes[sheet.getSheetId()] = { rows: sheet.getMaxRows(), cols: sheet.getMaxColumns() }; });
  plan.requests.forEach(function (request) {
    if (request.addSheet) {
      var p = request.addSheet.properties;
      sizes[p.sheetId] = { rows: p.gridProperties.rowCount, cols: p.gridProperties.columnCount };
    }
    if (request.insertDimension) {
      var range = request.insertDimension.range, size = sizes[range.sheetId];
      if (!size) guestFail_('invalid_run', 'The target sheet is missing.');
      size[range.dimension === 'ROWS' ? 'rows' : 'cols'] += range.endIndex - range.startIndex;
    }
  });
  plan.targetState.cells.concat([{ sheetId: receiptLocation.sheetId, row: receiptLocation.rowIndex, col: 128 }]).forEach(function (cell) {
    var size = sizes[cell.sheetId];
    if (!size || cell.row > size.rows || cell.col > size.cols) guestFail_('table_capacity', 'A shared table needs more capacity before this change can be saved.');
  });
}
/** Status polling can resolve a lost response after both original processes stop. */
function guestReconcile_(book, operationId) {
  var receipt = guestReadOperation_(book, operationId);
  var fence = scriptProperty_(GUEST_FENCE_PROPERTY);
  if (fence !== operationId) return receipt;
  var journal = guestJournal_();
  if (receipt && receipt.status === 'completed' && guestVerifyTargets_(book, receipt.targetState)) {
    guestClearJournal_(); return receipt;
  }
  if (receipt && (receipt.status === 'rejected' || receipt.status === 'not_applied')) {
    guestClearJournal_(); return receipt;
  }
  if (journal && scriptProperty_(GUEST_JOURNAL_PREFIX + 'PHASE') === 'reserved') {
    // Dispatch was never marked. The pending ledger reservation is not an attendance mutation.
    journal.status = 'not_applied';
    journal.response = errorResult('not_applied', 'This saved request was never dispatched. Review and submit a new operation.');
    if (book.getSheetById(journal.receiptLocation.sheetId)) {
      Sheets.Spreadsheets.batchUpdate({ requests: [guestOperationRequest_(journal)] }, book.getId());
      guestClearJournal_(); return journal;
    }
    // Bootstrap has no ledger yet. Keep its terminal receipt in properties and retain the
    // fence until an operator installs a ledger; structural setup must not replay itself.
    return journal;
  }
  return journal || receipt || { operationId: operationId, requestDigest: '', status: 'pending', response: null };
}
/** Reserve recovery material, then atomically apply data and its completed receipt. */
function guestExecutePlan_(book, request, canonicalRequest, plan, receiptLocation) {
  if (plan.requests.length > 500 || JSON.stringify(plan.requests).length > 180000) guestFail_('operation_too_large', 'This change needs a smaller verified batch.');
  guestValidateCapacity_(book, plan, receiptLocation);
  var operation = { operationId: request.operationId, requestDigest: request.requestDigest, status: 'pending',
    canonicalRequest: canonicalRequest, sourceRevisions: plan.sourceRevisions, targetState: plan.targetState,
    plannedRequests: plan.requests, receiptLocation: receiptLocation,
    response: Object.assign({ ok: true, operationId: request.operationId, status: 'completed' }, plan.response) };
  guestReserveJournal_(operation);
  try {
    // Reserve a visible pending row when the ledger already exists. Setup relies on the
    // bootstrap journal because creating its ledger is itself part of the final batch.
    if (book.getSheetById(receiptLocation.sheetId)) {
      Sheets.Spreadsheets.batchUpdate({ requests: [guestOperationRequest_(operation)] }, book.getId());
    }
    PropertiesService.getScriptProperties().setProperty(GUEST_JOURNAL_PREFIX + 'PHASE', 'dispatching');
    var completed = Object.assign({}, operation, { status: 'completed' });
    Sheets.Spreadsheets.batchUpdate({ requests: plan.requests.concat([guestOperationRequest_(completed)]) }, book.getId());
    var saved = guestReadOperation_(book, request.operationId);
    if (!saved || saved.status !== 'completed' || !guestVerifyTargets_(book, saved.targetState)) return guestPending_(request.operationId);
    guestClearJournal_();
    return saved.response;
  } catch (error) {
    // Service exceptions do not prove rejection: transport may have lost an applied
    // response. Leave the original recovery journal and workbook fence intact.
    return guestPending_(request.operationId);
  }
}
