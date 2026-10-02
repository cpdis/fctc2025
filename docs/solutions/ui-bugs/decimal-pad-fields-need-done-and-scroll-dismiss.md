---
title: Decimal-pad fields need a Done button and scroll-to-dismiss
date: 2026-10-02
category: ui-bugs
module: ios-attendance
problem_type: ui_bug
component: swiftui_text_input
symptoms:
  - The number keyboard stays on screen and hides the bottom of the checklist
  - The only way out is to leave the screen or press Return in another field
  - A distance typed in Add Run is lost when the user taps Add with the keyboard up
root_cause: missing_affordance
resolution_type: code_fix
severity: high
tags: [ios, swiftui, keyboard, decimalPad, FocusState, scrollDismissesKeyboard]
---

# Decimal-pad fields need a Done button and scroll-to-dismiss

## Problem

Aaron typed the actual kilometres on the checklist, then scrolled down to check runners.
The decimal pad has no Return key. The screen had no keyboard toolbar and no
`scrollDismissesKeyboard`, so the keyboard stayed up and covered the bottom of the roster.
He left the screen and came back to finish.

The Add Run sheet had the same field, with a second fault: `TextField(value:format:)` writes
its value only when editing ends. With no way to end editing, Add read `nil` kilometres.

## Symptoms

- A `.decimalPad` or `.numberPad` field with no `ToolbarItemGroup(placement: .keyboard)`.
- A `List` or `Form` with text input and no explicit `.scrollDismissesKeyboard`.
- A `TextField(value:format:)` whose value feeds a nav-bar action.

## What Didn't Work

- Relying on `.scrollDismissesKeyboard(.automatic)`. Apple's docs say lists dismiss on scroll
  by default, but in practice `List` and `Form` keep the keyboard until the mode is explicit.
- `.interactively` for this screen. It dismisses only when the drag crosses into the keyboard.
  An organiser scrolling down moves the finger up, so it never fires.
- Tap outside to dismiss. On a tap-to-check list a tap that closes the keyboard and toggles a
  runner is a misfire. SwiftUI has no API for it and the gestures fight the rows.

## Solution

Every screen with text input follows one pattern (see `GuestEditorView.swift`):

1. `.scrollDismissesKeyboard(.immediately)` on the `List` or `Form`.
2. One keyboard toolbar at the screen root, never inside a row, gated on a `@FocusState`
   for the field with no Return key:

```swift
@FocusState private var kilometresFocused: Bool
// ...
TextField("0", text: $viewModel.actualKmText)
    .keyboardType(.decimalPad)
    .focused($kilometresFocused)
// ...
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        if kilometresFocused {
            Spacer()
            Button("Done") { kilometresFocused = false }
                .accessibilityIdentifier("actual-km-keyboard-done")
        }
    }
}
```

The gate matters. The group applies to every text input in the view, including the
`.searchable` field and the quick-add row, which have their own Return key.

3. Bind number fields as text and parse on every keystroke (`DistanceText.parse`), so the
   model is current whenever the user taps a nav-bar action.
4. Tell blank from malformed. Blank means "no opinion" and the sheet's value stands. Text
   that is not a number (`DistanceText.isMalformed`) blocks the primary action and shows
   `DistanceText.malformedMessage` under the field, so a typo cannot silently keep the old
   distance.

## Where it applies

- `ios/FCTCAttendance/Views/ChecklistView.swift` (actual kilometres)
- `ios/FCTCAttendance/Views/RunPickerView.swift` (`AddRunView`, approx kilometres)
- `.scrollDismissesKeyboard(.immediately)` added to `SettingsView` and `GuestPromotionView`,
  whose Save result and Preview/Confirm rows sit below the fields.

## Verification

- `FCTCAttendanceKitTests/DistanceTextTests` (parse, malformed and format cases) and
  `ViewModelTests.malformedActualKmBlocksConfirmAndNamesItself`.
- `FCTCAttendanceUITests/ChecklistKeyboardUITests`: Done dismisses and keeps the value, a
  scroll dismisses and keeps the value, the search keyboard shows no distance Done button,
  a malformed distance shows the error and disables Confirm, Add Run's Done works, and the
  regression for Aaron's report: a distance typed with the keyboard still up survives a tap
  on Confirm and reads back after the drain (`testTypedDistanceSurvivesConfirmWithKeyboardUp`).
- `FCTCAttendanceKitTests/AddRunDraftTests`: the Add Run form's `canAdd` and `request` rules.
- Existing canaries still pass: `testGuestSearchKeyboardDismissesWithDoneAndDrag`,
  `testCountIncludesChecksAndGuestsAndSurvivesSearch`,
  `testChecklistHidesTabBarAndKeepsBottomSearch`.

## Known platform notes (October 2026)

- iOS 26.1 dropped keyboard toolbar items from the accessibility tree for a time
  (Apple forum 807529). If XCUITest cannot find the Done button on a newer runtime, check
  this before blaming the view.
- A forum report says iOS 27 ignores `Spacer()` in the keyboard toolbar, so Done may sit on
  the left. Cosmetic.
