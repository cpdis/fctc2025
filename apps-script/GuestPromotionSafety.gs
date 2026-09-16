/** Keep original member cells, notes and formula structure as postconditions. */
function guestPromotionSnapshot_(ctx, member, name) {
  var range = ctx.sheet.getDataRange(), formulas = range.getFormulas(), notes = range.getNotes();
  var values = ctx.grid.map(function (r) { return r.slice(); }), derived = [];
  ctx.runs.forEach(function (run) {
    for (var col = ctx.bounds.plusOnesCol + 1; col <= values[run.rowIndex - 1].length; col++) {
      var value = values[run.rowIndex - 1][col - 1];
      if (formulas[run.rowIndex - 1][col - 1] && typeof value === 'number') {
        derived.push({ row: run.rowIndex, col: col + (member.insertion ? 1 : 0), value: value });
      }
    }
  });
  if (member.insertion) {
    values = guestMemberGrid_(values, member);
    formulas = guestMemberGrid_(formulas, member);
    notes = guestMemberGrid_(notes, member);
    for (var row = 0; row < ctx.headerRow - 1; row++) {
      var formula = formulas[row][member.templateCol - 1];
      formulas[row][member.column - 1] = formula;
      values[row][member.column - 1] = formula || '';
    }
    values[ctx.headerRow - 1][member.column - 1] = name;
  }
  return { values: values, formulas: formulas, notes: notes, derived: derived };
}
/** Translate a pre-insert column, including a member relocated by copy/paste. */
function guestProjectedColumn_(column, member) {
  if (!member || !member.insertion) return column;
  var insertion = member.insertion;
  if (insertion.relocateFirst && column === member.column) return insertion.insertBefore;
  if (insertion.relocateDisplaced && column === insertion.insertBefore) return insertion.insertBefore;
  return column >= insertion.insertBefore ? column + 1 : column;
}
function guestColumnA1_(column) {
  var text = '';
  while (column > 0) { column--; text = String.fromCharCode(65 + column % 26) + text; column = Math.floor(column / 26); }
  return text;
}
function guestDirectHistoryReference_(formula) {
  var match = /^=\s*(?:'(\d{4})'|(\d{4}))!\$?([A-Z]+)\$?(\d+)\s*$/i.exec(formula);
  if (!match) return null;
  var column = 0;
  match[3].toUpperCase().split('').forEach(function (letter) { column = column * 26 + letter.charCodeAt(0) - 64; });
  return { season: match[1] || match[2], column: column, row: Number(match[4]) };
}
function guestPlanExactFormula_(plan, ctx, row, col, formula, snapshot) {
  plan.requests.push(guestFormulaRequest_(ctx.sheetId, row, col, formula));
  if (!plan.targetState.formulas) plan.targetState.formulas = [];
  plan.targetState.formulas.push({ sheetId: ctx.sheetId, row: row, col: col, formula: formula });
  if (snapshot) {
    snapshot.formulas[row - 1][col - 1] = formula;
    snapshot.values[row - 1][col - 1] = formula;
  }
}
/** Preserve the originally referenced member when either end moves. A copy is
 * not a cut: Sheets does not retarget other seasons to a relocated member.
 */
function guestPlanExistingHistory_(plan, store, ctx, members, snapshot) {
  var formulas = ctx.sheet.getDataRange().getFormulas();
  for (var row = 0; row < ctx.headerRow - 1; row++) ctx.band.forEach(function (entry) {
    var formula = formulas[row][entry.colIndex - 1] || '';
    if (formula.indexOf('!') < 0) return;
    var reference = guestDirectHistoryReference_(formula);
    if (!reference) guestFail_('unsafe_member_formula', 'A dependent historical formula needs review before member columns can move.');
    var target = store.seasons.filter(function (season) { return season.sheetName === reference.season; })[0];
    if (!target || !target.band.some(function (m) { return m.colIndex === reference.column; })) {
      guestFail_('unsafe_member_formula', 'A historical formula does not point at a supported member column.');
    }
    var column = guestProjectedColumn_(entry.colIndex, members[ctx.sheetId]);
    var targetColumn = guestProjectedColumn_(reference.column, members[target.sheetId]);
    var corrected = "='" + reference.season + "'!" + guestColumnA1_(targetColumn) + reference.row;
    guestPlanExactFormula_(plan, ctx, row + 1, column, corrected, snapshot);
  });
}
/** Historical references use the target person's column, never the template person's. */
function guestPlanMemberHistory_(plan, store, ctx, member, members, snapshot) {
  var formulas = ctx.sheet.getDataRange().getFormulas();
  for (var row = 0; row < ctx.headerRow - 1; row++) {
    var references = [];
    ctx.band.forEach(function (entry) {
      var formula = formulas[row][entry.colIndex - 1] || '';
      if (formula.indexOf('!') < 0) return;
      var reference = guestDirectHistoryReference_(formula);
      if (!reference) guestFail_('unsafe_member_formula', 'A historical member formula needs review before a new column can be created.');
      if (!references.some(function (ref) { return ref.season === reference.season && ref.row === reference.row; })) references.push(reference);
    });
    if (references.length > 1) guestFail_('unsafe_member_formula', 'Historical formulas disagree about their source row. Review the season summary.');
    if (!references.length) continue;
    var reference = references[0], target = store.seasons.filter(function (season) { return season.sheetName === reference.season; })[0];
    if (!target || reference.row >= target.headerRow) guestFail_('unsafe_member_formula', 'The historical summary source is not a supported summary row.');
    var targetMember = members[target.sheetId];
    if (targetMember) {
      var formula = "='" + reference.season + "'!" + guestColumnA1_(targetMember.column) + reference.row;
      guestPlanExactFormula_(plan, ctx, row + 1, member.column, formula, snapshot);
    } else {
      guestPlanCell_(plan, ctx.sheetId, row + 1, member.column, [0]);
      if (snapshot) { snapshot.formulas[row][member.column - 1] = ''; snapshot.values[row][member.column - 1] = 0; }
    }
  }
}
/** Formula references change on insert/copy; operators and quoted text must survive.
 * Numeric derived run cells are checked separately. Reference adjustment itself is
 * verified on a real workbook copy, not inferred from this structural digest.
 */
function guestFormulaShape_(formula) {
  return formula.replace(/"(?:[^"]|"")*"|\$?[A-Z]{1,3}\$?\d+/gi, function (part) {
    return part[0] === '"' ? part : '@';
  });
}
function guestPreservationDigest_(values, formulas, notes) {
  return guestDigest_(JSON.stringify(values.map(function (row, r) {
    return row.map(function (value, c) { return [formulas[r][c] ? guestFormulaShape_(formulas[r][c]) : value,
      notes[r][c] || '']; });
  })));
}
function guestVerifyPromotion_(book, expected) {
  for (var i = 0; i < expected.length; i++) {
    var item = expected[i], sheet = book.getSheetById(item.sheetId);
    if (!sheet) return false;
    var range = sheet.getRange(1, 1, item.height, item.width), values = range.getValues();
    var formulas = range.getFormulas();
    if (guestPreservationDigest_(values, formulas, range.getNotes()) !== item.digest) return false;
    for (var d = 0; d < item.derived.length; d++) {
      var cell = item.derived[d], actual = values[cell.row - 1][cell.col - 1];
      if (typeof actual !== 'number' || Math.abs(actual - cell.value) > 0.0000001) return false;
    }
  }
  return true;
}
