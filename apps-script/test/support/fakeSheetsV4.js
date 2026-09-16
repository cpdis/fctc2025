'use strict';

/**
 * Bounded Sheets v4 stand-in for server integration tests. A batch executes on a
 * detached workbook and commits only after every request validates. This models
 * atomic failure and lost responses; it deliberately does not evaluate formulas
 * or prove Google's reference-expansion behaviour (those need a real copy).
 */
function makeSheetsService({ allSheets, spreadsheetId, FakeSheet }) {
  const batches = [];
  let nextFailure = null;
  function requireBook(id) {
    if (id !== spreadsheetId) throw new Error('Unknown spreadsheet ID');
  }
  function properties(sheet) {
    return { sheetId: sheet.sheetId, title: sheet.name, hidden: sheet.hidden,
      gridProperties: { rowCount: sheet.maxRows, columnCount: sheet.maxColumns } };
  }
  const api = { Spreadsheets: {
    get(id) {
      requireBook(id);
      return { spreadsheetId, sheets: allSheets.map(sheet => ({
        properties: properties(sheet), developerMetadata: structuredClone(sheet.metadata),
      })) };
    },
    DeveloperMetadata: {
      search(request, id) {
        requireBook(id);
        const lookups = request.dataFilters.map(filter => filter.developerMetadataLookup || {});
        return { matchedDeveloperMetadata: allSheets.flatMap(sheet => sheet.metadata)
          .filter(meta => lookups.some(lookup => (!lookup.metadataKey || lookup.metadataKey === meta.metadataKey)
            && (!lookup.metadataValue || lookup.metadataValue === meta.metadataValue)))
          .map(meta => ({ developerMetadata: structuredClone(meta) })) };
      },
    },
    batchUpdate(request, id) {
      requireBook(id);
      const failure = nextFailure;
      nextFailure = null;
      batches.push(structuredClone(request));
      if (failure === 'before') throw new Error('Simulated uncertain transport failure before application');
      const draft = allSheets.map(sheet => {
        const copy = new FakeSheet(sheet.name, sheet.values, sheet.sheetId);
        Object.assign(copy, structuredClone({ maxRows: sheet.maxRows, maxColumns: sheet.maxColumns,
          hidden: sheet.hidden, metadata: sheet.metadata, notes: sheet.notes, formats: sheet.formats, writes: sheet.writes }));
        return copy;
      });
      const replies = request.requests.map(part => applyRequest(part, draft, FakeSheet));
      // Keep existing object identities so callers' sheet handles see committed data.
      for (const changed of draft) {
        const current = allSheets.find(sheet => sheet.sheetId === changed.sheetId);
        if (current) Object.assign(current, changed);
        else allSheets.push(changed);
      }
      if (failure === 'after') throw new Error('Simulated response loss after atomic application');
      return { spreadsheetId, replies };
    },
  } };
  return { api, batches, failNextBatch: failure => { nextFailure = failure; } };
}

function sheetById(sheets, id) {
  const sheet = sheets.find(candidate => candidate.sheetId === id);
  if (!sheet) throw new Error('Invalid sheet ID: ' + id);
  return sheet;
}

function gridRange(sheet, range) {
  const r0 = range.startRowIndex ?? 0, r1 = range.endRowIndex ?? sheet.maxRows;
  const c0 = range.startColumnIndex ?? 0, c1 = range.endColumnIndex ?? sheet.maxColumns;
  if (![r0, r1, c0, c1].every(Number.isInteger) || r0 < 0 || c0 < 0 || r1 <= r0 || c1 <= c0
      || r1 > sheet.maxRows || c1 > sheet.maxColumns) throw new Error('Invalid grid range');
  return { r0, r1, c0, c1 };
}

function enteredValue(cell) {
  const value = cell.userEnteredValue || {};
  const fields = Object.keys(value);
  if (fields.length > 1) throw new Error('Value must have exactly one type');
  if (!fields.length) return '';
  const result = value[fields[0]];
  if (typeof result === 'string' && result.length > 50000) throw new Error('Cell exceeds 50,000 characters');
  if (fields[0] === 'numberValue' && (typeof result !== 'number' || !Number.isFinite(result))) throw new Error('Invalid numeric cell');
  if (!['stringValue', 'numberValue', 'boolValue', 'formulaValue'].includes(fields[0])) throw new Error('Invalid cell type');
  return result;
}

function writeCell(sheet, row, col, cell, fields) {
  const includes = name => fields === '*' || fields.split(',').some(field => field.trim().split('.')[0] === name);
  const key = `${row},${col}`;
  if (includes('userEnteredValue')) {
    sheet.ensure_(row + 1, col + 1);
    sheet.values[row][col] = enteredValue(cell);
  }
  if (includes('note')) sheet.notes[key] = cell.note || '';
  if (includes('userEnteredFormat')) sheet.formats[key] = structuredClone(cell.userEnteredFormat || {});
}

function moveCellMetadata(sheet, dimension, index, count) {
  for (const field of ['notes', 'formats']) {
    const moved = {};
    for (const [key, value] of Object.entries(sheet[field])) {
      let [row, col] = key.split(',').map(Number);
      if (dimension === 'ROWS' && row >= index) row += count;
      if (dimension === 'COLUMNS' && col >= index) col += count;
      moved[`${row},${col}`] = value;
    }
    sheet[field] = moved;
  }
}

