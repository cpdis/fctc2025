import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import SiteHeader from '../components/Poster/SiteHeader'
import SeasonTitle from '../components/Poster/SeasonTitle'
import HeadlineNumbers from '../components/Poster/HeadlineNumbers'
import Marquee from '../components/Poster/Marquee'
import SiteFooter from '../components/Poster/SiteFooter'
import OnARoll from '../components/Dashboard/OnARoll'
import Leaderboard from '../components/Dashboard/Leaderboard'
import TheWall from '../components/Dashboard/TheWall'
import EveryRun from '../components/Dashboard/EveryRun'
import VsLastYear from '../components/Dashboard/VsLastYear'
import MilestoneBibs from '../components/Dashboard/MilestoneBibs'
import RunLog from '../components/Dashboard/RunLog'
import { everyRunTracks, headline, onARoll, seasonProgress, wallModel } from '../utils/dashboardMetrics'
import { milestoneShortlist } from '../utils/clubDays'
import { resolveYear, isAllTime } from '../config/years'
import { yearSwitchParams } from '../utils/dashboardPaths'
import '../styles/poster-charts.css'

/**
 * The season dashboard, in the approved Poster order (R9): title band and
 * meta row, headline numbers, the marquee, On a roll beside the leaderboard,
 * The Wall, Every run, Vs last year, Milestones ahead and the run log.
 *
 * Every figure comes from a pure builder (utils/dashboardMetrics.js,
 * utils/clubDays.js), computed once per view; the sections only draw them.
 *
 * @param {object} props
 * @param {object} props.data - the selected view: one season, or All time
 * @param {object|null} [props.previous] - the season before a single-season
 *   view, for the same-date comparisons; null for the earliest season and
 *   for All time
 * @param {object} props.allTime - every season merged; milestones always
 *   count all-time runs, whatever the view
 * @param {string[]} props.roster - the latest season's members. Milestones
 *   list only them, as the app does (LifetimePriors(rosterOf:)), so a former
 *   member never takes a current member's place on the shortlist
 */
export default function Dashboard({ data, previous = null, allTime, roster }) {
  // The selected season lives in ?year; the title band's year control writes
  // it. The footer label is "All Time" for the combined view, else
  // "<year> Season".
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedYear = resolveYear(searchParams.get('year'))
  const allTimeView = isAllTime(selectedYear)
  const seasonLabel = allTimeView ? 'All Time' : `${selectedYear} Season`

  // A new season is a new view, so the run-log filters reset (AE7).
  const selectYear = (year) => setSearchParams(yearSwitchParams(searchParams, year))

  // The meta row's last run: the latest by date, since All time concatenates
  // seasons newest first rather than in date order. The next run is the
  // first scheduled row still to come.
  const lastRun = useMemo(() => {
    if (data.runs.length === 0) return null
    const latest = data.runs.reduce((a, b) => (b.parsedDate > a.parsedDate ? b : a))
    return { date: latest.parsedDate, location: latest.location, type: latest.type }
  }, [data.runs])
  const upcoming = data.upcoming[0]
  const nextRun = upcoming && { date: upcoming.parsedDate, location: upcoming.location, type: upcoming.type }

  // "Updated" timestamp, stamped by the weekly data-sync GitHub Action
  // whenever it commits fresh data (see .github/workflows/weekly-data-sync.yml).
  // Rendered in the viewer's local timezone. Fetched best-effort: if the file is
  // missing or malformed the meta row simply leaves it out.
  const [lastUpdated, setLastUpdated] = useState(null)
  useEffect(() => {
    let cancelled = false
    fetch('/data/last-updated.json')
      .then((res) => (res.ok ? res.json() : null))
      .then((json) => {
        const ts = json?.updatedAt ? new Date(json.updatedAt) : null
        if (!cancelled && ts && !Number.isNaN(ts.getTime())) setLastUpdated(ts)
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [])

  // One pass of each builder per view (or per previous season), never per render.
  const numbers = useMemo(() => headline(data, previous), [data, previous])
  const roll = useMemo(() => onARoll(data), [data])
  const wall = useMemo(() => wallModel(data), [data])
  const tracks = useMemo(() => everyRunTracks(data), [data])
  const progress = useMemo(() => seasonProgress(data, previous), [data, previous])
  const milestones = useMemo(() => {
    const current = new Set(roster)
    return milestoneShortlist(
      Object.values(allTime.memberTotals)
        .filter(({ name }) => current.has(name))
        .map(({ name, totalRuns }) => ({ name, runs: totalRuns }))
    )
  }, [allTime, roster])

  const delta = numbers.vsPrevious && {
    year: numbers.vsPrevious.year,
    runs: numbers.vsPrevious.runsDelta,
    km: numbers.vsPrevious.memberKmDelta,
  }

  return (
    // The .poster root scopes the fctc.fun brand tokens and fonts
    // (styles/poster.css), so Wrapped keeps its own palette.
    <div className="poster">
      <SiteHeader year={selectedYear} />

      <main>
        <div className="wrap">
          <SeasonTitle
            year={selectedYear}
            onSelectYear={selectYear}
            updatedAt={lastUpdated}
            lastRun={lastRun}
            nextRun={nextRun}
          />
          <HeadlineNumbers
            runs={numbers.runs}
            km={numbers.memberKm}
            runners={numbers.runners}
            perRun={numbers.perRun}
            delta={delta}
          />
        </div>
        {/* Every active runner's current streak: the Wall's rows carry them. */}
        <Marquee runs={numbers.runs} km={numbers.memberKm} runners={numbers.runners} streaks={wall.rows} />

        <div className="wrap">
          <section className="block" aria-label="Streaks and leaderboard">
            <div className="pair">
              <OnARoll {...roll} allTime={allTimeView} />
              <Leaderboard leaderboard={data.leaderboard} distanceLeaderboard={data.distanceLeaderboard} />
            </div>
          </section>
          <TheWall model={wall} />
          <EveryRun tracks={tracks} />
          <VsLastYear progress={progress} />
          <MilestoneBibs shortlist={milestones} />
          <RunLog runs={data.runs} />
        </div>
      </main>

      <SiteFooter seasonLabel={seasonLabel} />
    </div>
  )
}
