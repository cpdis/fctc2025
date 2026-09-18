# Shared guest setup operator procedure

Use this procedure first on a private workbook copy with its own bound script and
deployment. Production deployment, sharing changes, setup, and enablement each need
the separately authorised release window in the [release runbook](../plans/packets/U8-release-runbook.md).
This document and local tests do not grant production permission.

The helper uses the production `GuestOps.canonicalRequest` implementation. It saves
the UUID, canonical bytes, digest, endpoint, workbook ID, and season IDs before use.
It creates a separate durable dispatch marker before the setup POST. A later `submit`
call becomes a status read when that marker exists, even after a crash or absent receipt.

## Prepare the exact request

Use Node 22 or later and run commands from the repository root in Bash.
Replace the example values with IDs copied from the private target workbook and deployment.
Copy the workbook ID between `/d/` and `/edit` in its URL. Copy each season's numeric
sheet ID from its `gid`. Do not use a year or tab position as a sheet ID.
Include every supported season, including seasons already registered during a later
new-season setup. Compare these IDs with the owner and the bound script's parent.

```bash
umask 077
mkdir -p "$HOME/.local/share/fctc-setup/copy-2026"
chmod 700 "$HOME/.local/share/fctc-setup/copy-2026"
setup_file="$HOME/.local/share/fctc-setup/copy-2026/request.json"
setup_endpoint='https://script.google.com/macros/s/EXACT_EXISTING_DEPLOYMENT_ID/exec'
setup_workbook='EXACT_WORKBOOK_ID'
setup_seasons='EXACT_2025_GID,EXACT_2026_GID'

node scripts/setup-shared-guests.js prepare \
  --file "$setup_file" --endpoint "$setup_endpoint" \
  --spreadsheet "$setup_workbook" --seasons "$setup_seasons"
```

The parent directory must have mode `0700`. The helper creates files with mode `0600`.
Use an absolute path without symlink components. Keep the directory outside the repo
and cloud sharing. `prepare` refuses existing files and orphaned dispatch markers.
Review its secret-free output and private file. Confirm the endpoint, workbook, and
sorted season IDs. Keep the UUID and digest with the private release notes.

## Verify the deployed server before cutover

Deploy the reviewed v2 server with the existing deployment ID, as the runbook requires.
Set `SHARED_GUESTS_ENABLED=false` and `SHARED_GUESTS_SETUP_ALLOWED=false`.
Load the secret through a silent prompt. Never put its value in shell arguments,
history, a request file, screenshots, or logs. Disable shell tracing before the prompt.

```bash
set +x
read -r -s -p 'Shared secret: ' FCTC_SETUP_SECRET
printf '\n'
export FCTC_SETUP_SECRET

node scripts/setup-shared-guests.js read \
  --file "$setup_file" --endpoint "$setup_endpoint" \
  --spreadsheet "$setup_workbook" --seasons "$setup_seasons"
```

Require `status: "read_verified"`, the exact workbook and season IDs, both supported
years, and `sharedGuestsEnabled: false`. The command verifies authenticated v2 state
and the snapshot's content digest. It rejects missing seasons, wrong workbook IDs,
active shared writes, and pending operations. It prints no names, cells, or secrets.
The snapshot identifies the bound workbook because disabled v2 state omits that ID.
Now complete the workflow snapshot gate before restricting workbook access.

## Submit once and verify the receipt

Keep the edit-free window. Enable `SHARED_GUESTS_SETUP_ALLOWED=true` in the bound script.
Keep `SHARED_GUESTS_ENABLED=false`. Reuse the exact request and binding arguments.

```bash
node scripts/setup-shared-guests.js submit \
  --file "$setup_file" --endpoint "$setup_endpoint" \
  --spreadsheet "$setup_workbook" --seasons "$setup_seasons"
```

Success requires a separate authenticated `getOperationStatus` response after dispatch.
The helper verifies this receipt before printing `status: "completed"`:

```json
{
  "ok": true,
  "operation": {
    "operationId": "SAVED_OPERATION_UUID",
    "requestDigest": "SAVED_LOWERCASE_SHA256_DIGEST",
    "status": "completed",
    "response": {
      "ok": true,
      "operationId": "SAVED_OPERATION_UUID",
      "status": "completed",
      "spreadsheetId": "EXACT_WORKBOOK_ID",
      "seasonSheetIds": [25, 26],
      "sharedGuestsEnabled": false
    }
  }
}
```

The numbers `25` and `26` above are synthetic IDs. Require the exact sorted sheet IDs
from your saved request. Do not accept a completed response for another UUID or digest.
Do not enable shared writes from an unverified mutation response alone.

Compare season values, formulas, notes, and unique run metadata with the pre-setup copy.
Run `apps-script/test/smoke.md` and `apps-script/test/verify-sync-fidelity.md` on the copy.
Then disable setup. Shared enablement remains a later authorised release step.
Complete candidate reconciliation on both phones before promotion, as the runbook requires.

## Recover without replay

After a timeout, rejected authentication, unexpected response, process exit, or restart,
keep both `request.json` and `request.json.dispatch`. Load the same endpoint, workbook,
and season variables again. Load the secret through the same silent prompt, then run:

```bash
node scripts/setup-shared-guests.js status \
  --file "$setup_file" --endpoint "$setup_endpoint" \
  --spreadsheet "$setup_workbook" --seasons "$setup_seasons"

unset FCTC_SETUP_SECRET
```

| Result | Required action |
| --- | --- |
| `completed` | Compare the verified receipt and preservation checks before enablement. |
| `pending` or `missing` | Preserve the workbook fence and journal. Continue status reads or stop for operator comparison. |
| `not_applied` or `rejected` | Review the terminal receipt and workbook with the owner. The helper never creates a replacement request. |
| `bad_secret` | Correct the environment secret. Continue with `status`; do not reset the request. |
| `uncertain`, `receipt_binding`, or `binding` | Stop. Preserve both private files and server recovery evidence. |

An absent receipt does not prove non-delivery. Never delete a marker, edit a saved
request, clear server properties, or generate another UUID to bypass this rule.
Even a crash before delivery leaves the helper in status-only mode. A fresh request
requires separate operator proof of non-application and an approved recovery procedure.
Retain the original evidence. A setup interruption may retain a bootstrap fence even
with a `not_applied` receipt; repair it through the server recovery procedure.

The helper emits fixed error codes and selected identity fields only. It never prints
raw service errors. It follows only Google's ContentService redirect using a GET
without the request body. It does not automatically repeat a structural POST.

## Local verification

```bash
npx vitest run scripts/setup-shared-guests.test.js
node --test apps-script/test/guest-api.checks.js apps-script/test/guestops.checks.js
```

These checks use synthetic data and the production router inside a fake Sheets runtime.
They prove canonical bytes, durable dispatch evidence, receipt binding, recovery, and
secret-safe errors. Google consent, real formula recalculation, and device history
reconciliation still require the private-copy and physical-phone release checks.
