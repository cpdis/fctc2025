const test = require('node:test');
const assert = require('node:assert/strict');
const { createEnvironment } = require('./support/fakeAppsScript');

test('batch fake validates the whole batch before changing a sheet', () => {
  const env = createEnvironment({ grid: [['before']], sheetId: 26 });
  assert.equal(typeof env.context.Sheets?.Spreadsheets.batchUpdate, 'function');
  assert.throws(() => env.context.Sheets.Spreadsheets.batchUpdate({ requests: [
    { updateCells: { start: { sheetId: 26, rowIndex: 0, columnIndex: 0 }, rows: [{ values: [{ userEnteredValue: { stringValue: 'after' } }] }], fields: 'userEnteredValue' } },
    { insertDimension: { range: { sheetId: 999, dimension: 'ROWS', startIndex: 0, endIndex: 1 } } }
  ] }, env.spreadsheet.getId()));
  assert.equal(env.grid()[0][0], 'before');
});

test('batch fake preserves committed data and metadata after a lost response and process restart', () => {
  const env = createEnvironment({ grid: [['header'], ['run']], sheetId: 26 });
  env.failNextBatch('after');
  assert.throws(() => env.context.Sheets.Spreadsheets.batchUpdate({ requests: [
    { createDeveloperMetadata: { developerMetadata: { metadataKey: 'fctc.runId', metadataValue: 'stable-id', visibility: 'DOCUMENT', location: { dimensionRange: { sheetId: 26, dimension: 'ROWS', startIndex: 1, endIndex: 2 } } } } }
  ] }, env.spreadsheet.getId()));
  const restarted = env.restart();
  restarted.sheet.insertRowBefore(2);
  assert.deepEqual(restarted.context.Sheets.Spreadsheets.get(restarted.spreadsheet.getId()).sheets[0].developerMetadata, []);
  const meta = restarted.context.Sheets.Spreadsheets.DeveloperMetadata.search({ dataFilters: [
    { developerMetadataLookup: { metadataKey: 'fctc.runId' } },
  ] }, restarted.spreadsheet.getId()).matchedDeveloperMetadata[0].developerMetadata;
  assert.equal(meta.location.dimensionRange.startIndex, 2);
  assert.equal(meta.metadataValue, 'stable-id');
});
