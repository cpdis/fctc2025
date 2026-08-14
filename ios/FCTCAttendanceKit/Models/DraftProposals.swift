//
//  DraftProposals.swift
//  FCTCAttendanceKit
//
//  The frozen seam between the smart modalities (U6 screenshot, U7 voice) and the
//  Review & Confirm draft. Both pipelines end here: extracted entities go through
//  the matcher once, bucket into triage tiers, and the triage UI applies the
//  human-confirmed result through ChecklistViewModel.applyProposals.
//
//  Orchestrator-owned. Changing these shapes is a packet change, not a quiet edit.
//

import Foundation

/// One raw extracted name, resolved against the roster into a triage tier.
public struct DraftProposal: Hashable, Sendable, Identifiable {
    public enum Resolution: Hashable, Sendable {
        /// Confident match: pre-checked in the triage list, human can untick.
        case autoCheck(name: String)
        /// Roster collision: an explicit pick is required, never pre-checked.
        case pick(candidates: [String])
        /// Below the auto-check bar: offer "map to…" / "add as new" / ignore.
        case suggest(candidates: [String])
    }

    /// The string the extractor saw, before matching. Unique per set.
    public var raw: String
    public var resolution: Resolution

    public var id: String { raw }

    public init(raw: String, resolution: Resolution) {
        self.raw = raw
        self.resolution = resolution
    }
}

/// Everything one extraction pass proposes for the draft, ready for triage.
public struct DraftProposalSet: Hashable, Sendable {
    public var proposals: [DraftProposal]
    public var plusOnes: Int?
    public var distanceKm: Double?
    public var guestNames: [String]
    public var provenance: CheckProvenance

    public init(
        proposals: [DraftProposal] = [],
        plusOnes: Int? = nil,
        distanceKm: Double? = nil,
        guestNames: [String] = [],
        provenance: CheckProvenance
    ) {
        self.proposals = proposals
        self.plusOnes = plusOnes
        self.distanceKm = distanceKm
        self.guestNames = guestNames
        self.provenance = provenance
    }

    /// The shared bucketing rule: run every extracted name through the matcher,
    /// dedupe on the normalized raw string (multi-screenshot unions), and map the
    /// matcher's tiers onto triage resolutions. Pure; both modalities call this.
    public init(
        entities: ExtractedEntities,
        matcher: NameMatcher,
        provenance: CheckProvenance
    ) {
        var seen = Set<String>()
        var proposals: [DraftProposal] = []
        for raw in entities.names {
            let key = NormalizedName(raw).core
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let resolution: DraftProposal.Resolution
            switch matcher.match(raw) {
            case .matched(let name, _):
                resolution = .autoCheck(name: name)
            case .ambiguous(let candidates):
                resolution = .pick(candidates: candidates)
            case .suggestion(let name, _):
                resolution = .suggest(candidates: [name])
            case .unmatched(let suggestions):
                resolution = .suggest(candidates: suggestions)
            }
            proposals.append(DraftProposal(raw: raw, resolution: resolution))
        }
        self.init(
            proposals: proposals,
            plusOnes: entities.plusOnes,
            distanceKm: entities.distanceKm,
            guestNames: entities.guestNames,
            provenance: provenance
        )
    }

    /// The names the triage list pre-checks before the human touches anything.
    public var autoCheckNames: [String] {
        proposals.compactMap {
            if case .autoCheck(let name) = $0.resolution { return name }
            return nil
        }
    }

    /// True when nothing useful was extracted and the UI should coach instead.
    public var isEmpty: Bool {
        proposals.isEmpty && plusOnes == nil && distanceKm == nil
            && guestNames.isEmpty
    }
}
