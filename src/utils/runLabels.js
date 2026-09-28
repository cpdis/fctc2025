/**
 * Run label rules.
 *
 * Organisers type the sheet's "Run" and "Meet" cells by hand, so one kind of
 * run shows up under several spellings across seasons. This module is the one
 * place those spellings become a normalized type, event and location, and the
 * one place a run gets its stable id:
 *
 *   raw "Run" cell         type            event
 *   ---------------------  --------------  ------------
 *   "Half- Invasion Day"   Half Marathon   Invasion Day   (2025 spacing)
 *   "Half - Xmas"          Half Marathon   Xmas           (2026 spacing)
 *   "Mara - Anzac Day"     Marathon        Anzac Day
 *   "10k - Xmas"           10K             Xmas
 *   "**Cruise"             Cruise          -              (sheet footnote)
 *   "N/hood Loop"          N'hood Loop     -
 *   "FILAMENT CUP 🏆"      Filament Cup    -
 *   "Good Fri Pancake"     Pancake Run     Good Friday
 *   "Pub Run", "Intervals" (as typed)      -              (pass through)
 *
 * A non-null event marks a holiday special. The Good Friday pancake run is one,
 * so it splits like the races: "Good Friday" + "Pancake Run".
 *
 * Every widget, filter and colour keys off this output (R7). The functions are
 * pure and dependency-free so plain Node (the weekly digest) can import them,
 * and the Swift `RunLabel` mirrors the same tables.
 */

// "Mara", "Half" or "10k", an optional-space hyphen, then the event name.
const RACE_LABEL = /^(mara|half|10k)\s*-\s*(.+)$/i

// Race distance prefix (lowercased) -> normalized type.
const RACE_TYPES = {
  mara: 'Marathon',
  half: 'Half Marathon',
  '10k': '10K',
}

// Whole labels that need a new name. Keys are lowercased so a change of case in
// the sheet ("Filament Cup 🏆") still lands on the same type.
const LABEL_ALIASES = {
  'n/hood loop': { type: "N'hood Loop", event: null },
  'filament cup 🏆': { type: 'Filament Cup', event: null },
  'good fri pancake': { type: 'Pancake Run', event: 'Good Friday' },
}

// Meet spellings that name the same place.
const LOCATION_ALIASES = {
  'Some-day': 'Someday',
}

// Type for a run row whose "Run" cell is blank.
const UNLABELLED_TYPE = 'Other'

/**
 * Drop sheet footnote markers ("**Cruise" on 5 Jan 2026) and outer whitespace.
 * The marker flags a note on the sheet; it is never part of the run's name.
 */
function stripFootnoteMarkers(label) {
  return (label ?? '').trim().replace(/^\*+|\*+$/g, '').trim()
}

/**
 * Parse a raw "Run" cell into its clean label, normalized type and event.
 *
 * @param {string | undefined} raw - the sheet's "Run" cell, as typed
 * @returns {{ label: string, type: string, event: string | null }}
 *   `label` is the cell without footnote markers (what Wrapped matches on),
 *   `type` is the normalized run type, `event` the holiday or race name, if any.
 */
export function parseRunLabel(raw) {
  const label = stripFootnoteMarkers(raw)

  const race = label.match(RACE_LABEL)
  if (race) {
    return { label, type: RACE_TYPES[race[1].toLowerCase()], event: race[2].trim() }
  }

  const alias = LABEL_ALIASES[label.toLowerCase()]
  if (alias) return { label, ...alias }

  return { label, type: label || UNLABELLED_TYPE, event: null }
}

/**
 * Normalize a raw "Meet" cell into a location name. Known aliases map to one
 * spelling; anything else passes through trimmed.
 *
 * @param {string | undefined} raw - the sheet's "Meet" cell, as typed
 * @returns {string}
 */
export function normalizeLocation(raw) {
  const location = (raw ?? '').trim()
  return LOCATION_ALIASES[location] ?? location
}

/**
 * Lowercase ASCII slug: accents folded, every other run of non-alphanumerics
 * (spaces, "/", "*", emoji) collapsed to one hyphen.
 */
function slugify(text) {
  return text
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

/**
 * Local YYYY-MM-DD for a Date (no UTC shift). The one date-key helper for run
 * ids, club days and dashboard series.
 *
 * @param {Date} date
 * @returns {string}
 */
export function isoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

/** Local YYYY-MM for a Date: the month key the run log and month axis share. */
export function monthKey(date) {
  return isoDate(date).slice(0, 7)
}

/**
 * Build a stable run id, `YYYY-MM-DD-<slug of the run label>` (KTD4), for
 * example `2026-09-25-river-loop`. The date carries the year, so ids stay
 * unique when seasons merge into All time.
 *
 * No season has two runs with the same date and label today. If one ever does,
 * the later row gets `-2`, then `-3`, in sheet order.
 *
 * @param {Date} date - the run's local-midnight date
 * @param {string} label - the run label (footnote markers slug away anyway)
 * @param {Set<string>} taken - ids already given out in this season; the new
 *   id is added to it
 * @returns {string}
 */
export function runId(date, label, taken = new Set()) {
  const base = `${isoDate(date)}-${slugify(label ?? '') || 'run'}`
  let id = base
  for (let n = 2; taken.has(id); n++) id = `${base}-${n}`
  taken.add(id)
  return id
}
