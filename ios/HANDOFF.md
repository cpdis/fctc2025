# U1 handoff — scaffolding & fixtures

Delete this file after the orchestrator's review (per `_conventions.md`).

## What U1 built

| Area | Files |
|---|---|
| Xcode project spec | `ios/project.yml` (XcodeGen; app + kit framework + test target, iOS 26.0, Swift 6, bundle id `com.cpdis.fctc-attendance`, Photo Library / Speech / Microphone usage strings) |
| App shell | `ios/FCTCAttendance/FCTCAttendanceApp.swift` (SwiftData `ModelContainer` bootstrap), `Views/HomeView.swift` (static Reminders-idiom home), `Assets.xcassets` (AccentColor + empty AppIcon) |
| Kit stubs | `ios/FCTCAttendanceKit/Models/{AttendanceSchema,Member,Run,AttendanceDraft,PendingSubmission}.swift`, `Services/{SheetAPI,SyncEngine}.swift`, `Intelligence/{NameMatcher,NameExtractor,PollScreenshotParser,VoiceEntryParser}.swift` |
| Kit tests | `ios/FCTCAttendanceKitTests/{ModelTests,ServiceTests,IntelligenceTests}.swift` (Swift Testing) |
| Apps Script | `apps-script/{appsscript.json,Code.gs,SheetOps.js,.clasp.json.example,.claspignore,package.json,README.md}`, `apps-script/test/` |
| Fixtures | `fixtures/attendance/` — season CSVs, 3 OCR dumps, 3 transcripts, 6 expected JSONs, `README.md` (schema) |
| Plumbing | `.gitignore` additions, `.github/workflows/attendance-tests.yml`, README "Attendance app" section |

## Verified here (Linux, no Xcode)

```
node --test apps-script/test   →  # tests 36  # pass 36  # fail 0
npm test (vitest, dashboard)   →  Test Files 12 passed (12)   Tests 107 passed (107)
npm run build                  →  ✓ built in 4.83s
```

Plus: `ios/project.yml` and the workflow parse as YAML; all six `*.expected.json`
parse; every roster name in every fixture is checked mechanically against the real
2026 header row by `apps-script/test/fixtures.checks.js`.

## Needs Colin's Mac (NOT verified here — no Swift toolchain on this box)

1. `brew install xcodegen && cd ios && xcodegen generate && open FCTCAttendance.xcodeproj`
   — first proof the spec is valid. The `.xcodeproj` and the generated
   `FCTCAttendance/Info.plist` are gitignored on purpose.
2. Build the `FCTCAttendance` scheme for an iOS 26 simulator, and run the
   `FCTCAttendanceKit` scheme's tests (21 tests across 3 suites). **Every Swift file
   here is unverified by a compiler** — expect to fix small things. Specific spots I'd
   check first, in rough order of risk:
   - `ModelConfiguration("FCTCAttendance", schema:isStoredInMemoryOnly:)` overload in
     `FCTCAttendanceApp.swift`.
   - Swift Testing availability in the test target (project.yml sets no explicit
     `SWIFT_TESTING` flags; Xcode 26 should just work).
   - `Color(.secondarySystemGroupedBackground)` / `.background(tint, in: .circle)` in
     `HomeView.swift`.
   - `SWIFT_STRICT_CONCURRENCY: complete` is on. Nothing here should trip it (all
     shared types are `Sendable` value types; the SwiftData `@Model` classes stay
     inside one isolation domain), but U3 should keep that in mind.
3. Signing: `DEVELOPMENT_TEAM` is empty in `project.yml`. Set it (or configure in
   Xcode) before a device build. TestFlight is U8, using your existing process.

## Decisions I made that the packet left open (flag if you disagree)

