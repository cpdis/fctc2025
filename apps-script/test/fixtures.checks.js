/**
 * Fixture integrity tests (U1).
 *
 * Every unit downstream trusts `fixtures/attendance/`, and a typo'd roster name there
 * would surface as a mysterious Swift test failure days later. So the fixtures are
 * validated mechanically, here, against the real season header:
 *
 *   • every *.expected.json parses and has the documented shape
 *   • every expectation names a real input file that exists
 *   • every roster name used is a real 2026 header name, spelled exactly
 *   • poll expectations agree with their own .ocr.txt (names present, counts consistent)
 *
 * Schema reference: fixtures/attendance/README.md.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const FIXTURES_DIR = path.join(__dirname, '..', '..', 'fixtures', 'attendance');

/** Members of a season, derived exactly as the dashboard parser derives them. */
function rosterFor(year) {
  const csv = fs.readFileSync(path.join(FIXTURES_DIR, `${year}.csv`), 'utf8');
  const headerLine = csv.split('\n').find((line) => line.startsWith('Date,Meet,Run'));
  assert.ok(headerLine, `no header row in ${year}.csv`);
  const cells = headerLine.replace(/\r$/, '').split(',');
  const start = cells.indexOf('Actual kms');
  const end = cells.indexOf("+1's");
  return cells.slice(start + 1, end);
}

const ROSTERS = { 2026: rosterFor(2026), 2025: rosterFor(2025) };

const expectedFiles = fs
  .readdirSync(FIXTURES_DIR)
  .filter((name) => name.endsWith('.expected.json'))
  .sort();

