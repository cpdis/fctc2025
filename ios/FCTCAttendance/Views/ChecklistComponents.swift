import FCTCAttendanceKit
import SwiftUI
import UIKit

struct MemberCheckRow: View {
    let name: String
    let provenance: CheckProvenance?
    let isSuggested: Bool
    let stats: MemberStats
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isChecked: Bool { provenance != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CircularCheck(isChecked: isChecked)

                MemberAvatarView(name: name)

                Text(name)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let provenance, provenance != .manual {
                    ProvenanceBadge(kind: ProvenanceBadgeKind(provenance))
                        .transition(badgeTransition)
                } else if isSuggested {
                    ProvenanceBadge(kind: .suggested)
                        .transition(badgeTransition)
                }
            }
            .contentShape(.rect)
            // Applied suggestions settle their badges in place instead of popping.
            .animation(Motion.snappy, value: provenance)
            .animation(Motion.snappy, value: isSuggested)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityHint("Double-tap to \(isChecked ? "uncheck" : "check").")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("member-\(name)")
        .contextMenu {
            Button(action: {}) {
                Label("\(stats.attendanceCount) season attendances", systemImage: "calendar")
            }
            .disabled(true)
            Button(action: {}) {
                Label(lastAttendedLabel, systemImage: "clock")
            }
            .disabled(true)
            Button(action: {}) {
                Label("\(stats.currentStreak) run streak", systemImage: "flame")
            }
            .disabled(true)
        }
    }

    private var badgeTransition: AnyTransition {
        .settle(scale: 0.9, anchor: .trailing, reduceMotion: reduceMotion)
    }

    private var lastAttendedLabel: String {
        guard let date = stats.lastAttendedAt else { return "No recorded attendance" }
        return "Last attended \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// The prominent capture-modality tile pair above the detail rows.
struct ModalityButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }
}

/// The Reminders-style check shared by the checklist and proposal triage.
/// Organisers tap it dozens of times per run, so the motion stays under a
/// quarter second and the filled state is legible from the first frame.
struct CircularCheck: View {
    let isChecked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1.5)
                .opacity(isChecked ? 0 : 1)
            // The fill grows out from inside the ring, so a check lands like a
            // press rather than a color swap.
            Circle()
                .fill(Color.accentColor)
                .scaleEffect(isChecked || reduceMotion ? 1 : 0.4)
                .opacity(isChecked ? 1 : 0)
            // Checking draws the tick on and unchecking wipes it off. The
            // opacity keeps the tick hidden if a symbol lacks draw data.
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .symbolEffect(.drawOff, options: .speed(1.8), isActive: !isChecked)
                .opacity(isChecked ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(Motion.snappy, value: isChecked)
        .accessibilityHidden(true)
    }
}

struct QuickAddPersonRow: View {
    @Bindable var viewModel: ChecklistViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            TextField("Add person…", text: $viewModel.quickAddName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit {
                    Task { try? await viewModel.commitQuickAdd() }
                }
                .accessibilityLabel("Add person")
                .accessibilityHint("Enter a name, then press Return.")
                .accessibilityIdentifier("add-person-field")

            if viewModel.isAddingPerson {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Adding person")
            }
        }
    }
}
