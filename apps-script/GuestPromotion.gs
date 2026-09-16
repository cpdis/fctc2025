/** Promotion converts the original rows. No opening balance or aggregate credit. */
function guestPromotionContext_(store, request) {
  var guest = store.guests.filter(function (g) { return g.guestId === request.guestId; })[0];
  if (!guest) guestFail_('guest_missing', 'Select a saved shared guest.');
  if (guest.status !== 'active') guestFail_('guest_promoted', 'This guest is already a member. Refresh their history.', { memberName: guest.memberName });
  var name = SheetOps.cellText(request.memberName), mode = request.targetMode;
  if (!SheetOps.normalizeKey(name) || name.length > 200 || ['create', 'link'].indexOf(mode) < 0) {
    guestFail_('invalid_member', 'Choose a member name and explicitly create or link a member.');
  }
  var existing = [];
  store.seasons.forEach(function (ctx) {
    var matches = ctx.band.filter(function (m) { return SheetOps.normalizeKey(m.name) === SheetOps.normalizeKey(name); });
    if (matches.length > 1 || matches.some(function (m) { return m.name !== name; })) {
      guestFail_('member_identity_ambiguous', 'Member spellings differ between seasons. Review the exact member identity first.');
    }
    if (matches.length) existing.push(ctx.sheetId);
  });
  if (mode === 'create' && existing.length) guestFail_('member_exists', 'This member already exists. Review and explicitly choose link instead.');
  if (mode === 'link' && !existing.length) guestFail_('member_missing', 'Choose an existing member to link, or explicitly create a new member.');
  var rows = store.attendanceRows.filter(function (r) { return r.value.guestId === guest.guestId && r.value.state === 'present'; });
  var seen = {}, changes = [], affected = {};
  rows.forEach(function (row) {
    var record = row.value, key = guestRunKey(record);
    if (record.classification !== 'guest') guestFail_('invalid_attendance', 'An active guest has attendance already transferred. Review their history.');
    if (seen[key]) guestFail_('duplicate_attendance_identity', 'Repair duplicate guest attendance rows before promotion.');
    seen[key] = true;
    var run = guestRequire_(GuestOps.resolveRun(store.runs, record)).run;
    var ctx = guestSeason_(store, run.seasonSheetId), memberIndex = SheetOps.findMemberIndex(ctx.band, name);
    if (run.namedGuestIds.indexOf(guest.guestId) < 0 || run.plusOnes < 1) guestFail_('invalid_allocation', 'This run has no guest allocation to transfer.');
    if (memberIndex >= 0 && SheetOps.isAttendedMark(ctx.grid[run.rowIndex - 1][ctx.band[memberIndex].colIndex - 1])) {
      guestFail_('member_already_attended', 'The member is already marked on an affected run. Review the duplicate before promotion.', { runId: run.runId, seasonSheetId: ctx.sheetId });
    }
    var formulas = ctx.sheet.getDataRange().getFormulas();
    var targetColumn = memberIndex < 0 ? null : ctx.band[memberIndex].colIndex;
    if (formulas[run.rowIndex - 1][ctx.bounds.plusOnesCol - 1] || (targetColumn && formulas[run.rowIndex - 1][targetColumn - 1])) {
      guestFail_('unsafe_formula', 'A target attendance cell contains a formula. Review it before promotion.');
    }
    affected[ctx.sheetId] = true;
    changes.push({ spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId,
      rowIndex: run.rowIndex, date: run.date, run: run.run, plusOnesBefore: run.plusOnes, plusOnesAfter: run.plusOnes - 1,
      totalBefore: run.attendees.length + run.plusOnes, totalAfter: run.attendees.length + run.plusOnes,
      actualKmBefore: run.actualKm, actualKmAfter: run.actualKm });
  });
  if (!rows.length) guestFail_('guest_history_empty', 'Save at least one confirmed guest attendance before promotion.');
  var active = guestSeason_(store);
  affected[active.sheetId] = true; // A historical-only guest must appear in today's roster.
  var seasons = store.seasons.filter(function (ctx) { return affected[ctx.sheetId]; }).sort(function (a, b) { return a.seasonYear - b.seasonYear; });
  // The preview binds complete source contexts, including formulas and notes. A
  // manual edit invalidates the preview even if the visible attendance is unchanged.
  var source = store.seasons.map(function (ctx) { return { sheetId: ctx.sheetId, grid: ctx.grid,
    formulas: ctx.sheet.getDataRange().getFormulas(), notes: ctx.sheet.getDataRange().getNotes(),
    runs: ctx.runs.map(function (r) { return [r.rowIndex, r.runId]; }) }; });
  var token = guestDigest_(JSON.stringify([store.book.getId(), guest, store.guestRevision, name, mode, active.sheetId, source]));
  return { guest: guest, memberName: name, targetMode: mode, rows: rows, changes: changes, seasons: seasons,
    active: active, previewToken: token, confirmedRuns: rows.length };
}
function guestPreviewPromotion_(store, request) {
  var context = guestPromotionContext_(store, request);
  // Build the same plan during preview so formula or size problems are shown
  // before the organiser confirms. No request is dispatched here.
  var plan = guestBuildPromotion_(store, context);
  guestValidateCapacity_(store.book, plan, { sheetId: store.tables.operations.sheetId,
    rowIndex: store.tables.operations.grid.length + 1 });
  return okResult({ guestId: context.guest.guestId, memberName: context.memberName, targetMode: context.targetMode,
    confirmedRuns: context.confirmedRuns, previewToken: context.previewToken, changes: context.changes,
    seasons: context.seasons.map(function (ctx) { return { seasonYear: ctx.seasonYear, seasonSheetId: ctx.sheetId,
      runs: context.changes.filter(function (c) { return c.seasonSheetId === ctx.sheetId; }).length }; }) });
}
function guestPromotionPlan_(store, request) {
  var context = guestPromotionContext_(store, request);
  if (request.previewToken !== context.previewToken) guestFail_('promotion_changed', 'Saved history or the member choice changed. Review a new promotion preview.');
  return guestBuildPromotion_(store, context);
}
function guestBuildPromotion_(store, context) {
  var plan = guestPlan_(), members = {}, predicted = {}, snapshots = {};
  plan.sourceRevisions = { guestRevision: store.guestRevision, previewToken: context.previewToken };
  store.seasons.forEach(function (ctx) {
    var index = SheetOps.findMemberIndex(ctx.band, context.memberName);
    if (index >= 0) members[ctx.sheetId] = { column: ctx.band[index].colIndex };
  });
  context.seasons.forEach(function (ctx) {
    var member = members[ctx.sheetId];
    if (!member) member = members[ctx.sheetId] = guestPlanMember_(plan, ctx, context.memberName);
    snapshots[ctx.sheetId] = guestPromotionSnapshot_(ctx, member, context.memberName);
    predicted[ctx.sheetId] = Object.assign({}, ctx, { grid: snapshots[ctx.sheetId].values });
    plan.sourceRevisions['season:' + ctx.sheetId] = guestSheetRevision_(ctx, store.guestRevision);
  });
  // Unconverted seasons can refer to a relocated historical member. Preserve
  // their references too without creating an unnecessary new roster entry.
  store.seasons.forEach(function (ctx) {
    if (!snapshots[ctx.sheetId]) snapshots[ctx.sheetId] = guestPromotionSnapshot_(ctx, members[ctx.sheetId] || {}, context.memberName);
    guestPlanExistingHistory_(plan, store, ctx, members, snapshots[ctx.sheetId]);
  });
  context.seasons.forEach(function (ctx) {
    var member = members[ctx.sheetId];
    if (member.insertion) guestPlanMemberHistory_(plan, store, ctx, member, members, snapshots[ctx.sheetId]);
  });
  var attendance = store.attendance.slice();
  context.rows.forEach(function (row) {
    var run = guestRequire_(GuestOps.resolveRun(store.runs, row.value)).run, ctx = predicted[run.seasonSheetId];
    var member = members[ctx.sheetId], plusCol = ctx.bounds.plusOnesCol + (member.insertion ? 1 : 0);
    guestPlanCell_(plan, ctx.sheetId, run.rowIndex, member.column, ['x']);
    guestPlanCell_(plan, ctx.sheetId, run.rowIndex, plusCol, [run.plusOnes - 1]);
    ctx.grid[run.rowIndex - 1][member.column - 1] = 'x';
    ctx.grid[run.rowIndex - 1][plusCol - 1] = run.plusOnes - 1;
    plan.targetState.metadata.push({ sheetId: ctx.sheetId, row: run.rowIndex, runId: run.runId });
    var transferred = Object.assign({}, row.value, { classification: 'transferred', revision: row.value.revision + 1 });
    guestPlanRecord_(plan, store.tables.attendance, row.rowIndex, guestRunKey(transferred) + ':' + transferred.guestId, transferred);
    attendance[store.attendance.indexOf(row.value)] = transferred;
  });
  var promoted = Object.assign({}, context.guest, { status: 'promoted', memberName: context.memberName, revision: context.guest.revision + 1 });
  var guestRow = store.guestRows.filter(function (row) { return row.value.guestId === promoted.guestId; })[0];
  guestPlanRecord_(plan, store.tables.guests, guestRow.rowIndex, promoted.guestId, promoted);
  var guests = store.guests.map(function (g) { return g.guestId === promoted.guestId ? promoted : g; });
  var revision = guestRevision_(guests, attendance);
  plan.targetState.promotion = store.seasons.map(function (ctx) {
    var snapshot = snapshots[ctx.sheetId];
    return { sheetId: ctx.sheetId, height: snapshot.values.length, width: snapshot.values[0].length,
      digest: guestPreservationDigest_(snapshot.values, snapshot.formulas, snapshot.notes), derived: snapshot.derived };
  });
  plan.response = { guest: promoted, memberName: promoted.memberName, targetMode: context.targetMode,
    confirmedRuns: context.confirmedRuns, guestRevision: revision,
    sheetRevision: guestSheetRevision_(predicted[context.active.sheetId], revision) };
  // Promotion must fit one operation. Leave room for its envelope and receipt;
  // never split historical credit into independently committed batches.
  if (plan.requests.length > 500 || JSON.stringify(plan).length > GUEST_JOURNAL_MAX - 8000) {
    guestFail_('operation_too_large', 'This promotion exceeds the supported atomic limit. Keep the history unchanged and request a reviewed migration.');
  }
  return plan;
}
