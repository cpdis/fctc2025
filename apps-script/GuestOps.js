/**
 * Pure shared-guest contracts. No sheet, clock, randomness, or network access.
 * Names are labels; UUIDs identify people and runs. The I/O adapter computes
 * SHA-256 digests and wraps these conflicts in the existing API envelope.
 * All globals use the guest prefix to coexist with Apps Script's shared scope.
 */
var GUESTOPS_VERSION = '1.0.0';
var guestUUIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
var guestCapabilities = {
  apiVersion: 2, sharedGuests: true, stableRunIdentity: true,
  guestHistory: true, guestPromotion: true, operationReceipts: true
};
var guestOperationFields = {
  createGuest: ['guestId', 'displayName', 'confirmDistinct'],
  renameGuest: ['guestId', 'displayName', 'baseGuestRevision'],
  submitAttendance: ['spreadsheetId', 'seasonSheetId', 'runId', 'rowIndex', 'expectedDate',
    'expectedRun', 'attendees', 'namedGuestIds', 'unnamedGuests', 'actualKm', 'mode', 'baseRevision'],
  importGuestHistory: ['guestId', 'baseGuestRevision', 'entries', 'baseRevision'],
  commitPromotion: ['guestId', 'memberName', 'targetMode', 'previewToken'],
  addMember: ['name', 'baseRevision', 'seasonSheetId'],
  addRun: ['date', 'meet', 'run', 'approxKm', 'spreadsheetId', 'seasonSheetId', 'baseRevision'],
  setupSharedGuests: ['spreadsheetId', 'seasonSheetIds']
};

function guestConflict(reason, message, details) {
  return { ok: false, conflict: Object.assign({ reason: reason, message: message }, details || {}) };
}
function guestIsObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function guestIsUUID(value) { return typeof value === 'string' && guestUUIDPattern.test(value); }
function guestIsRevision(value) { return Number.isSafeInteger(value) && value >= 1; }
function guestHasText(value) { return typeof value === 'string' && value.trim().length > 0; }
function guestNameKey(value) {
  // Compare for suggestions only. Preserve letters outside the Latin alphabet.
  return value.trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ');
}

/** A promoted identity must retain its exact canonical member name. */
function guestValidateGuest(guest) {
  if (!guestIsObject(guest) || !guestIsUUID(guest.guestId) || !guestHasText(guest.displayName) ||
      !guestIsRevision(guest.revision) || ['active', 'promoted'].indexOf(guest.status) < 0 ||
      (guest.status === 'active' && guest.memberName !== null) ||
      (guest.status === 'promoted' && !guestHasText(guest.memberName))) {
    return guestConflict('invalid_guest', 'Guest identity, name, state, member mapping, or revision is invalid.');
  }
  return { ok: true, guest: guest };
}

/** Row index and displayed date are not part of identity. */
function guestValidateRunIdentity(run) {
  if (!guestIsObject(run) || !guestHasText(run.spreadsheetId) || !guestIsUUID(run.runId) ||
      !Number.isSafeInteger(run.seasonSheetId) || run.seasonSheetId < 0) {
    return guestConflict('invalid_run', 'Select a run with a workbook, season sheet, and stable run ID.');
  }
  return { ok: true, runIdentity: {
    spreadsheetId: run.spreadsheetId, seasonSheetId: run.seasonSheetId, runId: run.runId
  } };
}
function guestRunKey(run) {
  return JSON.stringify([run.spreadsheetId, run.seasonSheetId, run.runId]);
}

function guestValidateAttendance(record) {
  if (!guestIsObject(record) || !guestIsUUID(record.guestId) || !guestIsRevision(record.revision) ||
      ['present', 'removed'].indexOf(record.state) < 0 ||
      ['guest', 'transferred'].indexOf(record.classification) < 0 || !guestValidateRunIdentity(record).ok) {
    return guestConflict('invalid_attendance', 'Guest attendance has an invalid identity, state, or revision.');
  }
  return { ok: true, attendance: record };
}

