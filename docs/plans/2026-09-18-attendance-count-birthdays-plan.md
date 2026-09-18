---
title: Attendance Count and Birthdays - Plan
type: feat
date: 2026-09-18
---

# Attendance Count and Birthdays - Plan

## Goal Capsule

Add a live attendance count and upcoming birthdays to the iOS app.
Implement and verify locally on the existing shared-guest branch. Hold release until Colin asks.

## Product Contract

### Summary

Show checked members beside the Attendance heading, with a separate total including guests.
Show birthdays beneath Home's milestones, using the spreadsheet birthday row.

### Problem Frame

Aaron counts people at each run but must count the app's ticks by hand.
The spreadsheet now contains birthdays that organisers want to see before each date.

### Requirements

**Attendance**

- R1. Show the live number of checked members above the checklist, independent of search filtering.
- R2. When guests are present, also show the total people and the guest count, including named and unnamed guests once each.

**Birthdays**

- R3. Show birthdays from today through 30 days ahead, ordered by days remaining then name, beneath the existing milestones.
- R4. Read day and month from the BIRTHDAY metadata row without treating that row as attendance or changing sheet contents.
- R5. Keep birthdays available offline after refresh and accept older server responses without the new field.

**Delivery**

- R6. Do not upload or distribute a TestFlight build, deploy Apps Script, mutate live sheets, or push GitHub changes.

### Key Decisions

- Use a 30-day birthday window. Governs R3. (session-settled: user-directed — chosen over a shorter window: Colin selected the next 30 days.)
- Hold distribution while the existing guest-sync build is being tested. Governs R6. (session-settled: user-directed — chosen over immediate release: Colin asked for implementation only.)

### Scope Boundaries

No birthday editing, ages, birth years, notifications, public dashboard fields, or changes to milestone rules.

## Planning Contract

- KTD1. Derive counts directly from AttendanceDraft checks and plusOnes. R1–R2 never add a second mutable count.
- KTD2. Add optional `birthdays: [{name, month, day}]` to SheetState. Missing preserves same-endpoint cached birthdays; an empty array clears them. Governs R4–R5.
- KTD3. Parse the metadata row by its label and discovered member columns, not row 12. Convert Google Date cells using the spreadsheet timezone. Governs R4.
- KTD4. Use the club's Gregorian Australia/Perth calendar for R3. Include today and day 30. Observe 29 February on 28 February in non-leap years; show the recorded birthday date.
- KTD5. Use native sections and text that wrap at accessibility sizes. A separate Birthdays section follows Milestones. Governs R1–R3.
- KTD6. Prefer the active sheet state's birthdays; otherwise use endpoint-scoped member cache. Historical navigation must not replace Home's active season data. Governs R5.

The additional total in R2 is an implementation assumption: it supports Aaron's head count while retaining the exact checked-member count he requested.

## Implementation Units

### U1. Sheet birthday contract

- **Goal:** R4–R5 via KTD2–KTD3.
- **Files:** `apps-script/SheetOps.js`, `apps-script/Code.gs`, server tests and API docs.
- **Tests:** Shifted metadata row; real Date cells in sheet timezone; text dates; invalid and missing values; legacy/shared state responses; attendance remains unchanged.
- **Verification:** `node apps-script/test/index.js`.

### U2. iOS birthday policy and cache

- **Goal:** R3–R5 via KTD2, KTD4, KTD6.
- **Files:** Kit models, SheetDTO, AttendanceCacheSync, BirthdayBoard and kit tests.
- **Tests:** Today, day 30/31, year rollover, leap day, malformed dates, old payloads, cache clear/preserve, endpoint changes, offline reload. Confirm that a historical-season refresh cannot clear or replace Home's active-season birthdays, including a later old payload and offline relaunch.
- **Verification:** FCTCAttendanceKit simulator tests.

### U3. Native displays and review

- **Goal:** R1–R3 via KTD1, KTD5; depends on U2 for birthdays.
- **Files:** Checklist header, BirthdaysSection, HomeView, synthetic UI fixtures and UI tests.
- **Tests:** Check/uncheck, search, imported checks, guest counts; birthday rows and empty state; small/large phones and accessibility text.
- **Verification:** UI tests with screenshots; local comparison page in ignored `review/attendance-birthdays/`.

## Verification Contract

Run server tests, iOS kit tests and the affected UI suite.
Inspect rendered screenshots on small and large simulators, including large text.
Review the diff for unrelated changes and release actions.
Record actual results in the daily worknote and local verification notes.

## Definition of Done

All requirements are implemented with passing relevant tests and a local visual review page.
Document the additive API and offline behavior.
Commit locally. Note that real birthday data requires a later Apps Script deployment and app release under R6.
