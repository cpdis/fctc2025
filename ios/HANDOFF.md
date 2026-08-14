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

---

# U5 handoff — NameMatcher + NameExtractor implementations

Delete this file after the orchestrator's review (per `_conventions.md`).

## What U5 built

| Area | Files |
|---|---|
| Text primitives | `Intelligence/TextNormalization.swift` — `NormalizedName` (core / tokens / compact / symbol signature) + `StringDistance` (Jaro, Jaro-Winkler, Levenshtein, normalized Levenshtein, `similarity`) |
| Matcher | `Intelligence/NameMatcher.swift` (replaces the U1 stub body), `Intelligence/NicknameTable.swift` (44 entries, plain dictionary) |
| Extractor seam | `Intelligence/NameExtractor.swift` — added `ExtractionMode`, `ExtractionContext`, `ExtractionWarning`, `ExtractionResult` and a defaulted `extract(from:context:)` requirement |
| Heuristics | `Intelligence/HeuristicExtractor.swift`, `Intelligence/VoiceTranscriptScanner.swift`, `Intelligence/PollLineScanner.swift` |
| Model path | `Intelligence/ModelExtractor.swift` — `ModelGateway` seam, `FoundationModelsGateway`, `@Generable GeneratedAttendance`, grounding + fallback logic |
| U1 stubs wired up | `PollScreenshotParser.parse(lines:)` and `VoiceEntryParser.parse(transcript:)` now delegate to the U5 scanners (one line each; no logic duplicated) |
| Tests | `FCTCAttendanceKitTests/{Fixtures,FixtureParityTests,NameMatcherTests,HeuristicExtractorTests,ModelExtractorTests}.swift` — 70 new `@Test` functions (many table-driven, so far more cases), on top of U1's 21 |
| Project | `ios/project.yml`: the granted edit — `../fixtures/attendance` as a **folder-reference resource** of `FCTCAttendanceKitTests` |

### The matcher's resolution order (first rule that fires wins)

1. **Exact key including its symbol signature** → `.matched` (`Alex 👑` → `Alex 👑`)
2. **Bare shared first name** → `.ambiguous` (`Dan` → [`Dan`, `Dan B`]) — deliberately runs
   *before* plain exact-key equality, which is what implements the post-U1 ruling
3. **Exact key**, undecorated and unshared → `.matched` (`Dan B`, `Laura K`)
4. **Nickname redirect** (max 2 hops), then retry 1-3 (`Colin` → `Col`)
5. **Qualifier prefix** (`Alex Kravchenko` → `Alex Kr`, `Dan Brown` → `Dan B`)
6. **Fuzzy scoring**: max of Jaro-Winkler and normalized Levenshtein over (core, compact,
   first token), then the 0.1 ambiguity band

The emoji is why normalization has two channels. Stripping `👑` outright (as the packet's
"`Alex 👑` ↔ `alex`" line implies) makes the exact sheet key `Alex 👑` normalize to `alex`,
which is the shared first name of three members — so the roster's own header cell would come
back ambiguous, contradicting `poll-1.expected.json`. `NormalizedName` therefore keeps the
stripped symbols as a side-channel signature: `core` is emoji-free for scoring, `identity`
(core + symbols) is what exact-key equality uses. A *decorated* query carries a disambiguator
no other roster key has, so it is not "bare"; an undecorated `Alex` still is.

## Fixture trace table (hand-traced, then re-verified by a reference implementation)

There is no Swift toolchain on this box, so every logic-critical rule was hand-traced against
the fixtures and then re-checked by writing the same algorithm out as a line-by-line Python
mirror and running it over all six fixtures **and** over every expectation asserted in the new
Swift tests (scratch artifact, not committed). "Traced result" below is what that mirror
produces; it agrees with the hand trace in every row.

