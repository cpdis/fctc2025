/** Reviewed local history only names existing guest slots; it never adds headcount. */
function guestImportReview_(store, request) {
  var guest = guestRequire_(GuestOps.resolveGuestIdentity(store.guests, { guestId: request.guestId })).guest;
  if (!Array.isArray(request.entries) || request.entries.length < 1 || request.entries.length > 100) {
    guestFail_('invalid_import', 'Select between one and 100 confirmed run allocations to review.');
  }
  var seen = {}, entries = [], changes = [], rows = [], revisions = {};
  request.entries.forEach(function (entry) {
    guestRequire_(GuestOps.validateRunIdentity(entry));
    if (entry.assignment !== 'existing_unnamed_slot' || !guestHasText(entry.expectedDate) || !guestHasText(entry.expectedRun)) {
      guestFail_('invalid_import', 'Choose an existing unnamed slot on a dated run.');
    }
    var run = guestRequire_(GuestOps.resolveRun(store.runs, entry)).run;
    if (!SheetOps.sameRunIdentity(run.date, run.run, entry.expectedDate, entry.expectedRun)) {
      guestFail_('row_mismatch', 'The selected historical run changed. Review its date and label.');
    }
    var key = guestRunKey(run);
    if (seen[key]) return;
    seen[key] = true;
    var matches = store.attendanceRows.filter(function (row) {
      return row.value.guestId === guest.guestId && guestRunKey(row.value) === key;
    });
    if (matches.length > 1) guestFail_('duplicate_attendance_identity', 'Repair duplicate attendance before importing history.');
    var old = matches[0];
    if (old && old.value.classification === 'transferred') {
      guestFail_('guest_promoted', 'This run was already transferred. Review the member attendance.');
    }
    var assigned = !!old && old.value.state === 'present';
    if (!assigned && run.unnamedGuests < 1) {
      guestFail_('allocation_missing', 'This run has no unnamed guest slot. Correct the saved attendance before importing.', {
        spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId
      });
    }
    var resolved = { spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId,
      expectedDate: run.date, expectedRun: run.run, assignment: 'existing_unnamed_slot' };
    entries.push(resolved);
    changes.push(Object.assign({}, resolved, { alreadyAssigned: assigned,
      unnamedBefore: run.unnamedGuests, unnamedAfter: run.unnamedGuests - (assigned ? 0 : 1) }));
    rows.push({ run: run, existing: old, alreadyAssigned: assigned });
    var ctx = guestSeason_(store, run.seasonSheetId);
    revisions[String(ctx.sheetId)] = guestSheetRevision_(ctx, store.guestRevision);
  });
  var token = guestDigest_(GuestOps.canonicalJSON({ guestId: guest.guestId, guestRevision: guest.revision,
    revisions: revisions, entries: entries.slice().sort(function (a, b) { return guestRunKey(a).localeCompare(guestRunKey(b)); }) }));
  return { guest: guest, rows: rows, sourceRevisions: revisions, response: {
    guestId: guest.guestId, baseGuestRevision: guest.revision, baseRevision: token,
    entries: entries, changes: changes, confirmedRuns: guestSummary_(store, guest).confirmedRuns
  } };
}
function guestPreviewImport_(store, request) {
  return okResult(guestImportReview_(store, request).response);
}
function guestImportPlan_(store, request) {
  var reviewed = guestImportReview_(store, request), plan = guestPlan_();
  if (request.baseGuestRevision !== reviewed.guest.revision) {
    guestFail_('stale_guest_revision', 'This guest changed. Review the person before importing history.');
  }
  var additions = reviewed.rows.filter(function (row) { return !row.alreadyAssigned; });
  // A second phone may have completed the exact same assignments. That is a
  // successful no-op, even when its earlier preview token has become stale.
  if (additions.length && request.baseRevision !== reviewed.response.baseRevision) {
    guestFail_('stale_revision', 'The historical allocations changed. Review the import again.');
  }
  var attendance = store.attendance.slice(), nextRow = store.tables.attendance.grid.length + 1;
  plan.sourceRevisions = Object.assign({ guestRevision: store.guestRevision }, reviewed.sourceRevisions);
  additions.forEach(function (item) {
    var run = item.run, old = item.existing;
    if (old && old.value.revision === Number.MAX_SAFE_INTEGER) guestFail_('invalid_attendance', 'This attendance revision cannot be increased.');
    var record = { guestId: reviewed.guest.guestId, spreadsheetId: run.spreadsheetId,
      seasonSheetId: run.seasonSheetId, runId: run.runId, state: 'present', classification: 'guest',
      revision: old ? old.value.revision + 1 : 1 };
    guestPlanRecord_(plan, store.tables.attendance, old ? old.rowIndex : nextRow++,
      guestRunKey(record) + ':' + record.guestId, record);
    if (old) attendance[store.attendance.indexOf(old.value)] = record;
    else attendance.push(record);
    // Preserve the reviewed cells as postconditions without writing to them.
    // This catches a direct sheet edit during the operation's verification window.
    var ctx = guestSeason_(store, run.seasonSheetId);
    [ctx.bounds.actualKmCol, ctx.bounds.plusOnesCol].concat(ctx.band.map(function (m) { return m.colIndex; }))
      .forEach(function (col) { plan.targetState.cells.push({ sheetId: ctx.sheetId, row: run.rowIndex,
        col: col, value: ctx.grid[run.rowIndex - 1][col - 1] }); });
  });
  plan.response = { guestId: reviewed.guest.guestId, importedRuns: additions.length,
    confirmedRuns: reviewed.response.confirmedRuns + additions.length,
    guestRevision: guestRevision_(store.guests, attendance) };
  return plan;
}
