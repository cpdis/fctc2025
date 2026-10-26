---
title: A filtered @Query froze the guest detail screen
date: 2026-10-02
category: ui-bugs
module: ios-attendance
problem_type: performance_issue
component: swiftdata_query
symptoms:
  - A screen pins the main thread at full CPU and never settles once a child screen is pushed
  - XCUITest fails with "Timed out while evaluating UI query" on that screen
  - sample shows the view's body, a computed property and a @Query getter running a fetch, over and over
root_cause: filtered_query_render_loop
resolution_type: code_fix
severity: high
tags: [ios, swiftdata, swiftui, Query, Predicate, render-loop, bisect]
---

# A filtered @Query froze the guest detail screen

## Problem

Two guest-history UI tests timed out tapping the promotion preview button. The app sat at
99 % CPU. `sample` showed the main thread looping: a List batch update, a layout pass,
`GuestDetailView.body`, `hasPendingAttendance`, and the `submissions` query getter running a
Core Data fetch on every pass.

The screen had `@Query(filter: PendingSubmission.outstandingPredicate) private var submissions`
(package P8). Before P8 the query was unfiltered and the test passed in 23 seconds.

## Symptoms

- A pushed detail screen with several `@Query` properties, one of them filtered, that spins
  once another screen is pushed on top of it.
- `sample <pid>` with `UICollectionViewListCoordinatorBase.performUpdates` and the `@Query`
  getter's fetch in the heaviest main-thread stacks.
- Home and Outbox carry the same filter and do not spin, so a predicate that works on one
  screen is no proof it works on another.

## What Didn't Work

- Reverting P8's custom `init`, which built two filtered queries from the view's parameters.
  Necessary (it rebuilt two descriptors on every parent render) but not sufficient.
- Making `outstandingPredicate` a stored `static let` instead of a computed `static var`, on
  the theory that a fresh `Predicate` per render made the query refetch. Sound hygiene, no
  change in the outcome. The commit that did it (`b76d2bb`) claims more than it delivered.
- Reading the diffs. Nothing in the file explained it. Bisecting did.

## Solution

Bisect by package merge on one simulator with the single failing test (about five minutes a
step): P4 pass, P6 pass, P3b pass, P8 fail. Then revert the one P8 change left on the screen
(`9c1ed6a`):

```swift
// All four queries are unfiltered on purpose. A filtered `@Query` on this
// screen made SwiftUI re-render and refetch without end once the promotion
// screen was pushed on top. The readers filter in memory, as before P8.
@Query private var submissions: [PendingSubmission]
```

`hasPendingAttendance` already filters `status != .done` in memory, so the behaviour is the same.

Rules for this codebase until the mechanism is understood:

1. `GuestDetailView` keeps its four queries unfiltered.
2. A new filtered `@Query` on a pushed screen gets the UI test for that screen run before
   merge, not only the kit suite.
3. A hang with "Timed out while evaluating UI query" is bisected by package merge before
   anyone theorises from the source. The theory cost more time than the bisect.

## Where it applies

- `ios/FCTCAttendance/Views/GuestDetailView.swift`
- Home and Outbox keep `@Query(filter: PendingSubmission.outstandingPredicate)`; they are
  covered by `FCTCAttendanceUITests` and `OutboxUITests` and do not spin.

## Verification

- `FCTCAttendanceUITests/SharedGuestUITests` `testGuestHistoryAndPromotionPreview` (23 s) and
  `testSavedRunRemainsSavedWhenPromotionPreviewFails` (15 s) pass on the fixed head.
- Bisect runs: `3ea2079` pass, `968b39e` pass, `b88b0eb` pass, `5fc1b6d` fail.
- To confirm a suspected loop: `sample <pid> 5 1 -file loop.txt` while the screen is open, and
  look for a List batch update plus a `@Query` getter in the heaviest main-thread stack.
