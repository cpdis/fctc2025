//
//  ProposalTriageView.swift
//  FCTCAttendance
//
//  Modality-neutral proposal review behind the shared initializer contract.
//

import FCTCAttendanceKit
import SwiftUI

struct ProposalTriageView: View {
    let set: DraftProposalSet
    let onApply: ([String]) -> Void
    let onAddPerson: (String) -> Void
    let onCancel: () -> Void
    private let automaticProposals: [DraftProposal]
    private let pickProposals: [DraftProposal]
    private let suggestionProposals: [DraftProposal]

    @State private var automaticChecks: Set<String>
    @State private var choices: [String: String] = [:]

    init(
        set: DraftProposalSet,
        onApply: @escaping ([String]) -> Void,
        onAddPerson: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.set = set
        self.onApply = onApply
        self.onAddPerson = onAddPerson
        self.onCancel = onCancel
        automaticProposals = set.proposals.filter {
            if case .autoCheck = $0.resolution { return true }
            return false
        }
        pickProposals = set.proposals.filter {
            if case .pick = $0.resolution { return true }
            return false
        }
        suggestionProposals = set.proposals.filter {
            if case .suggest = $0.resolution { return true }
            return false
        }
        _automaticChecks = State(initialValue: Set(set.autoCheckNames))
    }

    var body: some View {
        List {
            if !automaticProposals.isEmpty {
                Section("Ready to check") {
                    ForEach(automaticProposals) { proposal in
                        if case .autoCheck(let name) = proposal.resolution {
                            Button {
                                toggleAutomatic(name)
                            } label: {
                                choiceLabel(
                                    title: name,
                                    detail: proposal.raw == name ? nil : "Heard “\(proposal.raw)”",
                                    selected: automaticChecks.contains(name)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("proposal-auto-\(proposal.id)")
                        }
                    }
                }
            }

            if !pickProposals.isEmpty {
                Section("Choose a person") {
                    ForEach(pickProposals) { proposal in
                        proposalGroup(proposal, offersAdd: false)
                    }
                }
            }

            if !suggestionProposals.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestionProposals) { proposal in
                        proposalGroup(proposal, offersAdd: true)
                    }
                }
            }

            if set.plusOnes != nil || set.distanceKm != nil || !set.guestNames.isEmpty {
                Section("Other details") {
                    if let distance = set.distanceKm {
                        LabeledContent("Actual kms", value: distance.formatted())
                    }
                    if let plusOnes = set.plusOnes {
                        LabeledContent("Guests", value: plusOnes.formatted())
                    }
                    if !set.guestNames.isEmpty {
                        LabeledContent("Guest names", value: set.guestNames.joined(separator: ", "))
                    }
                }
            }

            if set.isEmpty {
                Section {
                    Label("Nothing was found. Try again or enter attendance manually.", systemImage: "waveform.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    onApply(Array(resolvedChecks).sorted(by: Member.sheetOrder))
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("apply-proposals")
            }
        }
    }

    private var resolvedChecks: Set<String> {
        automaticChecks.union(choices.values)
    }

    @ViewBuilder
    private func proposalGroup(_ proposal: DraftProposal, offersAdd: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heard “\(proposal.raw)”")
                .font(.subheadline.weight(.semibold))

            ForEach(candidates(for: proposal), id: \.self) { candidate in
                Button {
                    choose(candidate, for: proposal.raw)
                } label: {
                    choiceLabel(
                        title: candidate,
                        detail: nil,
                        selected: choices[proposal.raw] == candidate
                    )
                }
                .buttonStyle(.plain)
            }

            if offersAdd {
                Button {
                    onAddPerson(proposal.raw)
                } label: {
                    Label("Add \(proposal.raw) as a new person", systemImage: "person.crop.circle.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("proposal-group-\(proposal.id)")
    }

    private func choiceLabel(title: String, detail: String?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func candidates(for proposal: DraftProposal) -> [String] {
        switch proposal.resolution {
        case .autoCheck(let name):
            [name]
        case .pick(let candidates), .suggest(let candidates):
            candidates
        }
    }

    private func toggleAutomatic(_ name: String) {
        if automaticChecks.contains(name) {
            automaticChecks.remove(name)
        } else {
            automaticChecks.insert(name)
        }
    }

    private func choose(_ candidate: String, for raw: String) {
        if choices[raw] == candidate {
            choices[raw] = nil
        } else {
            choices[raw] = candidate
        }
    }
}
