# Weekly Data Sync failures

The `Weekly Data Sync` workflow (`.github/workflows/weekly-data-sync.yml`) runs every Sunday at 17:17 Perth time.
Its `sync` job calls the Apps Script `exportAttendanceSnapshot` action and commits changed season CSVs.
Its `notify` job sends milestone emails, and it runs only after `sync` succeeds.
A failed sync changes no data and makes no commit.

## Read the failure

Open the failed run. The annotation titled **Attendance sync failed** holds the whole failure line, for example:

```text
Attendance snapshot unavailable (pending_operation): write 3f1c2a4b-5d6e-4f70-8a91-b2c3d4e5f607 awaits verification (phase dispatching). Phone writes are paused too. No data changed. Runbook: docs/operators/weekly-data-sync.md
```

The code in brackets selects the row below.
The script never prints a remote message, the secret, or a name.

## Codes and fixes

| Line contains | Cause | Fix |
|---|---|---|
| `(busy)` | Another request held the script lock for more than 20 s on all four attempts. | Rerun the sync. If it repeats, look for a stuck run under Apps Script **Executions**. |
| `(pending_operation)` … `phase dispatching` | A phone write was sent, and the server cannot verify it: its receipt is still pending, or its target cells changed after it landed. Phone writes are paused too. | The sync already ran the same check the owning phone runs, so opening the app or rerunning the sync does not clear this fence. Review the write as described in [manual sheet edits](manual-sheet-edits.md). Do not delete `FCTC_PENDING_OPERATION` by hand: no approved procedure clears an unverified write yet. |
| `(pending_operation)` … `phase preparing` | A write stopped while it saved its recovery journal. It was never sent, but the journal may be partial, so the server keeps the fence. | Same review as `dispatching`. |
| `(pending_operation)` … `phase none` | The fence property exists with no journal. | Same review as `dispatching`. |
| `(pending_operation)` … `phase reserved` | A write that was never sent. When the operations tab exists, the current server marks it `not_applied` and clears it. A setup interrupted before that tab exists keeps its fence on purpose. Otherwise the deployed script is out of date or its check failed. | For an interrupted setup, follow the status steps in [shared guest setup](shared-guest-setup.md). Otherwise check the deployed Apps Script version. Look for `could not be verified. Writes stay paused.` under Apps Script **Executions**. |
| `write unknown` or `phase unknown` | The server sent a value the script does not accept. | Check that the deployed Apps Script matches this repository. |
| `(bad_secret)` | The `FCTC_ATTENDANCE_SECRET` repository secret does not match the `SHARED_SECRET` Script Property. | Run `gh secret set FCTC_ATTENDANCE_SECRET --repo cpdis/fctc2025` and paste the Script Property value at the prompt. |
| `(snapshot_invalid)` | A supported season tab is missing or has no readable header row. | Check the season tabs listed in `ATTENDANCE_EXPORT_YEARS` (`apps-script/AttendanceExport.gs`) and `src/config/years.js`. |
| `(snapshot_too_large)` | The seasons exceed 250,000 cells or 1,200,000 characters. | Raise the limits in `apps-script/AttendanceExport.gs` and `scripts/sync-attendance-snapshot.js` together, after review. |
| `(shared_guests_disabled)` | The current export answers before this check, so the deployed script is out of date. | Deploy the current Apps Script. |
| `(service_error)` | The server returned an unexpected error code. | Look under Apps Script **Executions** for the failed run. |
| `returned an HTTP error` | A 4xx answer means a wrong `FCTC_ATTENDANCE_ENDPOINT` variable or deployment access. A 429 or 5xx answer was retried four times. | For 4xx, check the variable and that the web app deployment allows anonymous access. For 429 or 5xx, rerun later. |
| `did not return JSON` | The URL serves a sign-in page or a different deployment. | Check the deployment ID in `FCTC_ATTENDANCE_ENDPOINT`. |
| `request failed` or `was interrupted` | A network failure on all four attempts. | Rerun the sync. |
| `Set FCTC_ATTENDANCE_ENDPOINT`, `Use the HTTPS Apps Script /exec endpoint`, or `Set FCTC_ATTENDANCE_SECRET` | The repository variable or secret is missing or malformed. | Set the `FCTC_ATTENDANCE_ENDPOINT` variable or the secret in the repository settings. |
| `snapshot`, `season` or `revision` validation text | The response failed local validation. Nothing was written. | Rerun once. If it repeats, compare the deployed script with this repository. |
| `Snapshot replacement failed` | The runner could not replace the CSV files. No commit was made. | Rerun the sync. |

## How the server clears a pending write

Every authenticated request first checks a fence that another write left, under the script lock.
This includes the weekly sync and every phone refresh.

- A completed receipt whose target cells still match clears the fence.
- A write that was reserved but never sent, in a workbook that has its operations tab, gets a `not_applied` receipt, and the fence clears. Its phone then asks the organiser to review the run.
- Everything else stays fenced, as the shared guest design requires.

## Rerun after a fix

Send the milestone emails for the week, if delivery is enabled:

```bash
gh workflow run "Weekly Data Sync" --repo cpdis/fctc2025 --ref main -f notification_mode=send
```

Sync and list milestone candidates without email:

```bash
gh workflow run "Weekly Data Sync" --repo cpdis/fctc2025 --ref main -f notification_mode=preview
```

Do not use **Re-run failed jobs** on a scheduled run when you want the emails: a scheduled rerun skips milestone delivery by design.
