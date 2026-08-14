import { describe, expect, it } from 'vitest'
import {
  calculateMilestoneChance,
  calculateWeightedAttendanceRate,
  getAttendanceHistoryWeight,
} from './milestoneForecast'

describe('getAttendanceHistoryWeight', () => {
  it('uses an eight-opportunity exponential half-life without dropping old history', () => {
    expect(getAttendanceHistoryWeight(0)).toBe(1)
    expect(getAttendanceHistoryWeight(8)).toBe(0.5)
    expect(getAttendanceHistoryWeight(80)).toBeGreaterThan(0)
  })

  it.each([-1, 0.5, Number.NaN, Number.POSITIVE_INFINITY])(
    'rejects invalid history age %s',
    (age) => expect(() => getAttendanceHistoryWeight(age)).toThrow('History age must be a non-negative integer')
  )
})

describe('calculateWeightedAttendanceRate', () => {
  it('returns no estimate for empty history and keeps rates within their bounds', () => {
    expect(calculateWeightedAttendanceRate([])).toBeNull()
    expect(calculateWeightedAttendanceRate([false, false])).toBe(0)
    expect(calculateWeightedAttendanceRate([true, true])).toBe(1)
  })

  it('responds more strongly to the newest opportunity', () => {
    const recentAbsence = calculateWeightedAttendanceRate([false, true])
    const recentAttendance = calculateWeightedAttendanceRate([true, false])

    expect(recentAbsence).toBeLessThan(0.5)
    expect(recentAttendance).toBeGreaterThan(0.5)
  })

  it.each([null, [true, 1], [false, undefined], [true, , false]])(
    'rejects invalid boolean history %#',
    (history) => expect(() => calculateWeightedAttendanceRate(history)).toThrow('Attendance history must contain booleans')
  )
})

describe('calculateMilestoneChance', () => {
  it('matches the expected three-event distribution for fixed weekday rates', () => {
    const rates = [0.8, 0.8, 0.3]

    expect(calculateMilestoneChance(rates, 3)).toBeCloseTo(0.192, 12)
    expect(calculateMilestoneChance(rates, 2)).toBeCloseTo(0.736, 12)
    expect(calculateMilestoneChance(rates, 1)).toBeCloseTo(0.972, 12)
  })

  it('treats the three weekdays as independent Bernoulli events', () => {
    for (let mask = 0; mask < 8; mask += 1) {
      const rates = [0, 1, 2].map((bit) => (mask >> bit) & 1)
      const attendances = rates.reduce((sum, value) => sum + value, 0)

      for (let runsNeeded = 1; runsNeeded <= 3; runsNeeded += 1) {
        expect(calculateMilestoneChance(rates, runsNeeded)).toBe(
          attendances >= runsNeeded ? 1 : 0
        )
      }
    }
  })

  it.each([
    [[0.5, 0.5], 1],
    [[0.5, 0.5, -0.1], 1],
    [[0.5, 0.5, 1.1], 1],
    [[0.5, Number.NaN, 0.5], 1],
    [[0.5, , 0.5], 1],
  ])('rejects invalid weekday rates %#', (rates, runsNeeded) => {
    expect(() => calculateMilestoneChance(rates, runsNeeded))
      .toThrow('Weekday rates must be three finite probabilities')
  })

  it.each([0, 1.5, 4, Number.NaN])('rejects invalid runs-needed value %s', (runsNeeded) => {
    expect(() => calculateMilestoneChance([0.5, 0.5, 0.5], runsNeeded))
      .toThrow('Runs needed must be an integer from 1 to 3')
  })
})
