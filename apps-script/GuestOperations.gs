/** Durable single-writer journal. No unknown delivery is retried automatically. */
var GUEST_JOURNAL_CHUNK = 1500; // At most 6 KB UTF-8; Script Properties allow 9 KB per value.
var GUEST_JOURNAL_MAX = 70000; // At most 280 KB plus keys, below the 500 KB property store limit.
function guestReadOperation_(book, operationId) {
  var sheet = book.getSheetByName(GUEST_TABLES.operations);
  if (!sheet) return null;
  var rows = sheet.getDataRange().getValues(), found = [];
  rows.slice(1).forEach(function (row) {
    if (row[0] !== operationId) return;
    var count = Number(row[2]);
    if (!Number.isInteger(count) || count < 1 || count > 120) guestFail_('invalid_operation', 'The operation receipt is unreadable. Keep writes paused.');
    var record = JSON.parse(row.slice(3, 3 + count).join(''));
    if (record.operationId !== operationId || row[1] !== record.status) guestFail_('invalid_operation', 'The operation receipt does not match its reserved row.');
    found.push(record);
  });
  if (found.length > 1) guestFail_('invalid_operation', 'Duplicate operation receipts need repair.');
  return found[0] || null;
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
  for (var i = 0; i < target.cells.length; i++) {
    var cell = target.cells[i], sheet = book.getSheetById(cell.sheetId);
    if (!sheet) return false;
    var value = sheet.getRange(cell.row, cell.col).getValues()[0][0];
    if ((value === '' ? null : value) !== (cell.value === '' ? null : cell.value)) return false;
  }
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
