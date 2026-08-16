//
//  ModelExtractorTests.swift
//  FCTCAttendanceKitTests
//
//  U5 — the extractor-selection logic, exercised through a fake `ModelGateway` so it
//  runs on a simulator with no Apple Intelligence, on CI, and on a device where the
//  model is still downloading. The FoundationModels call itself is the one thing that
//  needs a real device (see ios/HANDOFF.md); everything AROUND it is tested here.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

/// Stands in for `FoundationModelsGateway`.
struct FakeModelGateway: ModelGateway {

    enum Behaviour: Sendable {
        case unavailable(ModelUnavailableReason)
        case fails
        case returns(ExtractedEntities)
    }

    let behaviour: Behaviour

    var availability: ModelAvailability {
        get async {
            if case .unavailable(let reason) = behaviour {
                return .unavailable(reason: reason)
            }
            return .available
        }
    }

    func extractEntities(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractedEntities {
        switch behaviour {
        case .returns(let entities):
            return entities
        case .fails:
            throw ModelGatewayError.emptyResponse
        case .unavailable(let reason):
            throw ModelGatewayError.modelUnavailable(reason: reason)
        }
    }
}

@Suite("ModelExtractor — selection and safety rails")
struct ModelExtractorTests {

    static let transcript = "Colin, Aaron and Adam came, plus two guests, we did eight point seven k"

    static func extractor(_ behaviour: FakeModelGateway.Behaviour) -> ModelExtractor {
        ModelExtractor(gateway: FakeModelGateway(behaviour: behaviour))
    }

    @Test("Availability mirrors the gateway", arguments: [
        ModelUnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .frameworkMissing,
    ])
    func availability(reason: ModelUnavailableReason) async {
        let blocked = await Self.extractor(.unavailable(reason)).isAvailable
        let ready = await Self.extractor(.returns(.empty)).isAvailable
        #expect(!blocked)
        #expect(ready)
    }

    @Test("An unavailable model falls back to the heuristics, and says so")
    func unavailableFallsBack() async throws {
        let result = try await Self.extractor(.unavailable(.appleIntelligenceNotEnabled))
            .extract(from: Self.transcript, context: .voice)

        #expect(!result.usedModel)
        #expect(result.warnings.contains(.modelUnavailable))
        #expect(result.entities.names == ["Colin", "Aaron", "Adam"])
        #expect(result.entities.plusOnes == 2)
        #expect(result.entities.distanceKm == 8.7)
    }

    @Test("A throwing model falls back to the heuristics, and says so")
    func failureFallsBack() async throws {
        let result = try await Self.extractor(.fails)
            .extract(from: Self.transcript, context: .voice)

        #expect(!result.usedModel)
        #expect(result.warnings.contains(.modelFailed))
        #expect(result.entities.names == ["Colin", "Aaron", "Adam"])
    }

    @Test("A good model answer is used as-is")
    func modelAnswerWins() async throws {
        let answer = ExtractedEntities(
            names: ["Colin", "Aaron", "Adam"],
            plusOnes: 2,
            distanceKm: 8.7,
            guestNames: []
        )
        let result = try await Self.extractor(.returns(answer))
            .extract(from: Self.transcript, context: .voice)

        #expect(result.usedModel)
        #expect(result.warnings.isEmpty)
        #expect(result.entities == answer)
    }

    @Test("Fields the model left out are filled in from the heuristics")
    func heuristicsFillGaps() async throws {
        let answer = ExtractedEntities(names: ["Aaron"])
        let result = try await Self.extractor(.returns(answer))
            .extract(from: Self.transcript, context: .voice)

        #expect(result.usedModel)
        #expect(result.entities.names == ["Aaron"])
        #expect(result.entities.plusOnes == 2)
        #expect(result.entities.distanceKm == 8.7)
    }

    @Test("Invented names are dropped and flagged")
    func hallucinationsAreDropped() async throws {
        let answer = ExtractedEntities(names: ["Aaron", "Rohan", "Tarquin"])
        let result = try await Self.extractor(.returns(answer))
            .extract(from: Self.transcript, context: .voice)

        #expect(result.entities.names == ["Aaron"])
        #expect(result.warnings.contains(.modelHallucinated))
    }

    @Test("A model that invents everything falls back to the heuristics")
    func totalHallucinationFallsBack() async throws {
        let result = try await Self.extractor(.returns(ExtractedEntities(names: ["Rohan"])))
            .extract(from: Self.transcript, context: .voice)

        #expect(!result.usedModel)
        #expect(result.warnings.contains(.modelLowConfidence))
        #expect(result.warnings.contains(.modelHallucinated))
        #expect(result.entities.names == ["Colin", "Aaron", "Adam"])
    }

    @Test("An empty model answer falls back to the heuristics")
    func emptyAnswerFallsBack() async throws {
        let result = try await Self.extractor(.returns(.empty))
            .extract(from: Self.transcript, context: .voice)

        #expect(!result.usedModel)
        #expect(result.warnings.contains(.modelLowConfidence))
        #expect(result.entities.names == ["Colin", "Aaron", "Adam"])
    }

    @Test("Invented guests are dropped too")
    func hallucinatedGuests() async throws {
        let answer = ExtractedEntities(
            names: ["Grant"],
            plusOnes: 1,
            guestNames: ["Priya", "Imaginary Friend"]
        )
        let source = "Grant came, plus one guest, Priya, and we did seven point one"
        let result = try await Self.extractor(.returns(answer))
            .extract(from: source, context: .voice)

        #expect(result.entities.guestNames == ["Priya"])
        #expect(result.warnings.contains(.modelHallucinated))
    }

    @Test("The nameless-card warning survives the model path")
    func cardWarningSurvives() async throws {
        let lines = ["Yes", "13", "No", "4", "View votes"]
        let result = try await Self.extractor(.returns(ExtractedEntities(names: ["Aaron"])))
            .extract(from: lines.joined(separator: "\n"), context: .pollScreenshot(lines: lines))

        #expect(result.warnings.contains(.namelessPollCard))
        // "Aaron" is not in the card text, so the model's answer is dropped and the
        // heuristics (which propose nothing) win.
        #expect(result.entities.names.isEmpty)
    }

    @Test("The plain protocol call still works and defaults to voice")
    func protocolCall() async throws {
        let entities = try await Self.extractor(.unavailable(.modelNotReady))
            .extract(from: Self.transcript)
        #expect(entities.names == ["Colin", "Aaron", "Adam"])
    }

    @Test("The real gateway reports a reason rather than crashing when it cannot run")
    func realGatewayIsSafeToAsk() async {
        // On a simulator or a device without Apple Intelligence this is `.unavailable`;
        // on an eligible device it may be `.available`. Either way, asking is safe and
        // an unavailable answer must carry a reason the UI can explain.
        let availability = await FoundationModelsGateway().availability
        if case .unavailable(let reason) = availability {
            #expect(!reason.rawValue.isEmpty)
        }
    }
}
