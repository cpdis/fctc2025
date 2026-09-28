// Poster text formatting. Fixed English names (not Intl) so a date reads
// "Fri 25 Sep" in every browser locale, matching the mockup.

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** "Fri 25 Sep" for a local Date. */
export function formatDay(date) {
  return `${WEEKDAYS[date.getDay()]} ${date.getDate()} ${MONTHS[date.getMonth()]}`
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
