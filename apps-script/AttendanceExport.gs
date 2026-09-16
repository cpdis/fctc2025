/** Keep this allowlist aligned with src/config/years.js; the test checks both. */
var ATTENDANCE_EXPORT_YEARS = [2025, 2026];
var ATTENDANCE_EXPORT_MAX_CELLS = 250000;
var ATTENDANCE_EXPORT_MAX_CHARACTERS = 1200000;

/** Called only by the authenticated route under its script lock and write fence. */
function guestExportSnapshot_(book) {
  if (scriptProperty_(GUEST_FENCE_PROPERTY)) return errorResult('busy', 'A saved change is waiting for verification.');
  var seasons = [], cellCount = 0;
  for (var i = 0; i < ATTENDANCE_EXPORT_YEARS.length; i++) {
    var year = ATTENDANCE_EXPORT_YEARS[i], sheet = book.getSheetByName(String(year));
    if (!sheet) return errorResult('snapshot_invalid', 'A supported attendance season is missing.');
    var range = sheet.getDataRange(), grid = range.getDisplayValues();
    cellCount += grid.reduce(function (count, row) { return count + row.length; }, 0);
    if (cellCount > ATTENDANCE_EXPORT_MAX_CELLS) return errorResult('snapshot_too_large', 'The attendance snapshot exceeds its supported size.');
    if (!SheetOps.sheetGeometry(grid)) return errorResult('snapshot_invalid', 'A supported season has an unreadable attendance header.');
    seasons.push({ year: year, seasonSheetId: sheet.getSheetId(), title: sheet.getName(), grid: grid });
  }
  // One digest binds every exported season. The capture time deliberately does
  // not affect it, so an unchanged workbook causes no commit or deployment.
  var content = JSON.stringify({ spreadsheetId: book.getId(), seasons: seasons });
  if (content.length > ATTENDANCE_EXPORT_MAX_CHARACTERS) {
    return errorResult('snapshot_too_large', 'The attendance snapshot exceeds its supported size.');
  }
  return okResult({ apiVersion: 2, spreadsheetId: book.getId(), capturedAt: new Date().toISOString(),
    snapshotRevision: guestDigest_(content), seasons: seasons });
}
