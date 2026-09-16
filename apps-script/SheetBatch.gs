/** Small Sheets v4 write planner. Cell updates preserve notes and formatting. */
function guestCellRequest_(sheetId, row, col, values) {
  return { updateCells: { start: { sheetId: sheetId, rowIndex: row - 1, columnIndex: col - 1 },
    rows: [{ values: values.map(function (value) {
      if (value === '' || value === null) return {};
      return { userEnteredValue: typeof value === 'number' ? { numberValue: value } :
        typeof value === 'boolean' ? { boolValue: value } : { stringValue: String(value) } };
    }) }], fields: 'userEnteredValue' } };
}
function guestFormulaRequest_(sheetId, row, col, formula) {
  return { updateCells: { start: { sheetId: sheetId, rowIndex: row - 1, columnIndex: col - 1 },
    rows: [{ values: [{ userEnteredValue: { formulaValue: formula } }] }], fields: 'userEnteredValue' } };
}
function guestMetadataRequest_(sheetId, row, runId) {
  return { createDeveloperMetadata: { developerMetadata: { metadataKey: GUEST_RUN_METADATA,
    metadataValue: runId, visibility: 'DOCUMENT', location: { dimensionRange: {
      sheetId: sheetId, dimension: 'ROWS', startIndex: row - 1, endIndex: row
    } } } } };
}
function guestPlan_() { return { requests: [], targetState: { cells: [], metadata: [], sheets: [] }, response: {}, sourceRevisions: {} }; }
function guestPlanCell_(plan, sheetId, row, col, values) {
  plan.requests.push(guestCellRequest_(sheetId, row, col, values));
  values.forEach(function (value, index) { plan.targetState.cells.push({ sheetId: sheetId, row: row, col: col + index, value: value }); });
}
function guestPlanRecord_(plan, table, row, key, value) { guestPlanCell_(plan, table.sheetId, row, 1, [key, JSON.stringify(value)]); }
function guestPlanMetadata_(plan, sheetId, row, runId) {
  plan.requests.push(guestMetadataRequest_(sheetId, row, runId));
  plan.targetState.metadata.push({ sheetId: sheetId, row: row, runId: runId });
}
function guestCopyRequest_(sheetId, fromRow, fromCol, toRow, toCol, height, width, pasteType) {
  function range(row, col) { return { sheetId: sheetId, startRowIndex: row - 1, endRowIndex: row - 1 + height,
    startColumnIndex: col - 1, endColumnIndex: col - 1 + width }; }
  return { copyPaste: { source: range(fromRow, fromCol), destination: range(toRow, toCol),
    pasteType: pasteType || 'PASTE_NORMAL', pasteOrientation: 'NORMAL' } };
}
/** In-band insertion retains the existing formula expansion rule, including the last name. */
function guestPlanMember_(plan, ctx, name) {
  if (!SheetOps.normalizeKey(name)) guestFail_('invalid_member', 'Enter a member name.');
  if (SheetOps.findMemberIndex(ctx.band, name) >= 0) guestFail_('duplicate_member', 'This member already exists.');
  if (ctx.band.length < 2) guestFail_('unsafe_member_insertion', 'This season needs a reviewed member formula template.');
  var position = SheetOps.alphabeticalInsertIndex(ctx.band, name);
  var insertion = SheetOps.memberInsertPlan(ctx.band, ctx.bounds, position);
  plan.requests.push({ insertDimension: { range: { sheetId: ctx.sheetId, dimension: 'COLUMNS',
    startIndex: insertion.insertBefore - 1, endIndex: insertion.insertBefore }, inheritFromBefore: false } });
  var newCol = insertion.insertBefore;
  if (insertion.relocateDisplaced) {
    // Full-cell relocation keeps absence annotations, notes and relative summary formulas.
    plan.requests.push(guestCopyRequest_(ctx.sheetId, 1, insertion.displacedCol, 1, insertion.insertBefore, ctx.sheet.getMaxRows(), 1));
    plan.requests.push({ repeatCell: { range: { sheetId: ctx.sheetId, startColumnIndex: insertion.displacedCol - 1,
      endColumnIndex: insertion.displacedCol }, cell: {}, fields: 'userEnteredValue,note' } });
    newCol = insertion.displacedCol;
  }
  guestPlanCell_(plan, ctx.sheetId, ctx.headerRow, newCol, [name]);
  return { column: newCol, insertion: insertion };
}
/** New rows receive their locator and copied derived formulas in the same batch. */
function guestPlanRun_(plan, store, ctx, request) {
  var date = SheetOps.cellText(request.date), run = SheetOps.cellText(request.run);
  if (!SheetOps.parseSheetDate(date) || !run) guestFail_('invalid_run', 'Enter a valid run date and label.');
  if (SheetOps.findRunRows(ctx.grid, ctx.headerRow, { date: date, run: run }).length) guestFail_('duplicate_run', 'This run already exists.');
  var target = SheetOps.runInsertTarget(ctx.runs, ctx.headerRow, date);
  var template = templateRowFor_(ctx.runs, target);
  if (template >= target.rowIndex) template++;
  plan.requests.push({ insertDimension: { range: { sheetId: ctx.sheetId, dimension: 'ROWS',
    startIndex: target.rowIndex - 1, endIndex: target.rowIndex }, inheritFromBefore: target.rowIndex > 1 } });
  guestPlanCell_(plan, ctx.sheetId, target.rowIndex, ctx.bounds.dateCol,
    [date, SheetOps.cellText(request.meet), run, SheetOps.numberOrNull(request.approxKm)]);
  var firstDerived = ctx.bounds.plusOnesCol + 1;
  if (template && ctx.grid[0].length >= firstDerived) {
    plan.requests.push(guestCopyRequest_(ctx.sheetId, template, firstDerived, target.rowIndex, firstDerived,
      1, ctx.grid[0].length - firstDerived + 1, 'PASTE_FORMULA'));
  }
  var runId = Utilities.getUuid().toLowerCase();
  guestPlanMetadata_(plan, ctx.sheetId, target.rowIndex, runId);
  return { runId: runId, rowIndex: target.rowIndex };
}