| Fixture | Expected (U1's `*.expected.json`) | Traced result |
|---|---|---|
| `poll-1.ocr.txt` | detail screen; options Yes/13/affirmative, No/4, Maybe/2; 19 candidates; 12 names; `ambiguous []`; `unmatchedRaw ["Priya B"]` | **identical**. `Scot t` → `Scott` 1.00 (compact form), `Alex 👑` → `Alex 👑` 1.00 (rule 1), `Dan B`/`Laura K` 1.00 (rule 3), `Priya B` → `.unmatched(suggestions: [Laura E, Laura K, Liam, Rhys, Rohan])`, top score 0.633 → no pre-check |
| `poll-2.ocr.txt` | detail screen; options Yes/11/affirmative, No/2; 13 candidates; names `[Alex Kr, Celeste, Col, Kate B, Ming, Rhys, Tarquin, Wes]`; ambiguous `Alex`/`Dan`/`Laura`; `unmatchedRaw []` | **identical**. `Colin` → `Col` (nickname), `Alex Kravchenko` → `Alex Kr` (nickname, and rule 5 reaches the same answer independently), `Cel este` → `Celeste` 1.00 (compact), `Tarquln` → `Tarquin` 0.943, `Alex`/`Dan`/`Laura` → `.ambiguous` with exactly the expected candidates in sheet order |
| `poll-card-nameless.ocr.txt` | `isVoteDetailScreen false`, `needsVotesView true`, options Yes/13, No/4, Maybe/2, no candidates, no names | **identical**. Bare-label + bare-count layout recognised; `Colin` (the poll author line) sits above the first option header and is dropped; `HeuristicExtractor` raises `.namelessPollCard` |
| `voice-1.transcript.txt` | names `[Aaron, Adam, Col]`, plusOnes 2, distance 8.7, no guest names | **identical**. raw names `[Colin, Aaron, Adam]` → `Col`, `Aaron`, `Adam`; "plus two guests" → 2 (that `two` is not read as a distance because it has neither a unit word nor "point"); "eight point seven k" → 8.7 |
| `voice-2.transcript.txt` | names `[Kate B, Laura E, Ming, Rhys, Toby]`, plusOnes 0, distance 10.42, ambiguous `Alex`/`Dan` | **identical**. raw names `[Alex, Dan, Laura E, Kate B, Toby, Ming, Rhys]`; "So today we had" and "turned up at the last minute" yield nothing; "no guests" → 0 (not nil); "ten point four two kilometres" → 10.42 |
| `voice-3.transcript.txt` | names `[Grant, Joe, Scott]`, plusOnes 1, distance 7.1, guestNames `[Priya]` | **identical**. The guest clause consumes "plus one guest, Priya", so `Priya` never reaches `NameMatcher`; "ran the soft sand this morning" yields no names; "seven point one" (no unit word) → 7.1 |

Roster-collision coverage beyond the fixtures (all traced): `Alex`/`alex`/`Alexander`/`Da n`
→ ambiguous 3-way; `Dan`/`Daniel`/`Danny` → ambiguous `Dan`/`Dan B`; `Laura` → ambiguous;
`Alex B`/`Alex Kr`/`Laura E`/`Laura K`/`Dan B`/`Kate B` → exact; `Alex K` → `Alex Kr`;
`Dan Brown` → `Dan B`; `Gra nt` → `Grant`; `Céleste` → `Celeste`; `Priya`/`Zeb`/`Bartholomew`
→ never pre-checked.

## Verified here (Linux, no Xcode)

```
npm test (vitest, dashboard)   →  Test Files 12 passed (12)   Tests 107 passed (107)
node --test apps-script/test   →  # tests 36  # pass 36  # fail 0
```

Plus: `ios/project.yml` still parses as YAML with the fixture resource entry; delimiter
balance checked mechanically across every Swift file; the matching/parsing algorithm
re-implemented and run against all six fixtures and every assertion in the new Swift tests
(0 mismatches).

## Needs Colin's Mac (NOT verified here — no Swift toolchain)

In rough order of risk:

1. **FoundationModels API surface** (`ModelExtractor.swift`) — written against the documented
   iOS 26 API but never compiled. Specifically:
   - `LanguageModelSession { instructionsString }` (the `@InstructionsBuilder` trailing-closure
     form). If the compiler wants the direct form it is
     `LanguageModelSession(instructions: instructionsString)`.
   - `session.respond(to: promptString, generating: GeneratedAttendance.self)`, then
     `response.content`.
   - `SystemLanguageModel.default.availability` → `.available` / `.unavailable(reason)` with
     `.deviceNotEligible` / `.appleIntelligenceNotEnabled` / `.modelNotReady`.
   - **Optionals inside a `@Generable` struct** (`plusOnes: Int?`, `distanceKm: Double?`). If
     guided generation rejects optional properties, make them non-optional with a sentinel
     (`plusOnes: Int` = -1 for "unstated") and map in `extractEntities`. Nothing else depends
     on that shape — `ExtractedEntities` keeps its optionals either way.
   Everything *around* the framework call is already covered by `FakeModelGateway`, so fixing
   this cannot break the selection logic.
2. **Fixture resource wiring.** `xcodegen generate`, then confirm the built test bundle really
   contains `attendance/poll-1.ocr.txt`. `Fixtures.url(_:)` tries the folder-reference layout,
   the flat layout and a direct `resourceURL` path, so either XcodeGen style works; if all
   three miss, the failure message says exactly what to fix.
3. **Swift Testing parameterised tests** — several suites use `@Test(arguments:)` with arrays
   of tuples. Standard usage, but unverified by a compiler.
4. Stdlib usage worth a skim: `String.folding(options:locale:)`, `Character.isSymbol` /
   `Unicode.Scalar.Properties.isEmojiPresentation`, `split(whereSeparator:)`,
   `trimmingCharacters(in:)`.

## Decisions I made that the packet left open (flag if you disagree)

1. **Kept U1's `ExtractedEntities` / `extract(from:)` seam** rather than the packet's
   `ExtractedAttendance` / `extract(from:context:) -> ExtractedAttendance`. U1's type is
   already the fixture shape (it carries `guestNames`, which the packet's sketch predates) and
   21 existing tests plus `VoiceEntryExtractor` are written against it. The packet's
   context-aware call exists as an **additional, defaulted** protocol requirement returning
   `ExtractionResult` (entities + warnings + poll structure + `usedModel`).
2. **`context.warning = .namelessPollCard` became `ExtractionResult.warnings`.** A value-type
   context the extractor mutates would have to be `inout` or a class; warnings are output, so
   they travel with the output. `ExtractedEntities` is untouched, so its Codable shape still
   matches the fixtures exactly.
3. **Added a fourth `NameMatch` case, `.suggestion(name:score:)`** — the packet's 0.6-0.85
   tier. U1's enum had three cases and nothing switched over it exhaustively, so all 21 U1
   tests are untouched. `.autoCheckName`, `.offeredNames` and `.needsHuman` are convenience
   accessors; `.offeredNames` maps straight onto `UnmatchedName.suggestions` in
   `AttendanceDraft` for U4/U6/U7.
4. **The 0.1 ambiguity band only yields `.ambiguous` when the top score is ≥ 0.85.** A tight
   cluster of *weak* scores is noise, not a roster collision, so it returns
   `.unmatched(suggestions: cluster)` instead. That is what puts `Priya B` (top 0.633, five
   names inside the band) into `unmatchedRaw` as `poll-1.expected.json` requires, while
   `Da n` (top 1.00, `Dan` and `Dan B` in the band) still asks the human. Nothing below 0.85
   is ever pre-checked either way, so the safety property is unchanged.
5. **U1's `PollScreenshotParser` / `VoiceEntryParser` now delegate to the U5 scanners.** The
   U5 packet assigns the OCR chrome filter, the nameless-card detector and the voice
   stop-phrase/number parsing to `HeuristicExtractor` — the same logic those two stubs are
   TODO-ing. Rather than write it twice, it lives in `PollLineScanner` /
   `VoiceTranscriptScanner` and the U1 types forward. **U6/U7:** your Vision and
   `SFSpeechRecognizer` work plugs in above these; if you were going to fill the stub bodies,
   take the delegation instead (expect a one-line merge conflict there).
6. **Poll proposals come from affirmative options only**, matching U1's fixture reading
   (`names` = the pre-check proposal set). The full option structure, `No`/`Maybe` voters
   included, is on `ExtractionResult.poll` for the Review screen.
7. **Model grounding:** any name the model returns whose letters do not appear in the source
   text is dropped and flagged `.modelHallucinated`; if that empties the answer, the
   heuristics win with `.modelLowConfidence`. Fields the model omitted (`plusOnes`,
   `distanceKm`) are filled in from the heuristic pass.
8. **The nickname table is roster-specific by design** (values must be real header cells).
   `Alexander` → `Alex` → *ambiguous*: a nickname may narrow the field, never pick a person
   the roster itself cannot distinguish.

## Open questions for the orchestrator

1. Is decision 5 (delegating the U1 parser stubs) the split you want, or should
   `PollLineScanner`/`VoiceTranscriptScanner` stay private to U5 with U6/U7 owning the public
   parser types outright?
2. `Kate` (no qualifier) auto-checks `Kate B` because only one Kate is on the roster, while
   `Dan` does not because there are two Dans. That is the rule as written — ambiguity is about
   collisions, not about qualifiers — but it means the same shape of input behaves differently
   per roster. Confirm that is intended.
3. `Dan Brown` → `Dan B` via the qualifier-prefix rule (0.95, auto-checked). Real WhatsApp
   display names are exactly this shape, but a *guest* called Dan Brown would be pre-checked
   as `Dan B`. Happy with that, or should rule 5 cap at the suggestion tier?
4. `fixtures/attendance/` is now a build input to the iOS test target. Worth a line in
   `fixtures/attendance/README.md` so nobody moves the directory?
