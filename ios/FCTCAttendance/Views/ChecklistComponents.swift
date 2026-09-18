import FCTCAttendanceKit
import SwiftUI
import UIKit

struct MemberCheckRow: View {
    let name: String
    let provenance: CheckProvenance?
    let isSuggested: Bool
    let stats: MemberStats
    let action: () -> Void

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
                } else if isSuggested {
                    ProvenanceBadge(kind: .suggested)
                }
            }
            .contentShape(.rect)
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

struct CircularCheck: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isChecked ? Color.accentColor : .clear)
            Circle()
                .stroke(isChecked ? Color.accentColor : Color.secondary.opacity(0.45), lineWidth: 1.5)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
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
