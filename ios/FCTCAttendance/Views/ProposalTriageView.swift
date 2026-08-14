//
//  ProposalTriageView.swift
//  FCTCAttendance
//
//  Shared U6/U7 proposal review. This view knows only the frozen proposal seam;
//  screenshot and voice capture stay in their own flows around it.
//

import FCTCAttendanceKit
import SwiftUI
import UIKit

struct ProposalTriageView: View {
    let set: DraftProposalSet
    let roster: [String]
    let onApply: ([String]) -> Void
    let onAddPerson: (String) async throws -> Void
    let onCancel: () -> Void

    @State private var selections: [String: String]
    @State private var addNewProposalIDs: Set<String> = []
    @State private var isApplying = false
    @State private var applyErrorMessage: String?
    @State private var applyTask: Task<Void, Never>?

    init(
        set: DraftProposalSet,
        roster: [String],
        onApply: @escaping ([String]) -> Void,
        onAddPerson: @escaping (String) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.set = set
        self.roster = roster
        self.onApply = onApply
        self.onAddPerson = onAddPerson
        self.onCancel = onCancel
        _selections = State(initialValue: Dictionary(
            uniqueKeysWithValues: set.proposals.compactMap { proposal in
                guard case .autoCheck(let name) = proposal.resolution else { return nil }
                return (proposal.id, name)
            }
        ))
    }

    var body: some View {
        let buckets = ProposalBuckets(proposals: set.proposals)
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Review every suggestion. Nothing changes until you tap Apply.")
                    } icon: {
                        Image(systemName: "checklist")
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                }

                if set.isEmpty {
                    ContentUnavailableView(
                        "No Suggestions",
                        systemImage: "checklist.unchecked",
                        description: Text("No attendance details were found to review.")
                    )
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("triage-empty")
                }

                if !buckets.autoChecks.isEmpty {
                    Section {
                        ForEach(buckets.autoChecks) { proposal in
                            autoCheckRow(proposal)
                        }
                    } header: {
                        Text("Matched")
                    } footer: {
                        Text("These strong matches start checked. Untick anyone who did not attend.")
                    }
                }

                if !buckets.picks.isEmpty {
                    Section {
                        ForEach(buckets.picks) { proposal in
                            pickRows(proposal)
                        }
                    } header: {
                        Text("Choose a person")
                    } footer: {
                        Text("These names match more than one roster entry. Pick one explicitly or ignore it.")
                    }
                }

                if !buckets.suggestions.isEmpty {
                    Section {
                        ForEach(buckets.suggestions) { proposal in
                            suggestionRows(proposal)
                        }
                    } header: {
                        Text("Needs review")
                    } footer: {
                        Text("Map each name, add a new person, or leave it ignored.")
                    }
                }

                if hasExtraValues {
                    Section("Other details") {
                        if let distance = set.distanceKm {
                            LabeledContent("Distance", value: "\(distance.formatted()) km")
                        }
                        if let plusOnes = set.plusOnes {
                            LabeledContent("Guests", value: plusOnes.formatted())
                        }
                        ForEach(set.guestNames, id: \.self) { name in
                            LabeledContent("Guest", value: name)
                        }
                    }
                }

