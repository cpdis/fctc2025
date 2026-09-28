// Poster text formatting. Fixed English names (not Intl) so a date reads
// "Fri 25 Sep" in every browser locale, matching the mockup.

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** "Fri 25 Sep" for a local Date. */
export function formatDay(date) {
  return `${WEEKDAYS[date.getDay()]} ${date.getDate()} ${MONTHS[date.getMonth()]}`
}

/** "25 Sep", or "25 Sep 2025" with the year, for a local Date. */
export function formatShortDate(date, withYear = false) {
  const day = `${date.getDate()} ${MONTHS[date.getMonth()]}`
  return withYear ? `${day} ${date.getFullYear()}` : day
}

/** "Sep" for a 0-based month. */
export function monthName(month) {
  return MONTHS[month]
}

/** The local-midnight Date for an ISO day ("2026-09-25"), as the builders key them. */
export function parseIsoDate(iso) {
  const [year, month, day] = iso.split('-').map(Number)
  return new Date(year, month - 1, day)
}

/** Thousands separators, a fixed number of decimals: 9889.4 -> "9,889". */
export function formatNumber(value, fractionDigits = 0) {
  return value.toLocaleString('en-AU', {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  })
}

/** A delta with its sign: "+38", "−5" (a true minus sign), "±0". */
export function formatSigned(value) {
  const sign = value > 0 ? '+' : value < 0 ? '−' : '±'
  return `${sign}${formatNumber(Math.abs(value))}`
}
