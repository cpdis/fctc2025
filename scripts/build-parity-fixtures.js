#!/usr/bin/env node
/**
 * Golden parity fixtures (KTD3, R28).
 *
 * Turns the dated sheet snapshot into one JSON contract per season, using the
 * web's own parser and club-day rules, so the web and the iOS app are checked
 * against the same numbers:
 *
 *   fixtures/attendance/2026-09-27/2026.csv
 *        | parseRunData                      (web: runs, member totals)
 *        | buildClubDays / memberClubDays    (web: club days, streaks)
 *        | milestoneShortlist                (web: milestones)
 *        v
 *   fixtures/attendance/parity/2026.json  { season, clubWeekdays, runs, expected }
 *        ^                        ^
 *        | Vitest: rebuild in     | Swift kit tests: parse each raw label with
 *        | memory, fail on drift  | RunLabel, recompute `expected` from `runs`
 *
 * Output order is fixed (runs by date then sheet order, names in plain string
 * order) and the JSON is 2-space with a trailing newline, so a rule change
 * shows up as a small, readable diff.
 *
 * Run: node scripts/build-parity-fixtures.js
 */
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { clubWeekdays } from '../src/config/years.js'
import { buildClubDays, memberClubDays, milestoneShortlist } from '../src/utils/clubDays.js'
import { parseRunData } from '../src/utils/dataParser.js'
import { isoDate } from '../src/utils/runLabels.js'

const ROOT = resolve(import.meta.dirname, '..')

// The frozen sheet snapshot the fixtures come from. A newer snapshot goes in its
// own dated folder; point this at it and rerun the script.
export const SNAPSHOT_DIR = join(ROOT, 'fixtures', 'attendance', '2026-09-27')
export const PARITY_DIR = join(ROOT, 'fixtures', 'attendance', 'parity')

/** Plain string order (UTF-16 code units, not locale collation), so every machine sorts alike. */
const byString = (a, b) => (a < b ? -1 : a > b ? 1 : 0)

/** Kilometres to 2 decimals, so float noise from a different summing order is never drift. */
const roundKm = (km) => Math.round(km * 100) / 100

/**
 * Build one season's parity fixture from its sheet CSV.
 *
 * `runs` is the Swift tests' input: each run with its raw sheet labels and the
 * web's normalized fields. `expected` is what the web computes from those runs;
 * the Swift kit must compute the same from the same runs.
 *
 * @param {string} csvText - the season's sheet CSV
 * @param {number} season - season year
 * @returns {object} plain JSON-ready fixture, keys in a fixed order
 */
export function buildParityFixture(csvText, season) {
  const data = parseRunData(csvText, season)

  // Date order, sheet order within a date (Array.prototype.sort is stable).
  const runs = [...data.runs].sort((a, b) => a.parsedDate - b.parsedDate)

  // Only members who ran: the Swift side sees runs, never the sheet header, so
  // a zero-run member is something it cannot recompute.
  const runners = data.members.filter((name) => data.memberTotals[name].totalRuns > 0).sort(byString)

  // The season's own club weekdays, the same table the web views use (KTD2).
  const days = buildClubDays(runs)

  return {
    season,
    clubWeekdays: [...clubWeekdays(season)],
    runs: runs.map((run) => ({
      id: run.id,
      date: isoDate(run.parsedDate),
      weekday: run.dayOfWeek,
      run: run.rawRun,
      meet: run.meet,
      type: run.type,
      event: run.event,
      location: run.location,
      actualKm: run.actualKm,
      attendees: [...run.attendees].sort(byString),
      plusOnes: run.plusOnes,
    })),
    expected: {
      // Member-km: actual km x attendees, +1s excluded, rounded after summing.
      totals: { runs: data.totalRuns, memberKm: roundKm(data.totalClubKm), runners: runners.length },
      members: runners.map((name) => ({
        name,
        runs: data.memberTotals[name].totalRuns,
        memberKm: roundKm(data.memberTotals[name].totalKm),
      })),
      clubDays: { count: days.length, dates: days.map((day) => day.date) },
      streaks: runners.map((name) => {
        const record = memberClubDays(days, name)
        return {
          name,
          current: record.current,
          currentFrom: record.currentFrom,
          best: record.best,
          bestFrom: record.bestFrom,
          bestTo: record.bestTo,
          madeByWeekday: record.madeByWeekday,
        }
      }),
      // Season totals only, so the file stands alone: the Swift test recomputes
      // it from this file's runs without the other season.
      milestones: milestoneShortlist(runners.map((name) => ({ name, runs: data.memberTotals[name].totalRuns }))),
    },
  }
}

/** Serialize a fixture exactly as it is committed: 2-space JSON and a trailing newline. */
export function formatFixture(fixture) {
  return JSON.stringify(fixture, null, 2) + '\n'
}

/**
 * Every parity file for the snapshot, oldest season first. A season is any
 * `<year>.csv` in SNAPSHOT_DIR.
 *
 * @returns {Array<{ season: number, path: string, content: string }>}
 */
export function buildParityFiles() {
  return readdirSync(SNAPSHOT_DIR)
    .filter((name) => /^\d{4}\.csv$/.test(name))
    .map((name) => Number(name.slice(0, 4)))
    .sort((a, b) => a - b)
    .map((season) => {
      const csvText = readFileSync(join(SNAPSHOT_DIR, `${season}.csv`), 'utf8')
      return {
        season,
        path: join(PARITY_DIR, `${season}.json`),
        content: formatFixture(buildParityFixture(csvText, season)),
      }
    })
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  mkdirSync(PARITY_DIR, { recursive: true })
  for (const { path, content } of buildParityFiles()) {
    writeFileSync(path, content)
    console.log(`Wrote ${relative(ROOT, path)}`)
  }
}
