---
title: "handoff: FCTC Attendance app — orchestration state + next steps (for the local Mac session)"
type: handoff
status: active
date: 2026-08-14
---

# Handoff: FCTC Attendance app orchestration

You are taking over as **orchestrator** of the FCTC Attendance iOS app build, continuing
a session that ran in Claude Code on the web. Everything durable is in this repo; this
doc is your entry point.

## Read these first (in order)

1. `docs/plans/2026-08-14-001-feat-fctc-attendance-ios-app-plan.md` — the full plan:
   architecture, all confirmed decisions, implementation units U1–U8, orchestration
   protocol. All open questions are resolved; do not re-litigate decisions.
2. `docs/plans/packets/_conventions.md` — agent ground rules, the **frozen API
   contract + post-U2 addendum**, Node-test conventions, sheet-safety invariant.
3. `ios/HANDOFF.md` and `apps-script/HANDOFF.md` — per-area Mac-verification punch
   lists left by the implementing agents.

## Current state (verified at handoff)

- **Branches**: work on **`feat/attendance-app`** (integration branch, head contains
  everything below). `claude/ios-attendance-app-plan-a6s6yt` mirrors the planning
  docs. `main` is untouched — it only receives the integration branch when U8 passes.
- **Done, merged, pushed**: U1 (scaffolding: `ios/` XcodeGen project, `apps-script/`
  skeleton, `fixtures/attendance/`, CI), U2 (complete Apps Script Web App API — four
  actions, locking, conflict detection, band-bounded write guard), U5 (NameMatcher +
  heuristic/FoundationModels extractors).
- **Tests green on Linux**: `npm test` → 107 dashboard tests; `node --test
  apps-script/test` → 145 API/geometry tests. **Swift code has NEVER been compiled**
  (built on Linux, verified by inspection + a Python mirror of the U5 algorithms).
- **Not started**: U3, U4, U6, U7, U8. Packets in `docs/plans/packets/U<N>.md` are
  standalone, agent-agnostic briefs — suggested split is Codex for U3/U4/U6/U7,
  Claude agents for U8 integration, but any capable agent can take any packet.
- The web dashboard is untouched and must stay that way.

## Next steps, in order

1. **Mac compile shakeout (do this before spawning any more agents):**
   `brew install xcodegen` if needed → `cd ios && xcodegen generate` → build
   `FCTCAttendance` + run the `FCTCAttendanceKitTests` scheme in Xcode 26.
   Fix what doesn't compile (commit as `fix(attendance): ...`). Priority checks from
   `ios/HANDOFF.md`: the FoundationModels API surface in
   `Intelligence/ModelExtractor.swift` (`LanguageModelSession`,
   `respond(to:generating:)`, `@Generable` optionals) — it's isolated behind the
   `ModelGateway` seam, so fixes there can't disturb the tested selection logic;
   fixture bundle loading via the test-target resource entry in `project.yml`;
   strict-concurrency diagnostics. U5's fixture expectations are behavior — if a
   test fails, suspect the port, not the fixture.
2. **Wave 3 — U3 (`docs/plans/packets/U3.md`)**: SheetAPI client + SwiftData models +
   SyncEngine outbox. Codex-assigned per the plan; hand Codex the packet +
   `_conventions.md` on `feat/attendance-app`. Unit branch
   `feat/attendance-u3-sync`, review against the packet's acceptance list, merge to
   integration. Now that a Mac is available, require compiled-and-passing tests, not
   inspection-only.
3. **Wave 4 — U4 (`U4.md`)** after U3 merges: the Reminders-style UI. Then **U6 +
   U7 (`U6.md`, `U7.md`)** in parallel (both depend on U4's review screen + U5,
   already merged).
4. **Sheet smoke test (Colin, ~30 min, any time from now):** follow
   `apps-script/test/smoke.md` against a **COPY** of the real Google Sheet. It
   settles the three things Linux couldn't verify — most critically whether
   `addMember`'s column insert widens the sheet's own SUM/COUNTA formula ranges.
   Do not deploy to the real sheet until this passes.
5. **U8 (`U8.md`)** once U2–U7 are merged and the smoke test passed: QR config
   import, polish, production `clasp` deploy, TestFlight via **Colin's existing
   TestFlight process** (in his Codex or local Claude Code tooling — do not invent a
   new pipeline), real-run end-to-end verification per the packet.

## Standing rules for the orchestrator

- Review every agent's work against its packet's acceptance list before merging;
  run both test suites after every merge; push `feat/attendance-app` after each
  accepted unit.
- Contract changes (the four-action API) require editing the plan/packets first,
  then code — never let an agent drift the seam unilaterally.
- Record any new rulings in the packets (there are existing "orchestrator ruling"
  precedents in `_conventions.md`, `U2.md`, `U5.md`–`U7.md`).
- Sheet-safety invariant is non-negotiable: writes only ever touch a run row's
  member band + `Actual kms` + `+1's`, the band header, or an inserted run row.
