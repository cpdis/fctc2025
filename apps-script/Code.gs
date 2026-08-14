/**
 * FCTC Attendance — Apps Script Web App (STUB, U1).
 *
 * The real router, auth, LockService serialization and the four actions land in U2.
 * This file exists so the project deploys and answers with a well-formed error
 * instead of an HTML stack trace.
 *
 * Contract (FROZEN — see docs/plans/packets/_conventions.md):
 *   POST  { secret, action, ...payload }
 *   200   { ok: true, ... } | { ok: false, error: "code", message: "..." }
 *   Actions: getState | submitAttendance | addMember | addRun
 *
 * Sheet-safety invariant (every unit): nothing is ever written outside a run row's
 * member band + `Actual kms` + `+1's` cells, the member-band header row, or an
 * inserted run row. Formula/summary rows and columns are sacrosanct.
 */

/** Script Property holding the shared secret the iOS app sends. Set it in the editor:
 *  Project Settings > Script Properties > SHARED_SECRET = <a long random string>.
 *  Never commit the value. */
var SECRET_PROPERTY = 'SHARED_SECRET';

/** Script Property naming the season tab (e.g. "2026"). Bump each new season. */
var SEASON_SHEET_PROPERTY = 'SEASON_SHEET_NAME';

/**
 * Web app entry point.
 * @param {GoogleAppsScript.Events.DoPost} e
 * @return {GoogleAppsScript.Content.TextOutput} JSON response.
 */
function doPost(e) {
  // TODO(U2): parse e.postData.contents, check the shared secret, route to the four
  // actions inside a LockService critical section, and return structured results.
  return jsonResponse({
    ok: false,
    error: 'not_implemented',
    message: 'The FCTC Attendance API is scaffolded but not implemented yet (U2).',
  });
}

/**
 * GET is not part of the contract; answer politely so a browser visit is
 * self-explanatory rather than a stack trace.
 * @return {GoogleAppsScript.Content.TextOutput} JSON response.
 */
function doGet() {
  return jsonResponse({
    ok: false,
    error: 'method_not_allowed',
    message: 'POST JSON to this endpoint. See apps-script/README.md.',
  });
}

/**
 * Serialize a payload as a JSON response.
 * @param {!Object} payload
 * @return {GoogleAppsScript.Content.TextOutput}
 */
function jsonResponse(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload)).setMimeType(
    ContentService.MimeType.JSON
  );
}
