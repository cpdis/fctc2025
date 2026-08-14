const HISTORY_HALF_LIFE = 8
const FORECAST_EVENT_COUNT = 3

/** Return the exponential weight for a newest-first history position. */
export function getAttendanceHistoryWeight(age) {
  if (!Number.isSafeInteger(age) || age < 0) {
    throw new Error('History age must be a non-negative integer')
  }

  return 2 ** (-age / HISTORY_HALF_LIFE)
}

/**
 * Estimate one weekday attendance rate from boolean opportunities, newest first.
 * Empty history has no estimate because this model adds no prior observations.
 */
export function calculateWeightedAttendanceRate(history) {
  if (
    !Array.isArray(history) ||
    [...history].some((attended) => typeof attended !== 'boolean')
  ) {
    throw new Error('Attendance history must contain booleans')
  }
  if (history.length === 0) return null

  let attendedWeight = 0
  let totalWeight = 0

  history.forEach((attended, age) => {
    const weight = getAttendanceHistoryWeight(age)
    totalWeight += weight
    if (attended) attendedWeight += weight
  })

  return attendedWeight / totalWeight
}

/**
 * Calculate the exact chance of enough attendances across three independent events.
 * The distribution array holds the chance of exactly zero through three successes.
 */
export function calculateMilestoneChance(weekdayRates, runsNeeded) {
  if (
    !Array.isArray(weekdayRates) ||
    weekdayRates.length !== FORECAST_EVENT_COUNT ||
    [...weekdayRates].some((rate) => !Number.isFinite(rate) || rate < 0 || rate > 1)
  ) {
    throw new Error('Weekday rates must be three finite probabilities')
  }
  if (!Number.isInteger(runsNeeded) || runsNeeded < 1 || runsNeeded > FORECAST_EVENT_COUNT) {
    throw new Error('Runs needed must be an integer from 1 to 3')
  }

  let distribution = [1, 0, 0, 0]

  for (const rate of weekdayRates) {
    const next = [0, 0, 0, 0]

    for (let attendances = 0; attendances < FORECAST_EVENT_COUNT; attendances += 1) {
      next[attendances] += distribution[attendances] * (1 - rate)
      next[attendances + 1] += distribution[attendances] * rate
    }

    distribution = next
  }

  return distribution.slice(runsNeeded).reduce((sum, chance) => sum + chance, 0)
}
