import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { Analytics } from '@vercel/analytics/react'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
    {/* Web Analytics: via fctc.fun the events post to the hub project's
        same-origin /_vercel/insights; on cpd.dev, to this project. */}
    <Analytics />
  </React.StrictMode>,
)
