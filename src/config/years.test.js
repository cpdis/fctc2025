import { describe, it, expect } from 'vitest'
import {
  YEARS,
  YEAR_LIST,
  LATEST_YEAR,
  ALL_TIME,
  clubWeekdays,
  isAllTime,
  resolveYear,
} from './years'

describe('years config', () => {
  it('maps every year to a /data path', () => {
    YEAR_LIST.forEach((year) => {
      expect(YEARS[year]).toBe(`/data/${year}.csv`)
    })
  })

  it('lists years descending with LATEST_YEAR first', () => {
    expect(YEAR_LIST).toEqual([...YEAR_LIST].sort((a, b) => b - a))
    expect(LATEST_YEAR).toBe(YEAR_LIST[0])
  })

  describe('resolveYear', () => {
    it('accepts a valid year as a string', () => {
      expect(resolveYear('2025')).toBe(2025)
    })

    it('accepts a valid year as a number', () => {
      expect(resolveYear(2026)).toBe(2026)
    })

    it.each([null, undefined, '', 'banana', '1999', '2030', '2025.5'])(
      'falls back to LATEST_YEAR for invalid input %p',
      (input) => {
        expect(resolveYear(input)).toBe(LATEST_YEAR)
      }
    )

    it('resolves the all-time sentinel', () => {
      expect(resolveYear(ALL_TIME)).toBe(ALL_TIME)
      expect(resolveYear('all')).toBe(ALL_TIME)
    })
  })

  describe('all-time selection', () => {
    it('isAllTime is true only for the sentinel', () => {
      expect(isAllTime(ALL_TIME)).toBe(true)
      expect(isAllTime(2025)).toBe(false)
      expect(isAllTime(LATEST_YEAR)).toBe(false)
    })
  })

  describe('clubWeekdays', () => {
    it('2025 ran club days on Wednesday and Friday only', () => {
      expect(clubWeekdays(2025)).toEqual(['Wed', 'Fri'])
    })

    it('2026 runs club days on Monday, Wednesday and Friday', () => {
      expect(clubWeekdays(2026)).toEqual(['Mon', 'Wed', 'Fri'])
    })

    it('defaults an unlisted season to Monday, Wednesday and Friday', () => {
      expect(clubWeekdays(2027)).toEqual(['Mon', 'Wed', 'Fri'])
    })

    it('hands out a list callers cannot edit', () => {
      expect(Object.isFrozen(clubWeekdays(2025))).toBe(true)
      expect(Object.isFrozen(clubWeekdays(2027))).toBe(true)
    })
  })
})
