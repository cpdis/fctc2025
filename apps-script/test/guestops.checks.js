/** Shared guest contract checks. This suite stays independent of sheet I/O. */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const GuestOps = require('../GuestOps.js');
const fixture = require('../../fixtures/attendance/guests/contract.json');
const { guests, runs, attendance } = fixture;
const rene = guests[0];
const allocation = { namedGuestIds: [], unnamedGuests: 1 };

function reason(result, expected) {
  assert.equal(result.ok, false);
  assert.equal(result.conflict.reason, expected);
  assert.ok(result.conflict.message.length > 0);
}

test.describe('GuestOps pure shared identity contract', () => {
  test.it('also exposes the same namespace without a CommonJS environment', () => {
    const context = {};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../GuestOps.js'), 'utf8'), context);
    assert.equal(context.GuestOps.capabilities.apiVersion, 2);
    assert.equal(typeof context.GuestOps.validateAllocation, 'function');
  });

  test.it('requires UUID identities, a valid state, and monotonic integer revisions', () => {
    assert.equal(GuestOps.validateGuest(rene).ok, true);
    reason(GuestOps.validateGuest({ ...rene, guestId: 'Rene' }), 'invalid_guest');
    reason(GuestOps.validateGuest({ ...rene, revision: 0 }), 'invalid_guest');
    reason(GuestOps.validateGuest({ ...rene, status: 'promoted' }), 'invalid_guest');
    reason(GuestOps.validateGuest({ ...rene, memberName: 'Rene' }), 'invalid_guest');
  });

  test.it('never resolves a name to an identity, including a single plausible match', () => {
    reason(GuestOps.resolveGuestIdentity([rene], { displayName: 'Réne' }), 'identity_ambiguous');
    const result = GuestOps.resolveGuestIdentity(guests, { displayName: 'rene' });
    reason(result, 'identity_ambiguous');
    assert.deepEqual(result.conflict.guestIds, guests.slice(0, 2).map(g => g.guestId));
    assert.equal(GuestOps.resolveGuestIdentity(guests, { guestId: guests[1].guestId }).guest.guestId, guests[1].guestId);
    assert.equal(GuestOps.resolveGuestIdentity(guests, { displayName: 'Rene', confirmDistinct: true }).create, true);
    assert.equal(GuestOps.resolveGuestIdentity(guests, { displayName: 'New visitor' }).create, true);
  });

  test.it('preserves non-Latin names during comparison and rejects blank labels', () => {
    assert.equal(GuestOps.resolveGuestIdentity(guests, { displayName: '李' }).create, true);
    reason(GuestOps.resolveGuestIdentity(guests, { displayName: '  ' }), 'invalid_guest');
  });

  test.it('rejects missing, duplicate, and promoted identities with useful details', () => {
    reason(GuestOps.resolveGuestIdentity(guests, { guestId: '__proto__' }), 'invalid_guest');
    reason(GuestOps.resolveGuestIdentity(guests, { guestId: 'ffffffff-ffff-4fff-8fff-ffffffffffff' }), 'guest_missing');
    reason(GuestOps.resolveGuestIdentity([...guests, rene], { guestId: rene.guestId }), 'duplicate_guest_identity');
    const promoted = GuestOps.resolveGuestIdentity(guests, { guestId: guests[2].guestId });
    reason(promoted, 'guest_promoted');
    assert.equal(promoted.conflict.memberName, guests[2].memberName);
  });

  test.it('renames the label without changing identity or history and rejects stale edits', () => {
    const changed = GuestOps.renameGuest(guests, rene.guestId, 'René', rene.revision);
    assert.equal(changed.guest.guestId, rene.guestId);
    assert.equal(changed.guest.displayName, 'René');
    assert.equal(changed.guest.revision, rene.revision + 1);
    assert.equal(rene.displayName, 'Rene');
    assert.equal(GuestOps.attendanceSummary(rene.guestId, attendance).confirmedRuns, 11);
    reason(GuestOps.renameGuest(guests, rene.guestId, 'René', 0), 'stale_guest_revision');
  });

  test.it('counts distinct run IDs across seasons, including two runs on the same date', () => {
    const result = GuestOps.attendanceSummary(rene.guestId, [...attendance, attendance[0]]);
    assert.equal(result.confirmedRuns, 11);
    assert.equal(result.guestRuns, 11);
    assert.equal(runs[0].date, runs[1].date);
    assert.notEqual(runs[0].runId, runs[1].runId);
    assert.deepEqual(result.runIdentities.map(r => r.runId).sort(), runs.map(r => r.runId).sort());
  });

  test.it('excludes removed attendance and retains transferred history without guest allocation', () => {
    const records = [
      { ...attendance[0], state: 'removed' },
      { ...attendance[1], classification: 'transferred' },
      attendance[2],
    ];
    const result = GuestOps.attendanceSummary(rene.guestId, records);
    assert.equal(result.confirmedRuns, 2);
    assert.equal(result.guestRuns, 1);
    assert.equal(result.transferredRuns, 1);
    reason(GuestOps.attendanceSummary(rene.guestId, [attendance[0], { ...attendance[0], state: 'removed' }]), 'duplicate_attendance_identity');
    reason(GuestOps.validateAttendance({ ...attendance[0], classification: 'unknown' }), 'invalid_attendance');
  });

  test.it('resolves stable identity after row movement and rejects missing/duplicate metadata', () => {
    const moved = { ...runs[0], rowIndex: 88 };
    assert.equal(GuestOps.resolveRun([moved], runs[0]).run.rowIndex, 88);
    reason(GuestOps.resolveRun([], runs[0]), 'run_missing');
    reason(GuestOps.resolveRun([moved, moved], runs[0]), 'duplicate_run_identity');
    reason(GuestOps.resolveRun(runs, { ...runs[0], seasonSheetId: 12345 }), 'run_missing');
    reason(GuestOps.validateRunIdentity({ ...runs[0], seasonSheetId: -1 }), 'invalid_run');
  });

  test.it('deduplicates named attendance and requires an explicit nonnegative unnamed count', () => {
    const result = GuestOps.validateAllocation({ namedGuestIds: [rene.guestId, rene.guestId], unnamedGuests: 2 }, guests);
    assert.deepEqual(result.allocation, { namedGuestIds: [rene.guestId], unnamedGuests: 2 });
    assert.equal(result.plusOnes, 3);
    for (const unnamedGuests of [undefined, null, -1, 1.5, '1']) {
      reason(GuestOps.validateAllocation({ namedGuestIds: [], unnamedGuests }, guests), 'invalid_allocation');
    }
    reason(GuestOps.validateAllocation({ namedGuestIds: [guests[2].guestId], unnamedGuests: 0 }, guests), 'guest_promoted');
  });

  test.it('merges named identities and takes the maximum unnamed remainder', () => {
    const result = GuestOps.mergeAllocation(
      { namedGuestIds: [rene.guestId], unnamedGuests: 1 },
      { namedGuestIds: [rene.guestId, guests[1].guestId], unnamedGuests: 2 }, guests);
    assert.deepEqual(result.allocation.namedGuestIds, [rene.guestId, guests[1].guestId]);
    assert.equal(result.allocation.unnamedGuests, 2);
    assert.equal(result.plusOnes, 4);
  });

  test.it('assigns a name to an existing unnamed slot without adding a headcount', () => {
    const result = GuestOps.assignUnnamedGuest(allocation, rene.guestId, guests);
    assert.deepEqual(result.allocation, { namedGuestIds: [rene.guestId], unnamedGuests: 0 });
    assert.equal(result.plusOnes, 1);
    assert.deepEqual(allocation, { namedGuestIds: [], unnamedGuests: 1 });
    reason(GuestOps.assignUnnamedGuest(result.allocation, guests[1].guestId, guests), 'invalid_allocation');
    reason(GuestOps.assignUnnamedGuest({ namedGuestIds: [rene.guestId], unnamedGuests: 1 }, rene.guestId, guests), 'guest_already_assigned');
  });

  test.it('canonicalizes only public request fields with stable keys and no credentials', () => {
    const request = fixture.requests.createGuest;
    assert.equal(GuestOps.canonicalRequest({ ...request, secret: 'never store this' }), fixture.canonicalCreateRequest);
    assert.equal(GuestOps.canonicalJSON({ b: { z: 1, a: 'René' }, a: [2, 1] }), '{"a":[2,1],"b":{"a":"René","z":1}}');
    assert.throws(() => GuestOps.canonicalJSON({ nested: { secret: 'nested credentials' } }), /credential/i);
    assert.throws(() => GuestOps.canonicalJSON({ bad: Infinity }), /finite/i);
    assert.throws(() => GuestOps.canonicalRequest({ ...request, privateToken: 'never save this' }), /Unsupported/);
    assert.throws(() => GuestOps.canonicalRequest({ ...request, displayName: { privateData: 'never save this' } }), /scalar/);
    assert.throws(() => GuestOps.canonicalRequest({ ...fixture.requests.importGuestHistory, entries: [{ ...fixture.requests.importGuestHistory.entries[0], privateData: 'never save this' }] }), /Unsupported/);
  });

  test.it('all mutation fixtures have correct SHA-256 digests of the exact UTF-8 request', () => {
    for (const request of Object.values(fixture.requests).filter(r => r.operationId && r.requestDigest)) {
      assert.equal(GuestOps.validateOperationRequest(request).ok, true, request.action);
      const digest = crypto.createHash('sha256').update(GuestOps.canonicalRequest(request), 'utf8').digest('hex');
      assert.equal(request.requestDigest, digest, request.action);
    }
  });

  test.it('validates operation envelopes and detects different requests under one UUID', () => {
    const request = fixture.requests.createGuest;
    assert.equal(GuestOps.validateOperationRequest(request).ok, true);
    reason(GuestOps.validateOperationRequest({ ...request, operationId: 'request-1' }), 'invalid_operation');
    reason(GuestOps.validateOperationRequest({ ...request, requestDigest: 'abc' }), 'invalid_operation');
    reason(GuestOps.validateOperationRequest({ ...request, apiVersion: 1 }), 'unsupported_api_version');
    assert.equal(GuestOps.inspectOperation(null, request).disposition, 'new');
    for (const status of ['pending', 'completed', 'rejected', 'not_applied']) {
      const stored = { ...fixture.operation, status };
      const result = GuestOps.inspectOperation(stored, request);
      assert.equal(result.disposition, status === 'pending' ? 'pending' : 'replay');
      assert.equal(result.operation.status, status);
    }
    reason(GuestOps.inspectOperation(fixture.operation, { ...request, displayName: 'Changed' }), 'operation_id_reused');
    reason(GuestOps.inspectOperation({ ...fixture.operation, status: 'mystery' }, request), 'invalid_operation');
  });

  test.it('requires an explicit create-or-link member choice when committing promotion', () => {
    const request = fixture.requests.commitPromotion;
    reason(GuestOps.validateOperationRequest({ ...request, targetMode: undefined }), 'invalid_operation');
    reason(GuestOps.validateOperationRequest({ ...request, targetMode: 'auto' }), 'invalid_operation');
    assert.equal(GuestOps.validateOperationRequest({ ...request, targetMode: 'create' }).ok, true);
    assert.equal(GuestOps.validateOperationRequest({ ...request, targetMode: 'link' }).ok, true);
    assert.equal(fixture.requests.previewPromotion.targetMode, 'create');
  });

  test.it('binds a new member operation to its explicitly selected season', () => {
    const request = { ...fixture.requests.createGuest, action: 'addMember', name: 'Rene',
      baseRevision: 'historical-revision', seasonSheetId: 25 };
    delete request.guestId;
    delete request.displayName;
    delete request.confirmDistinct;
    const result = GuestOps.validateOperationRequest(request);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(JSON.parse(result.canonicalRequest).seasonSheetId, 25);
    assert.notEqual(result.canonicalRequest, GuestOps.canonicalRequest({ ...request, seasonSheetId: 26 }));
  });

  test.it('fixtures retain legacy state fields and define parsable new action responses', () => {
    const state = fixture.responses.getState;
    for (const key of ['ok', 'roster', 'runs', 'seasonYear', 'sheetRevision', 'lifetimeTotals', 'apiVersion', 'capabilities', 'spreadsheetId', 'seasonSheetId', 'guests', 'guestRevision']) {
      assert.ok(Object.hasOwn(state, key), key);
    }
    for (const name of ['getGuestHistory', 'previewPromotion', 'commitPromotion', 'getOperationStatus']) {
      assert.equal(fixture.responses[name].ok, true, name);
      assert.ok(fixture.requests[name], name);
    }
    assert.equal(fixture.responses.previewPromotion.confirmedRuns, 11);
    assert.equal(fixture.responses.commitPromotion.confirmedRuns, 11);
    assert.equal(fixture.responses.getGuestHistory.attendance.length, 11);
  });
});
