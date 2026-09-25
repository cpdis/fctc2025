# Manual sheet edits and shared guests

Member columns are located from the current `Actual kms` and `+1's` headers.
Adding or removing member columns does not itself shift app writes onto another person.
Refresh the app after an edit. A pending save that names a removed member needs review.
Deleting a member column also removes its visible attendance; retain the history you need.

## Promote a guest through the app

Use the shared guest's promotion flow to create a member or link an existing member.
It updates the member marks, guest totals and hidden guest records together.
Review the person and their history before confirming the promotion.

Do not move a shared guest into a member column and clear `+1's` manually.
The hidden record still counts that person as a guest. One inconsistent run blocks
shared reads across both seasons. Do not restore `+1's` merely to clear the error:
that would count the same person twice when their member cell is already marked.
Do not infer a promotion from matching names. Different people can share a name.

The server keeps the `invalid_allocation` conflict code. For this mismatch, its
message names the season, date, run, row, sheet guest total and saved named guests.
It never changes attendance during a read or silently drops a guest record.

## Repair an already completed manual conversion

This is an operator repair. Preserve the phone app and its outbox records.

1. Capture a fresh private workbook backup and the deployed script source.
2. Confirm the selected guest and member are the same person.
3. Find every present guest attendance by workbook, season and stable run ID.
4. Confirm each member mark already exists and the sheet guest count was reduced.
5. Bind the repair to the exact source records, revisions, member spelling and run metadata.
6. Require no pending operation and reject any changed precondition.
7. Test the proposed repair against the captured workbook before applying it.
8. Use the script lock, durable operation journal and one atomic Sheets batch.
9. Set the guest status to `promoted`, set the exact `memberName`, and increase its revision.
10. Set each reviewed attendance classification to `transferred` and increase its revision.
11. Retain attendance state `present`, guest IDs, run IDs and every original operation receipt.
12. Record a new repair receipt. If delivery is uncertain, check that receipt; never repeat the batch.
13. Compare visible cells, formulas, notes and run metadata against the backup.
14. Verify both seasons load, the guest history remains, and the pending-operation fence is clear.
15. Refresh each phone. Review any queued change that still lists the promoted person as a guest.

The repair must not edit attendance marks, distances, guest totals, formulas or member headers.
If those conditions do not hold, stop and review the actual attendance first.

A lost response can leave a `pending` receipt after dispatch. Inspect its exact
targets and keep the fence; do not clear it or issue another operation. If receipt
verification returns `completed`, check the targets before reporting success. A
verified `not_applied` result needs a newly reviewed request with a new operation ID.
Never reuse an ID with a terminal receipt for a different request.

## 25 September 2026 incident

The 23 September Intervals run was recorded through the app with René as a named guest.
The sheet was later edited to mark René as a member and clear that run's `+1's` cell.
The guest registry and guest attendance record still held the original guest classification.
The server calculated an unnamed remainder of `0 - 1` and rejected both season reads.
The original message incorrectly described a bad request from the phone.

The prepared repair changes only the two hidden records and adds its operation receipt.
René's existing member history and the run's headcount of eleven stay intact.
The local snapshot check verifies both seasons, repeat safety and fourteen refusal conditions.
The server regression tests cover the diagnostic and the existing stale-phone review flow.
Live repair and deployment require Colin's production approval.
