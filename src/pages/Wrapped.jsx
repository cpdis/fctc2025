import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import WrappedContainer from '../components/Wrapped/WrappedContainer'
import MemberSelector from '../components/Wrapped/MemberSelector'
import { calculateMemberStats, calculateClubStats } from '../utils/calculations'

// Wrapped's type (index.css: --font-display, --font-sans). Only Wrapped uses
// these families; the dashboard self-hosts its own through @fontsource.
const FONTS_HREF =
  'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,200..800&family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&display=swap'
const FONTS_ID = 'wrapped-fonts'

/**
 * Add Wrapped's Google Fonts stylesheet to <head>, once per page load. The
 * link stays after Wrapped unmounts, so coming back never refetches it. The
 * gstatic preconnect opens the font-file connection while the CSS downloads.
 */
function loadWrappedFonts() {
  if (document.getElementById(FONTS_ID)) return
  const preconnect = Object.assign(document.createElement('link'), {
    rel: 'preconnect',
    href: 'https://fonts.gstatic.com',
    crossOrigin: 'anonymous',
  })
  const stylesheet = Object.assign(document.createElement('link'), { id: FONTS_ID, rel: 'stylesheet', href: FONTS_HREF })
  document.head.append(preconnect, stylesheet)
}

export default function Wrapped({ data }) {
  const { member } = useParams()
  const navigate = useNavigate()
  const [selectedMember, setSelectedMember] = useState(member || null)
  const [showSelector, setShowSelector] = useState(!member)
  const [stats, setStats] = useState(null)

  useEffect(() => {
    loadWrappedFonts()
  }, [])

  // Change body background to navy when on Wrapped pages (fixes iOS Safari chrome)
  useEffect(() => {
    const originalBg = document.body.style.backgroundColor
    document.body.style.backgroundColor = '#020912' // navy
    document.documentElement.style.backgroundColor = '#020912' // also set on html

    return () => {
      document.body.style.backgroundColor = originalBg
      document.documentElement.style.backgroundColor = ''
    }
  }, [])

  useEffect(() => {
    if (selectedMember) {
      if (selectedMember === 'club') {
        setStats({ type: 'club', data: calculateClubStats(data) })
      } else {
        const memberStats = calculateMemberStats(data, selectedMember)
        if (memberStats) {
          setStats({ type: 'member', data: memberStats })
        }
      }
      setShowSelector(false)
    }
  }, [selectedMember, data])

  const handleMemberSelect = (memberName) => {
    setSelectedMember(memberName)
    if (memberName === 'club') {
      navigate('/wrapped')
    } else {
      navigate(`/wrapped/${encodeURIComponent(memberName)}`)
    }
  }

  const handleRestart = () => {
    setSelectedMember(null)
    setStats(null)
    setShowSelector(true)
    navigate('/wrapped')
  }

  if (showSelector) {
    return (
      <MemberSelector
        members={data.members}
        memberTotals={data.memberTotals}
        onSelect={handleMemberSelect}
      />
    )
  }

  if (!stats) {
    return (
      <div className="min-h-screen bg-espresso flex items-center justify-center">
        <div className="text-cream text-center">
          <div className="w-16 h-16 border-4 border-latte border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p>Generating your Wrapped...</p>
        </div>
      </div>
    )
  }

  return (
    <WrappedContainer
      stats={stats}
      clubData={data}
      onRestart={handleRestart}
    />
  )
}