const lines = (file) =>
  fs
    .readFileSync(path.join(FIXTURES_DIR, file), 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

test.describe('fixtures/attendance', () => {
  test.it('has the fixture set U1 promised', () => {
    const present = new Set(fs.readdirSync(FIXTURES_DIR));
    const required = [
      '2025.csv',
      '2026.csv',
      'poll-1.ocr.txt',
      'poll-1.expected.json',
      'poll-2.ocr.txt',
      'poll-2.expected.json',
      'poll-card-nameless.ocr.txt',
      'poll-card-nameless.expected.json',
      'voice-1.transcript.txt',
      'voice-1.expected.json',
      'voice-2.transcript.txt',
      'voice-2.expected.json',
      'voice-3.transcript.txt',
      'voice-3.expected.json',
    ];
    for (const file of required) {
      assert.ok(present.has(file), `missing fixture ${file}`);
    }
  });

  test.it('season copies match the source fixtures they were copied from', () => {
    for (const year of [2025, 2026]) {
      const copy = fs.readFileSync(path.join(FIXTURES_DIR, `${year}.csv`), 'utf8');
      const source = fs.readFileSync(
        path.join(FIXTURES_DIR, '..', '..', 'src', 'test', 'fixtures', `${year}.csv`),
        'utf8'
      );
      assert.equal(copy, source, `${year}.csv drifted from src/test/fixtures/${year}.csv`);
    }
  });

  test.it('derives the expected 2026 roster from the header row', () => {
    assert.equal(ROSTERS[2026].length, 33);
    assert.equal(ROSTERS[2026][0], 'Aaron');
    assert.equal(ROSTERS[2026].at(-1), 'Wes');
    // The collisions the matcher must never auto-resolve.
    for (const name of ['Alex 👑', 'Alex B', 'Alex Kr', 'Dan', 'Dan B', 'Laura E', 'Laura K']) {
      assert.ok(ROSTERS[2026].includes(name), `2026 roster should contain ${name}`);
    }
  });

  test.it('finds at least one expectation to check', () => {
    assert.ok(expectedFiles.length >= 6, 'expected JSON fixtures are missing');
  });
});

for (const file of expectedFiles) {
  test.describe(file, () => {
    const raw = fs.readFileSync(path.join(FIXTURES_DIR, file), 'utf8');
    let expected;

    test.it('parses as JSON', () => {
      expected = JSON.parse(raw);
      assert.equal(typeof expected, 'object');
    });

    test.it('has the common keys and a real input file', () => {
      expected = JSON.parse(raw);
      assert.ok(['poll-ocr', 'voice-transcript'].includes(expected.kind));
      assert.equal(typeof expected.fixture, 'string');
      assert.ok(
        fs.existsSync(path.join(FIXTURES_DIR, expected.fixture)),
        `input file ${expected.fixture} does not exist`
      );
      assert.equal(
        expected.fixture,
        file.replace('.expected.json', expected.kind === 'poll-ocr' ? '.ocr.txt' : '.transcript.txt'),
        'expectation must describe the same-stem input file'
      );
      assert.ok(Array.isArray(expected.notes) && expected.notes.length > 0);
      assert.ok(Array.isArray(expected.names));
      assert.ok(Array.isArray(expected.ambiguous));
      assert.ok(Array.isArray(expected.unmatchedRaw));
      assert.ok(ROSTERS[expected.season], `unknown season ${expected.season}`);
    });

    test.it('uses only real roster names, in sheet order, without duplicates', () => {
      expected = JSON.parse(raw);
      const roster = ROSTERS[expected.season];

      for (const name of expected.names) {
        assert.ok(roster.includes(name), `"${name}" is not a ${expected.season} roster name`);
      }
      assert.equal(new Set(expected.names).size, expected.names.length, 'duplicate names');

      const indexes = expected.names.map((n) => roster.indexOf(n));
      const sorted = [...indexes].sort((a, b) => a - b);
      assert.deepEqual(indexes, sorted, 'names should be listed in sheet (member-band) order');

      for (const entry of expected.ambiguous) {
        assert.equal(typeof entry.raw, 'string');
        assert.ok(Array.isArray(entry.candidates) && entry.candidates.length >= 2);
        for (const candidate of entry.candidates) {
          assert.ok(
            roster.includes(candidate),
            `ambiguous candidate "${candidate}" is not a ${expected.season} roster name`
          );
        }
        assert.ok(
          !expected.names.includes(entry.raw),
          `"${entry.raw}" cannot be both auto-checked and ambiguous`
        );
      }

      for (const unmatched of expected.unmatchedRaw) {
        assert.equal(typeof unmatched, 'string');
        assert.ok(
          !roster.includes(unmatched),
          `"${unmatched}" is on the roster, so it cannot be unmatched`
        );
      }
    });

    test.it('agrees with its input file', () => {
      expected = JSON.parse(raw);
      const inputLines = lines(expected.fixture);
      assert.ok(inputLines.length > 0, 'input fixture is empty');

      if (expected.kind === 'voice-transcript') {
        assert.equal(inputLines.length, 1, 'a transcript fixture is one utterance');
        assert.ok(
          expected.plusOnes === null || Number.isInteger(expected.plusOnes),
          'plusOnes must be an integer or null'
        );
        assert.ok(
          expected.distanceKm === null || typeof expected.distanceKm === 'number',
          'distanceKm must be a number or null'
        );
        assert.ok(Array.isArray(expected.guestNames));
        assert.equal(
          expected.guestNames.length <= (expected.plusOnes ?? 0),
          true,
          'more guest names than +1s'
        );
        return;
      }

      // poll-ocr
      assert.equal(typeof expected.isVoteDetailScreen, 'boolean');
      assert.ok(Array.isArray(expected.options) && expected.options.length > 0);
      assert.ok(Array.isArray(expected.candidateNames));

      const fromOptions = [];
      for (const option of expected.options) {
        assert.equal(typeof option.label, 'string');
        assert.equal(typeof option.isAffirmative, 'boolean');
        assert.ok(Array.isArray(option.rawNames));
        if (expected.isVoteDetailScreen && option.voteCount !== null) {
          assert.equal(
            option.rawNames.length,
            option.voteCount,
            `option "${option.label}" lists ${option.rawNames.length} names but claims ${option.voteCount} votes`
          );
        }
        for (const rawName of option.rawNames) {
          assert.ok(
            inputLines.includes(rawName),
            `"${rawName}" is not a line in ${expected.fixture}`
          );
          fromOptions.push(rawName);
        }
      }
      assert.deepEqual(
        expected.candidateNames,
        fromOptions,
        'candidateNames must be the option rawNames in screen order'
      );

      if (!expected.isVoteDetailScreen) {
        assert.equal(expected.names.length, 0, 'a poll card proposes nothing');
        assert.equal(expected.needsVotesView, true);
        assert.equal(typeof expected.reason, 'string');
      }
    });
  });
}
