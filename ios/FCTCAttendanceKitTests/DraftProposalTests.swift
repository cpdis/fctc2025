//
//  DraftProposalTests.swift
//  FCTCAttendanceKitTests
//
//  The frozen U6/U7 seam: extracted entities bucket into triage tiers, and a
//  confirmed triage outcome applies to the draft under the precedence rules.
//

import FCTCAttendanceKit
import Foundation
import Testing

@MainActor
@Suite("Draft proposals — the U6/U7 seam")
struct DraftProposalTests {

    private static let roster = ["Aaron", "Col", "Dan", "Dan B", "Kate B"]

    private func makeSet(
        names: [String] = [],
        plusOnes: Int? = nil,
        distanceKm: Double? = nil,
        guestNames: [String] = [],
        provenance: CheckProvenance = .ocr
    ) -> DraftProposalSet {
        DraftProposalSet(
            entities: ExtractedEntities(
                names: names,
                plusOnes: plusOnes,
                distanceKm: distanceKm,
                guestNames: guestNames
            ),
            matcher: NameMatcher(roster: Self.roster),
            provenance: provenance
        )
    }

    private func makeViewModel(
        attendees: [String] = [],
        actualKm: Double? = nil,
        plusOnes: Int = 0
    ) -> ChecklistViewModel {
        ChecklistViewModel(
            run: RunSnapshot(
                rowIndex: 42,
                date: "Fri, 14-Aug",
                scheduledAt: nil,
                meet: "Il Lido",
                run: "Soft Sand",
                approxKm: 7.1,
                actualKm: actualKm,
                attendees: attendees,
                plusOnes: plusOnes,
                cachedRevision: "rev-1"
            ),
            roster: Self.roster,
            engine: UnimplementedSyncEngine()
        )
    }

    // MARK: Bucketing

    @Test("Matcher tiers map onto triage resolutions")
    func tiersMapOntoResolutions() {
        let set = makeSet(names: ["Aaron", "Dan", "Kate", "Zebedee"])

        #expect(set.proposals.count == 4)
        #expect(set.proposals[0].resolution == .autoCheck(name: "Aaron"))
        #expect(set.proposals[1].resolution == .pick(candidates: ["Dan", "Dan B"]))
        // A unique first name auto-matches its only qualified roster key (U5).
        #expect(set.proposals[2].resolution == .autoCheck(name: "Kate B"))
        if case .suggest = set.proposals[3].resolution {} else {
            Issue.record("A stranger should land in the suggest tier")
        }
        #expect(set.autoCheckNames == ["Aaron", "Kate B"])
    }

    @Test("Union across screenshots dedupes on the normalized raw string")
    func dedupeIsNormalized() {
        let set = makeSet(names: ["Col", "col", " Col ", "Aaron"])
        #expect(set.proposals.map(\.raw) == ["Col", "Aaron"])
    }

    @Test("An empty extraction is empty so the UI can coach instead")
    func emptySetIsEmpty() {
        #expect(makeSet().isEmpty)
        #expect(!makeSet(distanceKm: 8.7).isEmpty)
    }

    // MARK: Application

    @Test("Applied checks carry the set's provenance; strangers are dropped")
    func checksCarryProvenance() {
        let viewModel = makeViewModel()
        viewModel.applyProposals(
            checks: ["Aaron", "Kate B", "Zebedee"],
            from: makeSet(provenance: .voice)
        )

        #expect(viewModel.draft.checks["Aaron"] == .voice)
        #expect(viewModel.draft.checks["Kate B"] == .voice)
        #expect(viewModel.draft.checks["Zebedee"] == nil)
    }

    @Test("A proposal never downgrades a manual check")
    func manualChecksWin() {
        let viewModel = makeViewModel(attendees: ["Col"])
        viewModel.applyProposals(checks: ["Col"], from: makeSet(provenance: .ocr))
        #expect(viewModel.draft.checks["Col"] == .manual)
    }

    @Test("A dictated distance fills a pristine field only")
    func typedDistanceSurvives() {
        let pristine = makeViewModel(actualKm: nil)
        pristine.applyProposals(checks: [], from: makeSet(distanceKm: 8.7))
        #expect(pristine.draft.actualKm == 8.7)

        let touched = makeViewModel(actualKm: nil)
        touched.actualKmText = "9.2"
        touched.applyProposals(checks: [], from: makeSet(distanceKm: 8.7))
        #expect(touched.draft.actualKm == 9.2)
    }

    @Test("Guest names join the draft and drive the derived count")
    func guestNamesApply() {
        let viewModel = makeViewModel()
        viewModel.applyProposals(
            checks: [],
            from: makeSet(plusOnes: 1, guestNames: ["Priya"], provenance: .voice)
        )

        #expect(viewModel.draft.guests.map(\.name) == ["Priya"])
        // Named guests derive the count; the bare number must not override it.
        #expect(viewModel.draft.plusOnes == 1)
        #expect(viewModel.draft.plusOnesOverride == nil)
    }

    @Test("A bare guest count fills an untouched count only")
    func bareCountRespectsCuration() {
        let pristine = makeViewModel()
        pristine.applyProposals(checks: [], from: makeSet(plusOnes: 2))
        #expect(pristine.draft.plusOnes == 2)

        let curated = makeViewModel()
        curated.quickAddName = "Priya"
        curated.addGuest(name: "Priya")
        curated.applyProposals(checks: [], from: makeSet(plusOnes: 5))
        #expect(curated.draft.plusOnes == 1)
    }
}
