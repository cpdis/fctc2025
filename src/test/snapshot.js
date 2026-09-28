import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { combineYearData, parseRunData } from '../utils/dataParser'

// The dated snapshot of the live sheets (27 Sep 2026) that the approved
// mockup was drawn from: 2025 runs to Wed 31 Dec, 2026 to Fri 25 Sep.
// Under jsdom import.meta.url is not a file: URL, so use import.meta.dirname.
const snapshotDir = join(import.meta.dirname, '..', '..', 'fixtures', 'attendance', '2026-09-27')

/** One season of the snapshot, parsed. */
export const snapshot = (year) => parseRunData(readFileSync(join(snapshotDir, `${year}.csv`), 'utf-8'), year)

export const snap2025 = snapshot(2025)
export const snap2026 = snapshot(2026)
// Newest season first, the order the app merges them in.
export const snapAllTime = combineYearData([snap2026, snap2025])
