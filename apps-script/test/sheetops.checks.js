/**
 * Smoke tests for the Apps Script side (U1).
 *
 * These deliberately test the SCAFFOLD, not sheet logic: that the dual-environment
 * module pattern actually loads in Node, that the files Apps Script needs are present
 * and free of Node-isms, and that the constants SheetOps will key off match the real
 * sheet header. U2 adds the geometry tests beside this file.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const APPS_SCRIPT_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(APPS_SCRIPT_DIR, '..');
const SheetOps = require(path.join(APPS_SCRIPT_DIR, 'SheetOps.js'));

/** Member names of a season fixture, read the way the sheet is read: by content. */
function readRosterHeader(year) {
  const csv = fs.readFileSync(
    path.join(REPO_ROOT, 'fixtures', 'attendance', `${year}.csv`),
    'utf8'
  );
  const headerLine = csv
    .split('\n')
    .find((line) => line.startsWith('Date,Meet,Run'));
  assert.ok(headerLine, `no header row found in ${year}.csv`);
  return headerLine.replace(/\r$/, '').split(',');
}

test.describe('SheetOps module (dual-environment pattern)', () => {
  test.it('loads in Node via module.exports', () => {
    assert.equal(typeof SheetOps, 'object');
    assert.equal(typeof SheetOps.cellText, 'function');
    assert.equal(typeof SheetOps.sheetOpsHealth, 'function');
  });

  test.it('reports a version consistent with its own constant', () => {
    const health = SheetOps.sheetOpsHealth();
    assert.equal(health.module, 'SheetOps');
    assert.equal(health.version, SheetOps.SHEETOPS_VERSION);
    assert.ok(Array.isArray(health.implemented));
    for (const name of health.implemented) {
      assert.equal(
        typeof SheetOps[name],
        'function',
        `sheetOpsHealth() claims ${name} but it is not exported`
      );
    }
  });

  test.it('cellText trims without normalizing the canonical member key', () => {
    assert.equal(SheetOps.cellText('  Alex Kr '), 'Alex Kr');
    assert.equal(SheetOps.cellText(null), '');
    assert.equal(SheetOps.cellText(undefined), '');
    assert.equal(SheetOps.cellText(0), '0');
    // Case and emoji are part of the key and must survive untouched.
    assert.equal(SheetOps.cellText('Alex 👑'), 'Alex 👑');
    assert.equal(SheetOps.cellText("+1's"), "+1's");
  });

  test.it('member-band boundary constants exist in both season headers', () => {
    for (const year of [2025, 2026]) {
      const header = readRosterHeader(year);
      const start = header.indexOf(SheetOps.MEMBER_BAND_START_AFTER);
      const end = header.indexOf(SheetOps.MEMBER_BAND_END_BEFORE);
      assert.ok(start >= 0, `${year}: no "${SheetOps.MEMBER_BAND_START_AFTER}" column`);
      assert.ok(end > start, `${year}: "${SheetOps.MEMBER_BAND_END_BEFORE}" must follow it`);
      assert.ok(end - start > 20, `${year}: member band looks implausibly small`);
    }
  });
});

test.describe('Apps Script sources', () => {
  const sources = ['Code.gs', 'SheetOps.js'];

  test.it('exist and parse as JavaScript', () => {
    for (const file of sources) {
      const full = path.join(APPS_SCRIPT_DIR, file);
      assert.ok(fs.existsSync(full), `${file} is missing`);
      // Throws a SyntaxError (failing the test) if the file does not parse.
      new Function(fs.readFileSync(full, 'utf8'));
    }
  });

  test.it('contain no require()/import — Apps Script has no module loader', () => {
    // Comments talk ABOUT require(); only code matters, so strip them first.
    const stripComments = (src) =>
      src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');

    for (const file of sources) {
      const src = stripComments(fs.readFileSync(path.join(APPS_SCRIPT_DIR, file), 'utf8'));
      assert.ok(!/\brequire\s*\(/.test(src), `${file} must not call require()`);
      assert.ok(!/^\s*import\s/m.test(src), `${file} must not use import`);
    }
  });

  test.it('appsscript.json is a valid V8 anonymous web app', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(APPS_SCRIPT_DIR, 'appsscript.json'), 'utf8')
    );
    assert.equal(manifest.runtimeVersion, 'V8');
    assert.equal(manifest.webapp.access, 'ANYONE_ANONYMOUS');
    assert.equal(manifest.webapp.executeAs, 'USER_DEPLOYING');
  });

  test.it('.clasp.json.example ships a placeholder, never a real script id', () => {
    const example = JSON.parse(
      fs.readFileSync(path.join(APPS_SCRIPT_DIR, '.clasp.json.example'), 'utf8')
    );
    assert.match(example.scriptId, /REPLACE_ME/);
  });
});
