# Shared guest API v2 fixtures

`contract.json` uses synthetic names, workbook IDs, sheet IDs, and UUIDs.
It defines the shared contract for Apps Script and Swift `Codable` models.
It contains eleven distinct runs across two seasons, including two runs on one date.
No fixture authorises a production write or claims the server is deployed.

## Identity and allocation

| Object | Required fields |
|---|---|
| Guest | `guestId: String` (lowercase UUID), `displayName: String`, `status: "active" | "promoted"`, `memberName: String?`, `revision: Int` |
| Run identity | `spreadsheetId: String`, `seasonSheetId: Int`, `runId: String` (lowercase UUID) |
| Guest attendance | Run identity plus `guestId: String`, `state: "present" | "removed"`, `classification: "guest" | "transferred"`, `revision: Int` |
| Allocation | `namedGuestIds: [String]`, `unnamedGuests: Int` |
| Guest summary | Guest plus `confirmedRuns: Int`, `lastAttendance: LastAttendance?` |
| LastAttendance | Run identity plus `date: String`, `seasonYear: Int` |

Revisions are positive integers; sheet IDs and unnamed counts are nonnegative integers.
Encode an absent member mapping or last attendance as JSON `null`.
Active guests have no member mapping. Promoted guests retain the exact canonical member name.
The adapter trims names before storage; it never uses a name as a primary key.
The app must lowercase UUID strings before sending them.

Run row indices are 1-based coordinates. They can change without changing identity.
The server resolves metadata before comparing the date and run label validation fields.
Two run UUIDs on one date are two runs. One guest and one run form one logical attendance record.
Identical replay records count once. Contradictory duplicate records require repair.
Removed attendance remains stored but does not count. Transferred attendance retains its history
and member mapping, and must not contribute to the sheet's guest count.

The sheet's `plusOnes` equals distinct active `namedGuestIds.count + unnamedGuests`.
Merge unions named IDs and takes the maximum unnamed count.
Overwrite replaces the reviewed allocation only when its revision is current.
Assignment consumes one existing unnamed slot; adding attendance is a separate action.
Selecting a promoted guest returns `guest_promoted`, including its canonical `memberName`.
Even one matching display name requires selection or explicit `confirmDistinct: true`.

## State and history responses

`responses.getState` preserves the legacy `ok`, `roster`, `runs`, `seasonYear`,
`sheetRevision`, and `lifetimeTotals` keys. It adds:

- `apiVersion: 2` and `capabilities: { apiVersion: 2, sharedGuests: Bool,
  stableRunIdentity: Bool, guestHistory: Bool, guestPromotion: Bool, operationReceipts: Bool }`.
- `spreadsheetId: String`, `seasonSheetId: Int`, `guests: [GuestSummary]`.
- `guestRevision: String`, an opaque token for the guest registry and attendance.
- `pendingOperationId: String?`, present or `null` when there is no pending operation.
- Each run adds run identity, `namedGuestIds`, and `unnamedGuests` to the legacy fields.

`sheetRevision` must include applicable guest identities, allocations, and promotion mappings.
There is no separate per-run revision. Clients treat revision strings as opaque tokens.
The adapter advertises a capability only when its action is usable.

`getGuestHistory {guestId}` returns `{ok, guest: GuestSummary, guestRevision, attendance}`.
Each history entry includes the full attendance record plus `seasonYear`, `date`, `run`,
and current `rowIndex`. This identifies the exact season and run to reopen.
Removed/transferred classifications are explicit; the client must not infer them from a name.

`previewPromotion {guestId, memberName, targetMode}` returns `{ok, guestId, memberName, targetMode, confirmedRuns,
previewToken, seasons, changes}`. Each season has `seasonYear`, `seasonSheetId`, and `runs`.
Each change has run identity and display locators plus `plusOnesBefore`, `plusOnesAfter`,
`totalBefore`, `totalAfter`, `actualKmBefore`, and `actualKmAfter`.
The token covers all affected history, guest revisions, member context, target choice, and season data.
`targetMode: "create" | "link"` is an explicit organiser choice.
A matching member name must never silently change `create` into `link`.

`commitPromotion` supplies the same guest, member name, target choice, and preview token in a mutation envelope.
Its success contains `operationId`, `status: "completed"`, the promoted `guest`,
`memberName`, `confirmedRuns`, `sheetRevision`, and `guestRevision`.
The fixture's eleven guest runs become eleven member runs; no run headcount or distance changes.

## Mutations and operation receipts

Every v2 mutation includes `apiVersion: 2`, `operationId: String` (lowercase UUID),
`requestDigest: String` (64 lowercase SHA-256 hex characters), and `action: String`.
The normal authenticated transport adds the root `secret`; it never enters a receipt.
The payload fields are visible in `requests` and documented below.