                if let applyErrorMessage {
                    Section {
                        Label(applyErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("triage-apply-error")
                    }
                }

                Section {} footer: {
                    provenanceLegend
                }
            }
            .listStyle(.insetGrouped)
            .disabled(isApplying)
            .navigationTitle("Review suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isApplying)
                        .accessibilityIdentifier("triage-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        applySelections()
                    }
                    .fontWeight(.semibold)
                    .disabled(isApplying)
                    .accessibilityHint("Applies these choices to the attendance draft.")
                    .accessibilityIdentifier("triage-apply")
                }
            }
        }
        .interactiveDismissDisabled(isApplying)
        .onDisappear {
            applyTask?.cancel()
            applyTask = nil
        }
    }

    private var hasExtraValues: Bool {
        self.set.distanceKm != nil || self.set.plusOnes != nil || !self.set.guestNames.isEmpty
    }

    private var selectedNames: [String] {
        var seen: Set<String> = []
        return self.set.proposals.compactMap { proposal in
            guard let name = selections[proposal.id] else { return nil }
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
    }

    private var provenanceLegend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                legendItem("sparkles", "Model")
                legendItem("waveform", "Voice")
                legendItem("photo", "Screenshot")
                legendItem("questionmark.circle", "Suggested")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Provenance: model, voice, screenshot, and suggested")
    }

    private func legendItem(_ image: String, _ label: String) -> some View {
        Label(label, systemImage: image)
            .fixedSize()
    }

    private func autoCheckRow(_ proposal: DraftProposal) -> some View {
        let selected = selections[proposal.id] != nil
        return Button {
            if selected {
                selections.removeValue(forKey: proposal.id)
            } else if case .autoCheck(let name) = proposal.resolution {
                selections[proposal.id] = name
            }
        } label: {
            HStack(spacing: 12) {
                TriageCheck(isChecked: selected)
                MemberAvatarView(name: selections[proposal.id] ?? proposal.raw)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selections[proposal.id] ?? proposal.raw)
                        .foregroundStyle(.primary)
                    if let selectedName = selections[proposal.id], selectedName != proposal.raw {
                        Text("Found as \(proposal.raw)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                ProvenanceBadge(kind: ProvenanceBadgeKind(set.provenance))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(proposal.raw)
        .accessibilityValue(selected ? "Checked" : "Not checked")
        // Without the button trait the combined element surfaces as `Other` and
        // XCUITest's buttons[] query cannot find it (same as MemberCheckRow).
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("triage-auto-\(proposal.raw)")
    }

    @ViewBuilder
    private func pickRows(_ proposal: DraftProposal) -> some View {
        if case .pick(let candidates) = proposal.resolution {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MemberAvatarView(name: proposal.raw)
                    Text(proposal.raw)
                        .font(.headline)
                    Spacer()
                    ProvenanceBadge(kind: .suggested)
                }
                ForEach(candidates, id: \.self) { candidate in
                    choiceButton(
                        title: candidate,
                        proposal: proposal,
                        candidate: candidate
                    )
                }
                ignoreButton(proposal)
            }
            .padding(.vertical, 4)
            // No container identifier: SwiftUI stamps it onto every contained
            // accessibility element, clobbering the per-candidate identifiers.
        }
    }

    @ViewBuilder
    private func suggestionRows(_ proposal: DraftProposal) -> some View {
        if case .suggest(let candidates) = proposal.resolution {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MemberAvatarView(name: proposal.raw)
                    Text(proposal.raw)
                        .font(.headline)
                    Spacer()
                    ProvenanceBadge(kind: .suggested)
                }

                ForEach(candidates, id: \.self) { candidate in
                    choiceButton(
                        title: "Did you mean \(candidate)?",
                        proposal: proposal,
                        candidate: candidate
                    )
                }

                Menu {
                    ForEach(roster, id: \.self) { name in
                        Button(name) { select(name, for: proposal) }
                            // Distinct from the checklist's member rows, which
                            // share the bare name as their label behind the sheet.
                            .accessibilityIdentifier("triage-map-pick-\(name)")
                    }
                } label: {
                    Label("Map to existing…", systemImage: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("triage-map-\(proposal.raw)")

                Button {
                    selections[proposal.id] = proposal.raw
                    addNewProposalIDs.insert(proposal.id)
                } label: {
                    Label("Add \(proposal.raw) as new person", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("triage-add-\(proposal.raw)")

                ignoreButton(proposal)
            }
            .padding(.vertical, 4)
            // No container identifier: see pickRows.
        }
    }

    private func choiceButton(
        title: String,
        proposal: DraftProposal,
        candidate: String
    ) -> some View {
        let selected = selections[proposal.id] == candidate
        return Button {
            select(candidate, for: proposal)
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                MemberAvatarView(name: candidate)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("triage-choice-\(proposal.raw)-\(candidate)")
    }

    private func ignoreButton(_ proposal: DraftProposal) -> some View {
        Button {
            selections.removeValue(forKey: proposal.id)
            addNewProposalIDs.remove(proposal.id)
        } label: {
            Label(
                selections[proposal.id] == nil ? "Ignored" : "Ignore",
                systemImage: selections[proposal.id] == nil ? "minus.circle.fill" : "minus.circle"
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(selections[proposal.id] == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ignore \(proposal.raw)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("triage-ignore-\(proposal.raw)")
    }

    private func select(_ candidate: String, for proposal: DraftProposal) {
        selections[proposal.id] = candidate
        addNewProposalIDs.remove(proposal.id)
    }

    private func applySelections() {
        guard !isApplying else { return }
        isApplying = true
        applyErrorMessage = nil
        let names = selectedNames
        let additions = set.proposals
            .filter { addNewProposalIDs.contains($0.id) }
            .map(\.raw)

        applyTask = Task {
            defer { applyTask = nil }
            do {
                for name in additions {
                    try Task<Never, Never>.checkCancellation()
                    try await onAddPerson(name)
                }
                try Task<Never, Never>.checkCancellation()
                onApply(names)
            } catch is CancellationError {
                isApplying = false
            } catch {
                applyErrorMessage = UserFacingError.sync(error)
                isApplying = false
            }
        }
    }
}

private struct ProposalBuckets {
    var autoChecks: [DraftProposal] = []
    var picks: [DraftProposal] = []
    var suggestions: [DraftProposal] = []

    init(proposals: [DraftProposal]) {
        for proposal in proposals {
            switch proposal.resolution {
            case .autoCheck:
                autoChecks.append(proposal)
            case .pick:
                picks.append(proposal)
            case .suggest:
                suggestions.append(proposal)
            }
        }
    }
}

private struct TriageCheck: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isChecked ? Color.accentColor : .clear)
            Circle()
                .stroke(
                    isChecked ? Color.accentColor : Color.secondary.opacity(0.45),
                    lineWidth: 1.5
                )
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