1. **Node test files are `*.checks.js`, not `*.test.js`, and `test/index.js` requires
   them.** Two hard constraints forced this, both verified empirically:
   - The repo root's Vitest globs the whole tree; a `*.test.js` under `apps-script/`
     gets collected by Vitest and fails with "No test suite found" — i.e. it breaks
     `npm test`. (Confirmed: it failed exactly that way before renaming.)
   - Node 22.22's `--test` does **not** expand a bare directory argument (it tries to
     load `apps-script/test` as a module and fails). The `index.js` aggregator makes
     the packet's acceptance command `node --test apps-script/test` work anyway.
   **This affects U2**: the plan text names `test/sheetops.test.js`. That filename will
   break `npm test`. Either U2 follows the `*.checks.js` convention (documented in
   `apps-script/README.md`), or you allow a `test.exclude` line in `vite.config.js` —
   which U1 was not permitted to touch.
2. **`apps-script/package.json` added** (`"type": "commonjs"`, no dependencies). The
   repo root is `"type": "module"`, which would otherwise make the CommonJS
   dual-environment files unloadable in Node. It is `private`, installs nothing, and
   is excluded from `clasp push` by `.claspignore`.
3. **Fixture expected-JSON schema** is a superset of the packet's sketch: poll files
   carry `options[]` (label / voteCount / isAffirmative / rawNames), `candidateNames`,
   `names`, `ambiguous[]`, `unmatchedRaw[]`; voice files carry `names`, `plusOnes`,
   `distanceKm`, `guestNames`, `ambiguous[]`, `unmatchedRaw[]`. Schema documented in
   `fixtures/attendance/README.md`. U6/U7 should be able to use these as-is; if they
   need a shape change, that's a packet decision, not a quiet edit.
4. **`names` in a poll fixture = affirmative options only.** Poll "yes" ≠ attended, so
   it is a pre-check proposal set; `No`/`Maybe` voters are candidates but not
   proposals. The plan's OCR paragraph ("remaining lines are candidate names") does not
   say which options seed checks — this is my reading of R4 + R6.
5. **`"Dan"` alone is `ambiguous` (`Dan` / `Dan B`) in the fixtures**, even though
   `Dan` is itself an exact roster key. The plan's ambiguity rule says first-name-only
   hits must suggest all candidates and never auto-pick, and I took that literally. If
   U5 wants exact-key equality to win instead, change the plan first, then the fixture.
6. **`Guest` is a value type on the draft; `PendingSubmission` stores `guestNames`.**
   Only the count travels to the sheet (`+1's`), per resolved Q2.
7. **`SheetAPI.submitAttendance` takes a `Sendable` `AttendanceSubmission` struct**,
   not the `@Model PendingSubmission` (a `@Model` class across an async boundary would
   fight strict concurrency). `AttendanceSubmission(pending)` does the snapshot.
8. **`appsscript.json` requests `spreadsheets.currentonly` + `script.scriptapp`.**
   That is the minimal set for a container-bound script using `SpreadsheetApp.getActive()`.
   If U2 ends up using `openById`, it must widen to `.../auth/spreadsheets`.
9. **Kit tests assert safe defaults, not stub bodies** (e.g. "an empty roster never
   matches", "a poll card proposes nothing"), so U5/U6/U7 should not have to delete
   them when the real implementations land.

## Open questions for the orchestrator

1. Where should Swift tests read `fixtures/attendance/` from? Options: add the
   directory as a resource bundle to `FCTCAttendanceKitTests` in `project.yml`, or
   resolve `#filePath`-relative paths at runtime. U1 wired neither (no fixture-reading
   Swift test exists yet) — U5/U6/U7 will need one of them; the resource-bundle route
   means a `project.yml` edit, which crosses unit boundaries.
2. Vitest/Node collision (decision 1 above): confirm `*.checks.js` as the standing
   convention, or grant U2 a one-line `vite.config.js` exclude.
3. `PollScreenshotParser` currently takes `[String]` (OCR lines) rather than an image,
   so it stays pure and testable. U6 owns the Vision → lines step; is that split OK?
4. App display name is `FCTC` (`CFBundleDisplayName`) with product name
   `FCTC Attendance`. Say the word if you want something else on the home screen.
