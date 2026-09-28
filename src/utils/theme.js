// Run type names and colours for the 2025 Wrapped slides. The Poster dashboard
// styles itself in styles/poster.css and uses none of this.

// Clean display names for the raw "Run" labels Wrapped shows.
const runTypeDisplayNames = {
  'Half- Invasion Day': 'Invasion Day (Half Marathon)',
  '10k- Invasion Day': 'Invasion Day (10K)',
  'Mara- Anzac Day': 'ANZAC Day (Marathon)',
  'Half- Anzac Day': 'ANZAC Day (Half Marathon)',
  'Half- Beer Run': 'Beer Run (Half Marathon)',
  'Good Fri Pancake': 'Good Friday Pancake Run',
  'FILAMENT CUP 🏆': 'Filament Cup',
  'N/hood Loop': "N'hood Loop",
}

// Get clean display name for a run type
export const getRunTypeDisplayName = (runType) => {
  return runTypeDisplayNames[runType] || runType
}

// Run type colors - using FCTC palette. Keys are the parser's normalized types
// (club slide) and the raw labels that pass through unchanged (member slide).
export const runTypeColors = {
  'Intervals': '#ff511b',    // orange - high intensity
  'Social': '#fa688e',       // pink - fun/social
  'Soft Sand': '#c4a77d',    // sand/tan - beach vibes (visible on white)
  'Lakes Loop': '#9ed1af',   // mint - water/nature
  'River Loop': '#4d7059',   // dark mint - water
  'N\'hood Loop': '#d75b77', // dark pink
  'Hills': '#1a2332',        // navy - tough
  'Half Marathon': '#ff511b', // orange - achievement
  'Marathon': '#020912',     // navy - ultimate
  '10K': '#fa688e',          // pink
  'Filament Cup': '#ff511b', // orange - special
  'Other': '#e8e4d8',        // cream dark - a run with a blank "Run" cell
}
