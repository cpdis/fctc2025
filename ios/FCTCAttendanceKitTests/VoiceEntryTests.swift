//
//  VoiceEntryTests.swift
//  FCTCAttendanceKitTests
//
//  U7 — the fake transcriber drives the same parser, matcher, proposal, and draft
//  seams used by the voice sheet. Speech.framework is the only omitted layer.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@MainActor
private final class FakeTranscriber: Transcriber {
    var authorization: TranscriberAuthorization
    var requestedAuthorization: TranscriberAuthorization?
    var transcripts: [String]
    var mode: TranscriptionMode
    private(set) var startCount = 0
    private(set) var requestCount = 0
    private(set) var finishCount = 0
    private(set) var stopCount = 0
    private var handlers: [(@MainActor @Sendable (TranscriptionUpdate) -> Void)] = []

    init(
        authorization: TranscriberAuthorization = .authorized,
        requestedAuthorization: TranscriberAuthorization? = nil,
        transcripts: [String] = [],
        mode: TranscriptionMode = .onDevice
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.transcripts = transcripts
        self.mode = mode
    }

    func authorizationStatus() async -> TranscriberAuthorization {
        authorization
    }

    func requestAuthorization() async -> TranscriberAuthorization {
        requestCount += 1
        let resolved = requestedAuthorization ?? authorization
        authorization = resolved
        return resolved
    }

    func start(
        updateHandler: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionMode {
        let transcript = transcripts.indices.contains(startCount) ? transcripts[startCount] : ""
        startCount += 1
        handlers.append(updateHandler)

        // Replay a partial result before the complete text. This proves the view model
        // replaces partial text instead of appending duplicate words.
        let words = transcript.split(separator: " ")
        let partial = words.prefix(max(1, words.count / 2)).joined(separator: " ")
        updateHandler(TranscriptionUpdate(transcript: partial, isFinal: false))
        updateHandler(TranscriptionUpdate(transcript: transcript, isFinal: false))
        return mode
    }

    func finish() throws {
        finishCount += 1
        let index = startCount - 1
        guard transcripts.indices.contains(index), handlers.indices.contains(index) else { return }
        handlers[index](TranscriptionUpdate(transcript: transcripts[index], isFinal: true))
    }

    func stop() {
        stopCount += 1
    }

    func send(_ update: TranscriptionUpdate, toSession index: Int) {
        guard handlers.indices.contains(index) else { return }
        handlers[index](update)
    }
}

@Suite("U7 voice entry pipeline")
@MainActor
struct VoiceEntryTests {

