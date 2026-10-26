//
//  SyncStatusViews.swift
//  FCTCAttendance
//
//  The Runs header's sync button and the pill above the tab bar that follows a
//  sync from the first read of the sheet to the last sent change (`SyncStatus`):
//
//    ┌──────────────────────────────────────┐
//    │ FCTC                      (↻)  (⚙)   │
//    │ …                                    │
//    │       ( ◌ Checking the sheet… )      │  ← while it runs
//    │       ( ✓ Updated 9:42 PM )          │  ← 2 s after, then gone
//    │      [ Runs · Events · Dashboard ]   │
//    └──────────────────────────────────────┘
//

import FCTCAttendanceKit
import SwiftUI

extension SyncStatus {
    /// "Checking the sheet…", "Sending 2 changes…", "Updated 9:42 PM".
    var text: String {
        switch self {
        case .checking:
            return "Checking the sheet…"
        case .sending(let count):
            return "Sending \(count) \(count == 1 ? "change" : "changes")…"
        case .idle(let date?):
            // Shown only just after a refresh lands, so always today's time.
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        case .idle(nil):
            return "Not updated yet"
        }
    }
}

/// A 44 pt glyph on a solid circle in the card color, as the Runs header
/// draws its buttons. 44 pt matches the system toolbar buttons (Back, +,
/// Retry) on every pushed screen. Not glass: any glass (hand-applied or
/// `.glass` style) renders a grey shadow smear to its left inside this list
/// row in light mode.
struct HeaderCircleIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemGroupedBackground), in: .circle)
    }
}

/// Starts a refresh, which reads the sheet and then sends the outbox. The
/// arrow turns for as long as `status` reports work, whoever started it.
/// Reduce Motion keeps it still, as the Unsynced tile does; the pill still
/// says what runs.
struct SyncButton: View {
    let status: SyncStatus
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HeaderCircleIcon(systemImage: "arrow.clockwise")
                // Continuous, not `.repeating`, which turns and then pauses 1.5 s.
                .symbolEffect(.rotate.clockwise, options: .repeat(.continuous), isActive: status.isWorking && !reduceMotion)
                // A new view when the work starts or stops: with `isActive`
                // alone the arrow kept turning after the sync had ended.
                .id(status.isWorking)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Sync")
        .accessibilityValue(status.isWorking ? status.text : "")
        .accessibilityIdentifier("home-sync")
    }
}

/// A glass capsule above the tab bar, Mail's pattern. It appears when a sync
/// starts. A sync that ends well shows its time for 2 s; one that ends with
/// an error banner hides at once, so an old "Updated" time never reads as
/// this sync's success.
struct SyncStatusPill: View {
    let status: SyncStatus
    /// The sync left an error banner (`HomeViewModel.syncFailed`).
    let failed: Bool

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The container lets the glass materialize in and out with the text.
        // Without it the glass vanished at once while the text still faded.
        GlassEffectContainer {
            if isVisible {
                HStack(spacing: 8) {
                    if status.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    Text(status.text)
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .glassEffectTransition(.materialize)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home-sync-status")
                .transition(.settle(scale: 0.9, anchor: .bottom, reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.crossFade, value: isVisible)
        .animation(Motion.crossFade, value: status)
        // A new status cancels the pending hide, so a second sync keeps it up.
        .task(id: status) {
            if status.isWorking {
                isVisible = true
            } else if isVisible {
                // Only a good sync time earns the tick.
                if case .idle(updatedAt: .some) = status, !failed {
                    // Cancelled means a newer status took over: leave the pill
                    // to it. Hiding here cut the tick to 0.2 s, because one
                    // sync moves `lastSyncedAt` twice.
                    guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                }
                isVisible = false
            }
        }
    }
}
