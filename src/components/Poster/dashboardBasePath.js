// Where the dashboard is mounted. fctc.fun proxies this app under /dashboard
// (the hub's vercel.json rewrites /dashboard/:path+), while the app's own
// domain serves it at the root. Links must stay under the mount point, or a
// click on fctc.fun falls out of the proxy.
//
// Stand-in for the shared path helpers (src/utils/dashboardPaths.js); when
// those land, import the base path from there and delete this file.

/**
 * @param {string} pathname - the current location's pathname
 * @returns {'/dashboard' | ''} the mount point to prefix app links with
 */
export function dashboardBasePath(pathname) {
  return pathname === '/dashboard' || pathname.startsWith('/dashboard/') ? '/dashboard' : ''
}
