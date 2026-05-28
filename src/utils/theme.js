// Filament Coffee Track Club color palette
export const colors = {
  // Primary brand colors
  pink: '#fa688e',
  pinkDark: '#d75b77',
  mint: '#9ed1af',
  mintDark: '#4d7059',
  orange: '#ff511b',
  cream: '#f2eee2',
  creamDark: '#e8e4d8',
  navy: '#020912',
  navyLight: '#1a2332',

  // Warm accent colors
  amber: '#d4a574',
  amberLight: '#e8c9a4',
  amberDark: '#b8956a',

  // Legacy aliases for compatibility
  coffee: '#d75b77',
  coffeeLight: '#fa688e',
  latte: '#9ed1af',
  terracotta: '#ff511b',
  espresso: '#020912',
  roast: '#1a2332',
  mocha: '#2a3342',
}

// Chart color palette (for multiple data series)
export const chartColors = [
  '#fa688e', // pink
  '#ff511b', // orange
  '#9ed1af', // mint
  '#d75b77', // pink dark
  '#4d7059', // mint dark
  '#1a2332', // navy light
  '#f2eee2', // cream
  '#e8e4d8', // cream dark
]

// Clean display names for run types
export const runTypeDisplayNames = {
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

// Run type colors - using FCTC palette
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
  'Special Event': '#9ed1af', // mint
  'Special Events': '#8b7355', // warm brown - grouped special events
  'Other': '#e8e4d8',        // cream dark
}

// ─────────────────────────────────────────────────────────────────────────────
// Clean dashboard design system (Tufte-grade, light, minimal)
//
// A restrained, near-white palette: white cards on a soft off-white surface,
// hairline borders, dark ink for text, and exactly ONE saturated accent for
// active controls and the primary data series. Everything else is layered by
// luminance (greys), not hue. This is intentionally separate from the playful
// Wrapped palette above so the two aesthetics never bleed into each other.
// ─────────────────────────────────────────────────────────────────────────────
export const dashboardColors = {
  bg: '#f7f7f5',        // app surface / page background (warm near-white)
  surface: '#f7f7f5',   // alias for bg, used where "surface" reads clearer
  card: '#ffffff',      // card background
  border: '#e7e7e3',    // hairline border
  ink: '#1a1a18',       // primary text / strongest data-ink
  inkMuted: '#71716c',  // secondary text, axis labels, captions
  accent: '#1a1a18',    // single dark accent for active controls (near-black)
  accentSoft: '#33332f', // slightly lifted accent for hover states
}

// Restrained data palette: one saturated accent + muted secondaries/greys.
// Order matters — index 0 is the primary series, the rest recede. Keep to 5.
export const dataColors = [
  '#1a1a18', // ink — primary series (highest data-ink)
  '#c2410c', // burnt orange — the one saturated accent
  '#71716c', // mid grey — secondary series
  '#a8a8a2', // light grey
  '#cfcfc9', // lighter grey — context / background series
]

// Neutral grey for context series (e.g. "rest of the field" behind a highlight).
export const dataColorMuted = '#cfcfc9'

// Gradient definitions for wrapped slides
export const gradients = {
  pink: 'linear-gradient(135deg, #d75b77 0%, #fa688e 100%)',
  mint: 'linear-gradient(135deg, #4d7059 0%, #9ed1af 100%)',
  orange: 'linear-gradient(135deg, #cc4115 0%, #ff511b 100%)',
  navy: 'linear-gradient(135deg, #020912 0%, #1a2332 100%)',
  cream: 'linear-gradient(135deg, #f2eee2 0%, #e8e4d8 100%)',
  sunset: 'linear-gradient(135deg, #ff511b 0%, #fa688e 100%)',
}

// Animation variants for framer-motion
export const slideVariants = {
  enter: {
    y: 50,
    opacity: 0,
  },
  center: {
    y: 0,
    opacity: 1,
  },
  exit: {
    y: -50,
    opacity: 0,
  },
}

export const fadeVariants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
}

export const scaleVariants = {
  hidden: { scale: 0.8, opacity: 0 },
  visible: { scale: 1, opacity: 1 },
}

export const staggerChildren = {
  visible: {
    transition: {
      staggerChildren: 0.1,
    },
  },
}

// Playful animation variants for warm/organic design
export const bounceIn = {
  initial: { scale: 0, opacity: 0 },
  animate: {
    scale: 1,
    opacity: 1,
    transition: { type: "spring", stiffness: 400, damping: 15 }
  }
}

export const squashStretch = {
  initial: { scaleY: 0.3, scaleX: 1.3, opacity: 0 },
  animate: {
    scaleY: 1,
    scaleX: 1,
    opacity: 1,
    transition: { type: "spring", stiffness: 300, damping: 12 }
  }
}

export const tiltHover = {
  initial: { rotate: -1.5 },
  hover: { rotate: 0, scale: 1.02, transition: { type: "spring", stiffness: 400 } }
}

export const floatIn = {
  initial: { y: 30, opacity: 0 },
  animate: {
    y: 0,
    opacity: 1,
    transition: { type: "spring", stiffness: 100, damping: 15 }
  }
}

export const wiggle = {
  animate: {
    rotate: [0, -3, 3, -2, 2, 0],
    transition: { duration: 0.5 }
  }
}

export const pulseGlow = {
  animate: {
    boxShadow: [
      "0 0 0 0 rgba(250, 104, 142, 0)",
      "0 0 20px 4px rgba(250, 104, 142, 0.3)",
      "0 0 0 0 rgba(250, 104, 142, 0)"
    ],
    transition: { duration: 2, repeat: Infinity }
  }
}
