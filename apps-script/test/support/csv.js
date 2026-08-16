/**
 * A minimal RFC-4180 CSV reader for the season fixtures (U2, test-only).
 *
 * The repo already depends on papaparse for the dashboard, but the Apps Script
 * package is deliberately dependency-free (conventions: "Node test tooling uses only
 * `node:test` + built-ins"), and `split(',')` is not an option: the Date column is
 * quoted precisely because it contains a comma — `"Fri, 2-Jan"`.
 *
 * Handles: quoted fields, commas and newlines inside quotes, doubled quotes (`""`)
 * as an escaped quote, and CRLF. Everything comes back as strings, which is exactly
 * what a text-formatted sheet gives `Range.getValues()`.
 */

'use strict';

/**
 * Parse CSV text into a 0-based array-of-arrays (a `grid`, in SheetOps terms).
 *
 * @param {string} text Raw CSV.
 * @return {!Array<!Array<string>>} Rows of string cells.
 */
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"'; // escaped quote
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else if (ch === '\r') {
      // CRLF: the \n on the next iteration ends the row.
    } else {
      field += ch;
    }
  }

  // A file that does not end in a newline still has one last row to flush.
  if (field !== '' || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

module.exports = { parseCsv };