/** Validate the registry before making an identity decision; duplicates are unsafe. */
function guestRegistry(guests) {
  if (!Array.isArray(guests)) return guestConflict('invalid_guest', 'The shared guest registry is invalid.');
  var seen = {};
  for (var i = 0; i < guests.length; i++) {
    var valid = guestValidateGuest(guests[i]);
    if (!valid.ok) return valid;
    if (seen[guests[i].guestId]) {
      return guestConflict('duplicate_guest_identity', 'Repair duplicate records for this guest before continuing.', { guestIds: [guests[i].guestId] });
    }
    seen[guests[i].guestId] = guests[i];
  }
  return { ok: true, byId: seen };
}

/** Even one matching label needs explicit selection; two people may share it. */
function guestResolveGuestIdentity(guests, selection) {
  var registry = guestRegistry(guests);
  if (!registry.ok) return registry;
  if (!guestIsObject(selection)) return guestConflict('invalid_guest', 'Select a guest or enter a name.');
  if (selection.guestId !== undefined) {
    if (!guestIsUUID(selection.guestId)) return guestConflict('invalid_guest', 'Select a guest with a valid UUID.');
    var guest = registry.byId[selection.guestId];
    if (!guest) return guestConflict('guest_missing', 'Refresh and select an existing guest.', { guestIds: [selection.guestId] });
    if (guest.status === 'promoted') {
      return guestConflict('guest_promoted', 'This guest is now a member. Review their member attendance.', {
        guestIds: [guest.guestId], memberName: guest.memberName
      });
    }
    return { ok: true, guest: guest, create: false };
  }
  if (!guestHasText(selection.displayName)) return guestConflict('invalid_guest', 'Enter a guest name.');
  var key = guestNameKey(selection.displayName);
  var matches = guests.filter(function (g) { return guestNameKey(g.displayName) === key; });
  if (matches.length && selection.confirmDistinct !== true) {
    return guestConflict('identity_ambiguous', 'Select an existing person or confirm this is a different person.', {
      guestIds: matches.map(function (g) { return g.guestId; })
    });
  }
  return { ok: true, create: true, displayName: selection.displayName.trim() };
}

/** Renaming changes the registry revision, never the UUID or historical records. */
function guestRenameGuest(guests, guestId, displayName, baseRevision) {
  var resolved = guestResolveGuestIdentity(guests, { guestId: guestId });
  if (!resolved.ok) return resolved;
  if (!guestHasText(displayName)) return guestConflict('invalid_guest', 'Enter a guest name.');
  if (resolved.guest.revision !== baseRevision) {
    return guestConflict('stale_guest_revision', 'The guest changed. Refresh and review this name correction.', { guestIds: [guestId] });
  }
  if (baseRevision === Number.MAX_SAFE_INTEGER) return guestConflict('invalid_guest', 'The guest revision cannot be increased.');
  return { ok: true, guest: Object.assign({}, resolved.guest, {
    displayName: displayName.trim(), revision: baseRevision + 1
  }) };
}

/** Identical replay records count once. Contradictory duplicate records need repair. */
function guestAttendanceSummary(guestId, records) {
  if (!guestIsUUID(guestId) || !Array.isArray(records)) return guestConflict('invalid_attendance', 'Guest history is invalid.');
  var seen = {};
  var result = { ok: true, confirmedRuns: 0, guestRuns: 0, transferredRuns: 0, runIdentities: [] };
  for (var i = 0; i < records.length; i++) {
    var record = records[i];
    var valid = guestValidateAttendance(record);
    if (!valid.ok) return valid;
    if (record.guestId !== guestId) continue;
    var key = guestRunKey(record);
    if (seen[key]) {
      if (seen[key].state !== record.state || seen[key].classification !== record.classification || seen[key].revision !== record.revision) {
        return guestConflict('duplicate_attendance_identity', 'Repair conflicting records for this guest and run.', { guestIds: [guestId], runId: record.runId });
      }
      continue;
    }
    seen[key] = record;
    if (record.state !== 'present') continue;
    result.confirmedRuns++;
    if (record.classification === 'guest') result.guestRuns++;
    else result.transferredRuns++;
    result.runIdentities.push(guestValidateRunIdentity(record).runIdentity);
  }
  return result;
}

