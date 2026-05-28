import { describe, it, expect } from 'vitest'
import { YEARS, YEAR_LIST, LATEST_YEAR, resolveYear } from './years'

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
  })
})