function applyRequest(request, sheets, FakeSheet) {
  if (Object.keys(request).length !== 1) throw new Error('One request type required');
  if (request.addSheet) {
    const p = request.addSheet.properties;
    if (!p || !Number.isInteger(p.sheetId) || p.sheetId < 0
        || sheets.some(s => s.sheetId === p.sheetId || s.name === p.title)) throw new Error('Duplicate or invalid sheet');
    const sheet = new FakeSheet(p.title, [], p.sheetId);
    sheet.hidden = !!p.hidden;
    sheet.maxRows = p.gridProperties?.rowCount ?? 1000;
    sheet.maxColumns = p.gridProperties?.columnCount ?? 26;
    sheets.push(sheet);
    return { addSheet: { properties: p } };
  }
  if (request.updateSheetProperties) {
    const { properties: p } = request.updateSheetProperties;
    const sheet = sheetById(sheets, p.sheetId);
    if (p.hidden !== undefined) sheet.hidden = p.hidden;
    if (p.title !== undefined) sheet.name = p.title;
    if (p.gridProperties?.rowCount !== undefined) sheet.maxRows = p.gridProperties.rowCount;
    if (p.gridProperties?.columnCount !== undefined) sheet.maxColumns = p.gridProperties.columnCount;
    return {};
  }
  if (request.createDeveloperMetadata) {
    const meta = structuredClone(request.createDeveloperMetadata.developerMetadata);
    const range = meta.location.dimensionRange;
    const sheet = sheetById(sheets, range?.sheetId ?? meta.location.sheetId);
    if (range && (range.dimension !== 'ROWS' || range.endIndex !== range.startIndex + 1
        || range.startIndex < 0 || range.endIndex > sheet.maxRows)) throw new Error('Invalid row metadata');
    meta.metadataId ??= 1 + Math.max(0, ...sheets.flatMap(s => s.metadata.map(m => m.metadataId)));
    sheet.metadata.push(meta);
    return { createDeveloperMetadata: { developerMetadata: meta } };
  }
  if (request.insertDimension) {
    const range = request.insertDimension.range;
    const sheet = sheetById(sheets, range.sheetId);
    const count = range.endIndex - range.startIndex;
    const limit = range.dimension === 'ROWS' ? sheet.maxRows : sheet.maxColumns;
    if (!['ROWS', 'COLUMNS'].includes(range.dimension) || range.startIndex < 0 || !Number.isInteger(count)
        || count < 1 || range.startIndex > limit) throw new Error('Invalid insertion');
    moveCellMetadata(sheet, range.dimension, range.startIndex, count);
    for (let i = 0; i < count; i++) {
      if (range.dimension === 'ROWS') sheet.insertRowBefore(range.startIndex + 1);
      else sheet.insertColumnBefore(range.startIndex + 1);
    }
    return {};
  }
  if (request.copyPaste) {
    const copy = request.copyPaste;
    const source = sheetById(sheets, copy.source.sheetId), target = sheetById(sheets, copy.destination.sheetId);
    const from = gridRange(source, copy.source), to = gridRange(target, copy.destination);
    const values = source.getRange(from.r0 + 1, from.c0 + 1, from.r1 - from.r0, from.c1 - from.c0).getValues();
    const notes = structuredClone(source.notes), formats = structuredClone(source.formats);
    target.writes.push({ kind: 'copyPaste', request: structuredClone(copy) });
    for (let r = to.r0; r < to.r1; r++) for (let c = to.c0; c < to.c1; c++) {
      const sr = from.r0 + (r - to.r0) % values.length, sc = from.c0 + (c - to.c0) % values[0].length;
      const value = values[sr - from.r0][sc - from.c0];
      if (copy.pasteType !== 'PASTE_FORMAT') {
        target.ensure_(r + 1, c + 1);
        target.values[r][c] = copy.pasteType === 'PASTE_FORMULA' && !(typeof value === 'string' && value.startsWith('=')) ? '' : value;
      }
      if (!copy.pasteType || copy.pasteType === 'PASTE_NORMAL' || copy.pasteType === 'PASTE_FORMAT') {
        target.formats[`${r},${c}`] = formats[`${sr},${sc}`] || {};
        if (copy.pasteType !== 'PASTE_FORMAT') target.notes[`${r},${c}`] = notes[`${sr},${sc}`] || '';
      }
    }
    return {};
  }
  const update = request.updateCells || request.repeatCell;
  if (update) {
    if (!update.fields) throw new Error('Explicit fields required');
    const sheet = sheetById(sheets, (update.range || update.start).sheetId);
    const range = update.range || {
      startRowIndex: update.start.rowIndex || 0,
      startColumnIndex: update.start.columnIndex || 0,
      endRowIndex: (update.start.rowIndex || 0) + update.rows.length,
      endColumnIndex: (update.start.columnIndex || 0) + Math.max(...update.rows.map(row => (row.values || []).length)),
    };
    const area = gridRange(sheet, range);
    for (let r = area.r0; r < area.r1; r++) for (let c = area.c0; c < area.c1; c++) {
      const cell = request.repeatCell ? update.cell : update.rows?.[r - area.r0]?.values?.[c - area.c0] || {};
      writeCell(sheet, r, c, cell, update.fields);
    }
    sheet.writes.push({ kind: 'batchCells', range: structuredClone(range), fields: update.fields });
    return {};
  }
  throw new Error('Unsupported fake batch request: ' + Object.keys(request)[0]);
}

module.exports = { makeSheetsService };