function guestResolveRun(runs, identity) {
  var valid = guestValidateRunIdentity(identity);
  if (!valid.ok) return valid;
  if (!Array.isArray(runs)) return guestConflict('invalid_run', 'The run registry is invalid.');
  var key = guestRunKey(identity);
  var matches = runs.filter(function (run) { return guestValidateRunIdentity(run).ok && guestRunKey(run) === key; });
  if (matches.length === 0) return guestConflict('run_missing', 'This run is missing. Review its season and history.', { runId: identity.runId });
  if (matches.length > 1) return guestConflict('duplicate_run_identity', 'This run ID occurs more than once. Repair its metadata.', { runId: identity.runId });
  return { ok: true, run: matches[0] };
}

/** Guest count always equals unique active IDs plus the explicit unnamed remainder. */
function guestValidateAllocation(allocation, guests) {
  if (!guestIsObject(allocation) || !Array.isArray(allocation.namedGuestIds) ||
      !Number.isSafeInteger(allocation.unnamedGuests) || allocation.unnamedGuests < 0) {
    return guestConflict('invalid_allocation', 'Supply named guest IDs and a nonnegative whole unnamed count.');
  }
  var registry = guestRegistry(guests);
  if (!registry.ok) return registry;
  var ids = [];
  for (var i = 0; i < allocation.namedGuestIds.length; i++) {
    var id = allocation.namedGuestIds[i];
    if (!guestIsUUID(id)) return guestConflict('invalid_allocation', 'A named guest ID is invalid.');
    var identity = guestResolveGuestIdentity(guests, { guestId: id });
    if (!identity.ok) return identity;
    if (ids.indexOf(id) < 0) ids.push(id);
  }
  ids.sort();
  var plusOnes = ids.length + allocation.unnamedGuests;
  if (!Number.isSafeInteger(plusOnes)) return guestConflict('invalid_allocation', 'The guest count is too large.');
  return { ok: true, allocation: { namedGuestIds: ids, unnamedGuests: allocation.unnamedGuests }, plusOnes: plusOnes };
}

/** Merge may preserve anonymous uncertainty; name-assignment uses the separate helper. */
function guestMergeAllocation(current, proposed, guests) {
  var before = guestValidateAllocation(current, guests);
  if (!before.ok) return before;
  var after = guestValidateAllocation(proposed, guests);
  if (!after.ok) return after;
  return guestValidateAllocation({
    namedGuestIds: before.allocation.namedGuestIds.concat(after.allocation.namedGuestIds),
    unnamedGuests: Math.max(before.allocation.unnamedGuests, after.allocation.unnamedGuests)
  }, guests);
}

/** Assignment consumes one existing anonymous slot. Replays use operation receipts. */
function guestAssignUnnamedGuest(allocation, guestId, guests) {
  var before = guestValidateAllocation(allocation, guests);
  if (!before.ok) return before;
  if (before.allocation.namedGuestIds.indexOf(guestId) >= 0) {
    return guestConflict('guest_already_assigned', 'This guest already attends this run. Review the remaining unnamed guests.', { guestIds: [guestId] });
  }
  if (before.allocation.unnamedGuests < 1) return guestConflict('invalid_allocation', 'There is no unnamed guest slot to assign.');
  return guestValidateAllocation({ namedGuestIds: before.allocation.namedGuestIds.concat([guestId]),
    unnamedGuests: before.allocation.unnamedGuests - 1 }, guests);
}

/** Canonical JSON has sorted object keys, preserved arrays, and finite numbers. */
function guestCanonicalJSON(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Canonical JSON requires finite numbers.');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return '[' + value.map(guestCanonicalJSON).join(',') + ']';
  if (!guestIsObject(value)) throw new Error('Canonical JSON requires explicit JSON values.');
  return '{' + Object.keys(value).sort().map(function (key) {
    if (/secret|password|credential|authorization|apikey|token/i.test(key) && key !== 'previewToken') {
      throw new Error('Credentials must not enter canonical requests.');
    }
    return JSON.stringify(key) + ':' + guestCanonicalJSON(value[key]);
  }).join(',') + '}';
}