| Action | Payload fields |
|---|---|
| `createGuest` | `guestId`, `displayName`, `confirmDistinct: Bool` |
| `renameGuest` | `guestId`, `displayName`, `baseGuestRevision: Int` |
| `submitAttendance` | Run identity, `rowIndex`, `expectedDate`, `expectedRun`, `attendees: [String]`, allocation, `actualKm: Double?`, `mode: "merge" | "overwrite"`, `baseRevision: String` |
| `importGuestHistory` | `guestId`, `baseGuestRevision`, `baseRevision`, `entries: [HistoryAssignment]` |
| `commitPromotion` | `guestId`, `memberName`, `targetMode: "create" | "link"`, `previewToken` |
| `addMember` | `name`, `baseRevision`, `seasonSheetId` (omit only for the active season) |
| `addRun` | `date`, `meet`, `run`, `approxKm`, `spreadsheetId`, `seasonSheetId`, `baseRevision` |
| `setupSharedGuests` | `spreadsheetId`, `seasonSheetIds: [Int]` |

`HistoryAssignment` has run identity, `expectedDate`, `expectedRun`, and
`assignment: "existing_unnamed_slot"`. Import consumes verified existing unnamed slots.
`previewGuestImport {guestId, entries}` returns `{ok, guestId, baseGuestRevision,
baseRevision, entries, changes, confirmedRuns}`. It resolves and deduplicates the
explicit run identities. Each change has the entry fields plus `alreadyAssigned`,
`unnamedBefore`, and `unnamedAfter`. The count is the currently confirmed count.
The preview rejects missing allocations and changed dates before any write.
The client passes the returned revisions and entries to `importGuestHistory`.
Import success adds `guestId`, `importedRuns`, `confirmedRuns`, and `guestRevision`
to the completed-operation envelope. It never changes the season attendance cells.
An already-present guest/run pair returns its existing record and consumes no second slot.
It must not create headcount or infer a historical identity from an aggregate count.
The create operation is persisted and confirmed before dependent attendance sends its provisional UUID.

`getOperationStatus {operationId}` returns `{ok, operation: OperationReceipt?}`.
`OperationReceipt` has `operationId`, `requestDigest`, `status`, and `response`.
The `response` is `null` while pending; otherwise it contains the original action's result.
Decode it as the matching response type or an explicit JSON-value enum in Swift.
Do not map a missing operation to a successful write.

| Status | Meaning and retry behaviour |
|---|---|
| `pending` | Reserved, outcome not verified. Keep a workbook-wide write fence. |
| `completed` | Verified committed; return the saved response. |
| `rejected` | Definitively rejected; return the saved conflict/error. |
| `not_applied` | Reconciled non-application; return that saved outcome for review. |

Never dispatch an existing operation UUID again, including `not_applied`.
A separately reviewed retry uses a new operation UUID.
Reusing a UUID with another digest or canonical request returns `operation_id_reused`.
Persisted operation rows additionally contain `canonicalRequest: String`,
`sourceRevisions: {String: String}`, `targetState: Object`, and
`receiptLocation: {sheetId: Int, rowIndex: Int}`. These are server recovery fields,
not operation-status response fields. The adapter must bound/chunk them below sheet cell limits.

## Digest encoding

`GuestOps.canonicalRequest` removes only root `secret` and `requestDigest`.
It keeps `apiVersion`, `action`, `operationId`, and explicitly supported action fields.
It rejects unsupported fields and arbitrary nested objects rather than storing them.
It recursively sorts object keys by UTF-16 code units, preserves array order,
uses compact JSON without whitespace, preserves Unicode text, and does not escape `/`.
Numbers use ECMAScript `JSON.stringify` finite-number encoding (`-0` becomes `0`).
Absent optional keys stay absent; explicit `null` stays `null`.
Do not use locale sorting or Unicode normalisation while making the digest.
Hash the resulting UTF-8 bytes with SHA-256. The server must recompute this digest.
Shape validation alone does not authenticate the client-supplied digest.

`canonicalCreateRequest` is an exact byte comparison fixture. Every mutation in `requests`
also contains a verified digest, including fractional kilometres and an accented rename.
Swift must test those fixtures before relying on `JSONEncoder` formatting options;
sorted keys alone do not prove matching numeric or escaping behaviour.

## Failure contract

Pure helpers return `{ok: false, conflict: {reason, message, ...details}}`.
The API adapter returns the existing `{ok: true, conflict: {reason, message, state?, ...details}}`
format for actionable conflicts. Malformed requests use the existing top-level error format.
`conflicts` contains wire examples for missing/duplicate identities, same-name ambiguity,
promoted guests, stale revisions, missing/duplicate runs, invalid allocation, conflicting
attendance, operation reuse, and pending verification. Attach current state when a checklist
review needs it. Do not return a success that silently changes an allocation.

Run the pure checks with `node --test apps-script/test/guestops.checks.js`.
The suite proves contract rules only. Sheet atomicity, formula behaviour, permissions,
metadata movement, and cross-device persistence need the integration units and copy-sheet checks.
