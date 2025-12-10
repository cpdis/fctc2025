import { Routes, Route } from 'react-router-dom'
import { useState, useEffect } from 'react'
import Dashboard from './pages/Dashboard'
import Wrapped from './pages/Wrapped'
import RunDetail from './pages/RunDetail'
import { parseRunData } from './utils/dataParser'

function App() {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch('/data/runs.csv')
      .then(response => response.text())
      .then(csv => {
        const parsed = parseRunData(csv)
        setData(parsed)
        setLoading(false)
      })
      .catch(err => {
        setError(err.message)
        setLoading(false)
      })
  }, [])

  if (loading) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-coffee border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-coffee font-medium">Loading run data...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="text-center text-terracotta">
          <p className="text-xl font-bold mb-2">Error loading data</p>
          <p>{error}</p>
        </div>
      </div>
    )
  }

  return (
    <Routes>
      <Route path="/" element={<Dashboard data={data} />} />
      <Route path="/run/:runId" element={<RunDetail data={data} />} />
      <Route path="/wrapped" element={<Wrapped data={data} />} />
      <Route path="/wrapped/:member" element={<Wrapped data={data} />} />
    </Routes>
  )
}

export default App