/** Reject unknown action fields so a receipt cannot retain accidental credentials. */
function guestCanonicalRequest(request) {
  if (!guestIsObject(request) || !guestOperationFields[request.action]) throw new Error('Unknown operation action.');
  var fields = ['apiVersion', 'operationId', 'action'].concat(guestOperationFields[request.action]);
  var canonical = {};
  Object.keys(request).forEach(function (key) {
    if (key === 'secret' || key === 'requestDigest') return;
    if (fields.indexOf(key) < 0) throw new Error('Unsupported operation field: ' + key);
    // Only history entries have nested objects. Refuse extra nested properties
    // instead of persisting an arbitrary caller object into the operation ledger.
    if (key === 'entries') {
      if (!Array.isArray(request[key])) throw new Error('History entries must be an array.');
      var entryFields = ['spreadsheetId', 'seasonSheetId', 'runId', 'expectedDate', 'expectedRun', 'assignment'];
      request[key].forEach(function (entry) {
        if (!guestIsObject(entry)) throw new Error('History entry must be an object.');
        Object.keys(entry).forEach(function (field) {
          if (entryFields.indexOf(field) < 0 || (entry[field] !== null && typeof entry[field] === 'object')) {
            throw new Error('Unsupported history entry field: ' + field);
          }
        });
      });
    } else if (['attendees', 'namedGuestIds', 'seasonSheetIds'].indexOf(key) >= 0) {
      if (!Array.isArray(request[key]) || request[key].some(function (value) { return value !== null && typeof value === 'object'; })) {
        throw new Error('Operation list must contain scalar values: ' + key);
      }
    } else if (request[key] !== null && typeof request[key] === 'object') {
      throw new Error('Operation field must be a scalar value: ' + key);
    }
    canonical[key] = request[key];
  });
  return guestCanonicalJSON(canonical);
}

function guestValidateOperationRequest(request) {
  if (!guestIsObject(request)) return guestConflict('invalid_operation', 'Supply an operation request.');
  if (request.apiVersion !== 2) return guestConflict('unsupported_api_version', 'Update the app before sending shared guest changes.');
  if (!guestIsUUID(request.operationId) || typeof request.requestDigest !== 'string' || !/^[0-9a-f]{64}$/.test(request.requestDigest)) {
    return guestConflict('invalid_operation', 'Supply a stable operation UUID and lowercase SHA-256 request digest.');
  }
  if (request.action === 'commitPromotion' && ['create', 'link'].indexOf(request.targetMode) < 0) {
    return guestConflict('invalid_operation', 'Choose whether to create a member or link an existing member.');
  }
  try {
    return { ok: true, canonicalRequest: guestCanonicalRequest(request) };
  } catch (error) {
    return guestConflict('invalid_operation', error.message);
  }
}

/** A completed/rejected/not-applied request is replayed, never dispatched again. */
function guestInspectOperation(operation, request) {
  var valid = guestValidateOperationRequest(request);
  if (!valid.ok) return valid;
  if (operation === null || operation === undefined) return { ok: true, disposition: 'new' };
  if (!guestIsObject(operation) || ['pending', 'completed', 'rejected', 'not_applied'].indexOf(operation.status) < 0) {
    return guestConflict('invalid_operation', 'The saved operation receipt is invalid.');
  }
  if (operation.operationId !== request.operationId || operation.requestDigest !== request.requestDigest || operation.canonicalRequest !== valid.canonicalRequest) {
    return guestConflict('operation_id_reused', 'This operation ID belongs to another request. Review the saved operation.');
  }
  return { ok: true, disposition: operation.status === 'pending' ? 'pending' : 'replay', operation: operation };
}

var GuestOps = {
  GUESTOPS_VERSION: GUESTOPS_VERSION, capabilities: guestCapabilities,
  validateGuest: guestValidateGuest, validateRunIdentity: guestValidateRunIdentity,
  validateAttendance: guestValidateAttendance, resolveGuestIdentity: guestResolveGuestIdentity,
  renameGuest: guestRenameGuest, attendanceSummary: guestAttendanceSummary,
  resolveRun: guestResolveRun, validateAllocation: guestValidateAllocation,
  mergeAllocation: guestMergeAllocation, assignUnnamedGuest: guestAssignUnnamedGuest,
  canonicalJSON: guestCanonicalJSON, canonicalRequest: guestCanonicalRequest,
  validateOperationRequest: guestValidateOperationRequest, inspectOperation: guestInspectOperation
};
if (typeof module !== 'undefined' && module.exports) module.exports = GuestOps;
