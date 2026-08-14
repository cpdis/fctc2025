/**
 * Node test entry point: `node --test apps-script/test`.
 *
 * Two constraints shape this file, and neither is negotiable:
 *
 *  1. The repo root runs Vitest with its default include (`**\/*.{test,spec}.*`)
 *     over the WHOLE repo, and Vitest cannot run `node:test` files. So these files
 *     must NOT be named `*.test.js` / `*.spec.js`, or `npm test` breaks. Hence
 *     `*.checks.js`.
 *  2. Node's test runner expands a DIRECTORY argument by matching its own test-file
 *     patterns — which `*.checks.js` deliberately does not match. Passing a directory
 *     therefore resolves to this `index.js`, which requires each checks file so every
 *     suite still runs from the one documented command.
 *
 * Add a new suite = drop a `*.checks.js` file here and require it below. Shared
 * helpers live in `test/support/` as plain modules — they are NOT `*.checks.js`, so
 * they are only ever loaded by the suite that requires them.
 */

require('./sheetops.checks.js');
require('./api.checks.js');
require('./fixtures.checks.js');
