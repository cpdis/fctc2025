#!/usr/bin/env bash
#
# fetch-sheet.sh — Fetch + validate the current season's published Google Sheet CSV.
#
# Used by .github/workflows/weekly-data-sync.yml, but written to be runnable
# (and testable) standalone. It does NOT commit or push — it only produces a
# validated CSV at the destination path. The caller decides whether anything
# changed and whether to commit.
#
# Why a script instead of inline YAML: the validation logic (HTML-error
# detection, size/line floors) is fiddly enough that having it in a real shell
# file means we can `bash -n` it and feed it junk inputs locally to prove the
# guards reject them, without ever touching the live sheet.
#
# Usage:
#   scripts/fetch-sheet.sh <CSV_URL> <DEST_PATH>
#
# Exits non-zero (loudly) if the fetch fails or the response fails validation,
# so a scheduled run NEVER overwrites good data with an HTML login page, an
# empty body, or a truncated blob.

set -euo pipefail

# --- Validation thresholds -------------------------------------------------
# The real CSVs are ~10-14 KB and 100-170 lines (2025.csv: 118 lines / 10.7 KB,
# 2026.csv: 173 lines / 14.5 KB at time of writing). A healthy export should be
# comfortably above these floors; anything below is almost certainly an error
# page, a permissions wall, or a truncated download, not real attendance data.
MIN_BYTES=500   # a few hundred bytes; well under the real ~10 KB, well over an error page
MIN_LINES=10    # the header block alone is more than this; a real season has dozens of rows

usage() {
  echo "usage: $0 <CSV_URL> <DEST_PATH>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

CSV_URL="$1"
DEST_PATH="$2"

if [ -z "$CSV_URL" ]; then
  echo "ERROR: CSV_URL is empty. Set SHEET_GID in the workflow (see its header comment)." >&2
  exit 1
fi

# Refuse to run with the unconfigured gid placeholder — fail loud rather than
# fetch a half-formed URL and risk pulling the wrong tab or an error page.
case "$CSV_URL" in
  *gid=REPLACE_ME*)
    echo "ERROR: SHEET_GID is still the REPLACE_ME placeholder. Set the current-season tab's gid in the workflow (see its header comment)." >&2
    exit 1
    ;;
esac

# Fetch into a temp file so a failed/garbage download can never clobber the
# real CSV at DEST_PATH. --fail makes curl return non-zero on HTTP >= 400
# (e.g. a private sheet returning 401/403), --location follows Google's
# redirects, --show-error surfaces the reason even with --silent.
TMP_FILE="$(mktemp)"
# shellcheck disable=SC2064  # expand TMP_FILE now, intentional
trap "rm -f '$TMP_FILE'" EXIT

echo "Fetching: $CSV_URL"
if ! curl --fail --location --silent --show-error "$CSV_URL" --output "$TMP_FILE"; then
  echo "ERROR: curl failed to fetch the sheet. Is the sheet shared 'Anyone with the link (Viewer)' or Published-to-web, and is the gid correct?" >&2
  exit 1
fi

# --- Validate the response before we trust it ------------------------------

# Guard 1: non-empty.
if [ ! -s "$TMP_FILE" ]; then
  echo "ERROR: fetched response is empty." >&2
  exit 1
fi

# Guard 2: not an HTML error/login page. Google serves an HTML page (not a CSV)
# when a sheet is unshared or the gid is wrong; those start with '<' and/or
# contain '<html'. A real CSV starts with cell text, never a tag.
FIRST_CHAR="$(head -c 1 "$TMP_FILE")"
if [ "$FIRST_CHAR" = "<" ]; then
  echo "ERROR: response begins with '<' — looks like an HTML page, not a CSV (sheet likely not link-viewable, or wrong gid)." >&2
  exit 1
fi
if grep -qi "<html" "$TMP_FILE"; then
  echo "ERROR: response contains '<html' — looks like an HTML error/login page, not a CSV." >&2
  exit 1
fi

# Guard 3: plausibility — size and line count floors.
BYTES="$(wc -c < "$TMP_FILE" | tr -d '[:space:]')"
LINES="$(wc -l < "$TMP_FILE" | tr -d '[:space:]')"
if [ "$BYTES" -lt "$MIN_BYTES" ]; then
  echo "ERROR: response is only ${BYTES} bytes (< ${MIN_BYTES}). Implausibly small for a season CSV — refusing to adopt it." >&2
  exit 1
fi
if [ "$LINES" -lt "$MIN_LINES" ]; then
  echo "ERROR: response has only ${LINES} lines (< ${MIN_LINES}). Implausibly short for a season CSV — refusing to adopt it." >&2
  exit 1
fi

# Passed every guard — adopt it. mkdir -p so a fresh checkout / new year works.
mkdir -p "$(dirname "$DEST_PATH")"
mv "$TMP_FILE" "$DEST_PATH"
trap - EXIT  # TMP_FILE was moved, nothing to clean up
echo "OK: validated CSV (${BYTES} bytes, ${LINES} lines) written to ${DEST_PATH}"
