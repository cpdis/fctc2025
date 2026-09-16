/** API v2 actions. All decisions run under the existing authenticated script lock. */
function guestRoute_(request) {
  var action = SheetOps.cellText(request.action);
  var shared = ['setupSharedGuests', 'createGuest', 'renameGuest', 'getGuestHistory', 'getOperationStatus',
    'importGuestHistory', 'previewPromotion', 'commitPromotion', 'exportAttendanceSnapshot'].indexOf(action) >= 0;
  var writes = ['submitAttendance', 'addMember', 'addRun'].indexOf(action) >= 0;
  if (!shared && !writes && action !== 'getState') return null;
  return withLock_(function () {
    var book = SpreadsheetApp.getActiveSpreadsheet(), store = null;
    // A request may wait behind setup or a mutation. These decisions must use
    // values read after acquiring the lock, never the request's arrival state.
    var enabled = sharedGuestsEnabled_(), fence = scriptProperty_(GUEST_FENCE_PROPERTY);
    // Setup commits the schema marker with the ledger. Disabling the feature is a
    // write pause, never a rollback to clients that cannot preserve named guests.
    var sharedFormat = book.getSheetByName(GUEST_TABLES.guests) !== null;
    try {
      if (action === 'getOperationStatus') {
        if (!guestIsUUID(request.operationId)) return errorResult('invalid_operation', 'Supply a valid operation ID.');
        return okResult({ operation: guestPublicOperation_(guestReconcile_(book, request.operationId)) });
      }
      if (action === 'getState') {
        if (!enabled) return withSheet_(function (ctx) {
          var state = stateOf_(ctx);
          if (request.apiVersion === 2) Object.assign(state, { apiVersion: 2, capabilities: guestCapabilities_(), pendingOperationId: fence || null });
          else if (fence) state.pendingOperationId = fence;
          return okResult(state);
        });
        store = guestReadStore_();
        return okResult(guestState_(store, request.seasonSheetId));
      }
      if (action === 'exportAttendanceSnapshot' && fence) return errorResult('busy', 'A saved change is waiting for verification.');
      if (writes && request.apiVersion !== 2) {
        if (fence) return guestPending_(fence);
        if (enabled || sharedFormat) return errorResult('update_required', 'This workbook uses shared guests. Update the app before recording attendance.');
        // Keep the legacy decision and write within this same lock. Returning to
        // the old router would release/reacquire it and reopen the setup race.
        return withSheet_(function (ctx) {
          if (action === 'submitAttendance') return submitAttendance_(ctx, request);
          if (action === 'addMember') return addMember_(ctx, request);
          return addRun_(ctx, request);
        });
      }
      if (!shared && !writes) return errorResult(ERR_UNKNOWN_ACTION, 'Unknown action.');
      if (action !== 'setupSharedGuests' && !enabled) return errorResult('shared_guests_disabled', 'Shared guests are not enabled for this workbook.');
      if (action === 'getGuestHistory') { store = guestReadStore_(); return guestHistory_(store, request.guestId); }
      if (action === 'previewPromotion' && typeof guestPreviewPromotion_ === 'function') {
        if (fence) return guestPending_(fence);
        return guestPreviewPromotion_(guestReadStore_(), request);
      }
      if (action === 'exportAttendanceSnapshot' && typeof guestExportSnapshot_ === 'function') return guestExportSnapshot_(book);
      var valid = guestRequire_(GuestOps.validateOperationRequest(request));
      if (guestDigest_(valid.canonicalRequest) !== request.requestDigest) return errorResult('invalid_operation', 'The request digest does not match its canonical payload.');
      var saved = guestReadOperation_(book, request.operationId);
      if (fence === request.operationId) {
        var journal = guestJournal_();
        if (journal) guestRequire_(GuestOps.inspectOperation(journal, request));
        saved = guestReconcile_(book, request.operationId);
      }
      var inspection = guestRequire_(GuestOps.inspectOperation(saved, request));
      if (inspection.disposition === 'replay') return saved.response;
      if (inspection.disposition === 'pending') return guestPending_(request.operationId);
      fence = scriptProperty_(GUEST_FENCE_PROPERTY);
      if (fence) return guestPending_(fence);
      var planned;
      if (action === 'setupSharedGuests') planned = guestSetupPlan_(book, request);
      else {
        store = guestReadStore_();
        planned = { plan: guestActionPlan_(store, request), receiptLocation: {
          sheetId: store.tables.operations.sheetId, rowIndex: store.tables.operations.grid.length + 1 } };
      }
      return guestExecutePlan_(book, request, valid.canonicalRequest, planned.plan, planned.receiptLocation);
    } catch (error) {
      if (!error.guestConflict) throw error;
      var conflict = error.guestConflict;
      if (store && ['submitAttendance', 'renameGuest', 'importGuestHistory', 'commitPromotion'].indexOf(action) >= 0) {
        try { conflict.state = guestState_(store, request.seasonSheetId); } catch (ignored) { /* Keep the original actionable conflict. */ }
      }
      return okResult({ conflict: conflict });
    }
  });
}
function guestActionPlan_(store, request) {
  var plan = guestPlan_();
  plan.sourceRevisions.guestRevision = store.guestRevision;
  if (request.action === 'createGuest' || request.action === 'renameGuest') {
    return guestIdentityPlan_(store, request, plan);
  }
  if (request.action === 'commitPromotion' && typeof guestPromotionPlan_ === 'function') return guestPromotionPlan_(store, request);
  if (request.action === 'importGuestHistory' && typeof guestImportPlan_ === 'function') return guestImportPlan_(store, request);
  if (request.action === 'submitAttendance') return guestAttendancePlan_(store, request, plan);
  if (request.action !== 'addMember' && request.action !== 'addRun') guestFail_('unsupported_action', 'This shared guest action is not available yet.');
  var ctx = guestSeason_(store, request.seasonSheetId);
  var revision = guestSheetRevision_(ctx, store.guestRevision);
  if (request.baseRevision !== revision) guestFail_('stale_revision', 'Refresh the season before changing its structure.');
  plan.sourceRevisions.sheetRevision = revision;
  if (request.action === 'addMember') {
    var name = SheetOps.cellText(request.name), member = guestPlanMember_(plan, ctx, name);
    var memberGrid = ctx.grid.map(function (row) {
      var copy = row.slice(); copy.splice(member.insertion.insertBefore - 1, 0, '');
      if (member.insertion.relocateDisplaced) {
        copy[member.insertion.insertBefore - 1] = copy[member.insertion.displacedCol - 1];
        copy[member.insertion.displacedCol - 1] = '';
      }
      return copy;
    });
    memberGrid[ctx.headerRow - 1][member.column - 1] = name;
    var memberContext = Object.assign({}, ctx, { grid: memberGrid });
    plan.response = { memberName: name, colIndex: member.column,
      roster: SheetOps.sheetGeometry(memberGrid).band, sheetRevision: guestSheetRevision_(memberContext, store.guestRevision) };
  } else {
    if (request.spreadsheetId !== store.book.getId()) guestFail_('run_missing', 'This new run belongs to another workbook.');
    var run = guestPlanRun_(plan, store, ctx, request);
    var runGrid = ctx.grid.map(function (row) { return row.slice(); });
    runGrid.splice(run.rowIndex - 1, 0, new Array(ctx.grid[0].length).fill(''));
    plan.targetState.cells.filter(function (cell) { return cell.sheetId === ctx.sheetId; }).forEach(function (cell) {
      runGrid[cell.row - 1][cell.col - 1] = cell.value;
    });
    var predictedRuns = SheetOps.listRuns(runGrid, ctx.headerRow).map(function (entry) {
      if (entry.rowIndex === run.rowIndex) return Object.assign({}, entry, {
        spreadsheetId: store.book.getId(), seasonSheetId: ctx.sheetId, seasonYear: ctx.seasonYear,
        runId: run.runId, namedGuestIds: [], unnamedGuests: 0 });
      var previousRow = entry.rowIndex > run.rowIndex ? entry.rowIndex - 1 : entry.rowIndex;
      return Object.assign({}, ctx.runs.filter(function (old) { return old.rowIndex === previousRow; })[0], entry);
    });
    var runContext = Object.assign({}, ctx, { grid: runGrid, runs: predictedRuns });
    plan.response = { spreadsheetId: store.book.getId(), seasonSheetId: ctx.sheetId, runId: run.runId,
      rowIndex: run.rowIndex, runs: predictedRuns, sheetRevision: guestSheetRevision_(runContext, store.guestRevision) };
  }
  return plan;
}
function guestIdentityPlan_(store, request, plan) {
  var guest, row, guests = store.guests.slice();
  if (request.action === 'createGuest') {
    if (!guestIsUUID(request.guestId)) guestFail_('invalid_guest', 'Supply a stable guest UUID.');
    if (guests.some(function (g) { return g.guestId === request.guestId; })) guestFail_('duplicate_guest_identity', 'This guest ID already exists. Select the existing person.');
    var resolved = guestRequire_(GuestOps.resolveGuestIdentity(guests, { displayName: request.displayName, confirmDistinct: request.confirmDistinct }));
    guest = { guestId: request.guestId, displayName: resolved.displayName, status: 'active', memberName: null, revision: 1 };
    row = store.tables.guests.grid.length + 1;
    guests.push(guest);
  } else {
    guest = guestRequire_(GuestOps.renameGuest(guests, request.guestId, request.displayName, request.baseGuestRevision)).guest;
    var index = guests.findIndex(function (g) { return g.guestId === guest.guestId; });
    guests[index] = guest; row = store.guestRows[index].rowIndex;
  }
  if (guest.displayName.length > 200) guestFail_('invalid_guest', 'Keep the guest name to 200 characters or fewer.');
  guestPlanRecord_(plan, store.tables.guests, row, guest.guestId, guest);
  plan.response = { guest: guest, guestRevision: guestRevision_(guests, store.attendance) };
  return plan;
}
function guestAttendancePlan_(store, request, plan) {
  var run = guestRequire_(GuestOps.resolveRun(store.runs, request)).run;
  var ctx = guestSeason_(store, run.seasonSheetId), revision = guestSheetRevision_(ctx, store.guestRevision);
  if (!SheetOps.sameRunIdentity(run.date, run.run, request.expectedDate, request.expectedRun)) guestFail_('row_mismatch', 'The selected run date or label changed. Refresh this run.');
  if (!isStringArray_(request.attendees) || ['merge', 'overwrite'].indexOf(request.mode) < 0) guestFail_('invalid_attendance', 'Choose attendance and an explicit save mode.');
  if (request.actualKm !== null && (typeof request.actualKm !== 'number' || !Number.isFinite(request.actualKm) || request.actualKm < 0)) guestFail_('invalid_attendance', 'Enter a valid distance or leave it blank.');
  // Validate identities before the revision check so a stale phone receives the member mapping.
  var proposed = guestRequire_(GuestOps.validateAllocation(request, store.guests));
  if (request.mode === 'overwrite' && request.baseRevision !== revision) guestFail_('stale_revision', 'The run or guests changed. Review the current attendance before replacing it.');
  var allocation = request.mode === 'merge' ? guestRequire_(GuestOps.mergeAllocation(run, proposed.allocation, store.guests)) : proposed;
  // Merge uses the explicit guest allocation. The old aggregate max cannot restore transferred guests.
  var rowPlan = SheetOps.buildRowWrite(ctx.band, request.attendees, allocation.plusOnes, request.actualKm,
    { mode: request.mode, existingValues: SheetOps.memberValuesAt(ctx.grid, ctx.headerRow, run.rowIndex), existingPlusOnes: allocation.plusOnes, existingActualKm: run.actualKm });
  if (rowPlan.unknownNames.length) guestFail_('member_missing', 'Select members from the current roster.');
  var formulas = ctx.sheet.getDataRange().getFormulas();
  function write(col, value) {
    if (formulas[run.rowIndex - 1] && formulas[run.rowIndex - 1][col - 1]) guestFail_('unsafe_formula', 'A target attendance cell contains a formula. Review the sheet before saving.');
    guestPlanCell_(plan, ctx.sheetId, run.rowIndex, col, [value]);
  }
  rowPlan.memberValues.forEach(function (value, index) {
    var col = ctx.bounds.firstMemberCol + index;
    if (value !== SheetOps.cellText(ctx.grid[run.rowIndex - 1][col - 1])) write(col, value);
  });
  if (allocation.plusOnes !== run.plusOnes) write(ctx.bounds.plusOnesCol, allocation.plusOnes);
  if (rowPlan.writeActualKm) write(ctx.bounds.actualKmCol, rowPlan.actualKm);
  var attendance = store.attendance.slice(), nextRow = store.tables.attendance.grid.length + 1;
  var affected = run.namedGuestIds.concat(allocation.allocation.namedGuestIds).filter(function (id, index, all) { return all.indexOf(id) === index; });
  affected.forEach(function (id) {
    var rows = store.attendanceRows.filter(function (r) { return r.value.guestId === id && guestRunKey(r.value) === guestRunKey(run); });
    if (rows.length > 1) guestFail_('duplicate_attendance_identity', 'Repair duplicate guest attendance rows before editing this run.');
    var old = rows[0], present = allocation.allocation.namedGuestIds.indexOf(id) >= 0;
    if (old && old.value.state === (present ? 'present' : 'removed')) return;
    if (old && old.value.classification === 'transferred') guestFail_('guest_promoted', 'This attendance was transferred to a member. Refresh and review it.');
    var record = Object.assign({ spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId,
      guestId: id, classification: 'guest' }, { state: present ? 'present' : 'removed', revision: old ? old.value.revision + 1 : 1 });
    guestPlanRecord_(plan, store.tables.attendance, old ? old.rowIndex : nextRow++, guestRunKey(record) + ':' + id, record);
    if (old) attendance[store.attendance.indexOf(old.value)] = record; else attendance.push(record);
  });
  var predicted = Object.assign({}, ctx, { grid: ctx.grid.map(function (r) { return r.slice(); }) });
  plan.targetState.cells.filter(function (c) { return c.sheetId === ctx.sheetId; }).forEach(function (c) { predicted.grid[c.row - 1][c.col - 1] = c.value; });
  var guestRevision = guestRevision_(store.guests, attendance);
  plan.sourceRevisions.sheetRevision = revision;
  plan.response = { written: plan.targetState.cells.length, sheetRevision: guestSheetRevision_(predicted, guestRevision), guestRevision: guestRevision };
  return plan;
}
