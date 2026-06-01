import { describe, it, expect } from 'vitest'
import { YEARS, YEAR_LIST, LATEST_YEAR, ALL_TIME, YEAR_OPTIONS, isAllTime, resolveYear } from './years'

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

    it('YEAR_OPTIONS lists every year plus All time last', () => {
      expect(YEAR_OPTIONS.map((o) => o.value)).toEqual([...YEAR_LIST, ALL_TIME])
      expect(YEAR_OPTIONS[YEAR_OPTIONS.length - 1]).toEqual({ value: ALL_TIME, label: 'All time' })
    })
  })
})