    @Test("Fixture transcripts become voice draft proposals", arguments: Fixtures.voiceFixtures)
    func fixturePipeline(stem: String) async throws {
        let expected = try Fixtures.expected(stem)
        let transcript = try Fixtures.text("\(stem).transcript.txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriber = FakeTranscriber(transcripts: [transcript])
        let viewModel = VoiceEntryViewModel(
            roster: Roster.season2026,
            transcriber: transcriber
        )

        await viewModel.prepare()
        await viewModel.startRecording()
        #expect(viewModel.transcript == transcript)
        await viewModel.stopAndParse()
        await waitForPhase(.triage, in: viewModel)

        let set = try #require(viewModel.proposalSet)
        #expect(set.provenance == .voice)
        #expect(Set(set.autoCheckNames) == Set(expected.names))
        #expect(set.plusOnes == expected.plusOnes)
        #expect(set.guestNames == (expected.guestNames ?? []))
        if let wanted = expected.distanceKm {
            let parsed = try #require(set.distanceKm)
            #expect(abs(parsed - wanted) < 0.0001)
        } else {
            #expect(set.distanceKm == nil)
        }

        let ambiguous = set.proposals.compactMap { proposal -> ExpectedFixture.Ambiguity? in
            guard case .pick(let candidates) = proposal.resolution else { return nil }
            return ExpectedFixture.Ambiguity(raw: proposal.raw, candidates: candidates)
        }
        #expect(ambiguous.map(\.raw) == expected.ambiguous.map(\.raw))
        #expect(ambiguous.map(\.candidates) == expected.ambiguous.map(\.candidates))

        let unresolved = set.proposals.compactMap { proposal -> String? in
            guard case .suggest = proposal.resolution else { return nil }
            return proposal.raw
        }
        #expect(Set(unresolved) == Set(expected.unmatchedRaw))
        #expect(viewModel.phase == .triage)
    }

    @Test("A new recording resets voice proposals without changing checklist checks")
    func rerecordLeavesDraftAlone() async throws {
        let transcriber = FakeTranscriber(transcripts: ["Col came", "Adam came"])
        let voice = VoiceEntryViewModel(
            roster: ["Aaron", "Adam", "Col"],
            transcriber: transcriber
        )
        let checklist = ChecklistViewModel(
            run: RunSnapshot(
                rowIndex: 42,
                date: "Fri, 14-Aug",
                scheduledAt: nil,
                meet: "Il Lido",
                run: "Soft Sand",
                approxKm: 7.1,
                actualKm: 7.1,
                attendees: ["Aaron"],
                plusOnes: 0,
                cachedRevision: "rev-1"
            ),
            roster: ["Aaron", "Adam", "Col"],
            engine: UnimplementedSyncEngine()
        )

        await voice.prepare()
        await voice.startRecording()
        await voice.stopAndParse()
        await waitForPhase(.triage, in: voice)
        let first = try #require(voice.proposalSet)
        checklist.applyProposals(checks: first.autoCheckNames, from: first)
        #expect(checklist.draft.checks["Aaron"] == .manual)
        #expect(checklist.draft.checks["Col"] == .voice)

        voice.returnToRecording()
        await voice.startRecording()

        #expect(voice.proposalSet == nil)
        #expect(voice.transcript == "Adam came")
        #expect(checklist.draft.checks["Aaron"] == .manual)
        #expect(checklist.draft.checks["Col"] == .voice)
    }

    @Test("Denied permission enters the Settings state and never starts audio")
    func deniedPermission() async {
        let transcriber = FakeTranscriber(authorization: .denied)
        let viewModel = VoiceEntryViewModel(roster: [], transcriber: transcriber)

        await viewModel.prepare()

        #expect(viewModel.phase == .permissionDenied)
        #expect(transcriber.startCount == 0)
    }

    @Test("First-launch permission requests map to the correct state")
    func firstLaunchPermission() async {
        let allowed = FakeTranscriber(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let allowedViewModel = VoiceEntryViewModel(roster: [], transcriber: allowed)

        await allowedViewModel.prepare()

        #expect(allowedViewModel.phase == .ready)
        #expect(allowed.requestCount == 1)

        let denied = FakeTranscriber(
            authorization: .notDetermined,
            requestedAuthorization: .denied
        )
        let deniedViewModel = VoiceEntryViewModel(roster: [], transcriber: denied)

        await deniedViewModel.prepare()

        #expect(deniedViewModel.phase == .permissionDenied)
        #expect(denied.requestCount == 1)
    }

    @Test("Returning from Settings refreshes denied permission")
    func settingsPermissionRefresh() async {
        let transcriber = FakeTranscriber(authorization: .denied)
        let viewModel = VoiceEntryViewModel(roster: [], transcriber: transcriber)

        await viewModel.prepare()
        transcriber.authorization = .authorized
        await viewModel.refreshAuthorizationIfNeeded()

        #expect(viewModel.phase == .ready)
    }

    @Test("Final updates parse automatically and errors stop recording")
    func terminalUpdates() async throws {
        let finalTranscriber = FakeTranscriber(transcripts: ["Aaron came"])
        let finalViewModel = VoiceEntryViewModel(
            roster: ["Aaron"],
            transcriber: finalTranscriber
        )
        await finalViewModel.prepare()
        await finalViewModel.startRecording()

        finalTranscriber.send(
            TranscriptionUpdate(transcript: "Aaron came", isFinal: true),
            toSession: 0
        )
        await waitForPhase(.triage, in: finalViewModel)

        #expect(finalViewModel.proposalSet?.autoCheckNames == ["Aaron"])

        let errorTranscriber = FakeTranscriber(transcripts: ["Adam"])
        let errorViewModel = VoiceEntryViewModel(
            roster: ["Adam"],
            transcriber: errorTranscriber
        )
        await errorViewModel.prepare()
        await errorViewModel.startRecording()

        errorTranscriber.send(
            TranscriptionUpdate(
                transcript: "Adam",
                isFinal: true,
                errorMessage: "Recognition unavailable"
            ),
            toSession: 0
        )

        #expect(errorViewModel.phase == .failed("Speech recognition stopped before it finished. Try again."))
        #expect(errorTranscriber.stopCount == 1)
    }

    @Test("Late callbacks cannot overwrite a replacement recording")
    func staleCallbackIsIgnored() async {
        let transcriber = FakeTranscriber(transcripts: ["Aaron came", "Adam came"])
        let viewModel = VoiceEntryViewModel(
            roster: ["Aaron", "Adam"],
            transcriber: transcriber
        )

        await viewModel.prepare()
        await viewModel.startRecording()
        viewModel.returnToRecording()
        await viewModel.startRecording()
        #expect(viewModel.transcript == "Adam came")

        transcriber.send(
            TranscriptionUpdate(transcript: "Aaron came", isFinal: true),
            toSession: 0
        )

        #expect(viewModel.phase == .recording)
        #expect(viewModel.transcript == "Adam came")
    }

    @Test("Server recognition mode is exposed for the warning UI")
    func serverRecognitionMode() async {
        let transcriber = FakeTranscriber(
            transcripts: ["Aaron came"],
            mode: .server
        )
        let viewModel = VoiceEntryViewModel(roster: ["Aaron"], transcriber: transcriber)

        await viewModel.prepare()
        await viewModel.startRecording()

        #expect(viewModel.recognitionMode == .server)
    }

    @Test("Stopping the sheet always asks the transcriber to release audio")
    func dismissalStopsAudio() async {
        let transcriber = FakeTranscriber(transcripts: ["Aaron came"])
        let viewModel = VoiceEntryViewModel(roster: ["Aaron"], transcriber: transcriber)

        await viewModel.prepare()
        await viewModel.startRecording()
        viewModel.stop()

        #expect(transcriber.stopCount == 1)
        #expect(viewModel.phase == .ready)
    }

    @Test("Transcript highlighting follows parsed name and number tokens")
    func transcriptHighlighting() {
        let tokens = VoiceTranscriptAnnotator().annotate(
            "Col and Adam came, plus two guests, we did eight point seven k"
        )
        let names = tokens.filter { $0.kind == .name }.map(\.text)
        let numbers = tokens.filter { $0.kind == .number }.map(\.text)

        #expect(names == ["Col", "Adam"])
        #expect(numbers == ["two", "eight", "point", "seven"])
    }

    private func waitForPhase(
        _ phase: VoiceEntryPhase,
        in viewModel: VoiceEntryViewModel
    ) async {
        for _ in 0..<20 where viewModel.phase != phase {
            await Task.yield()
        }
    }
}
