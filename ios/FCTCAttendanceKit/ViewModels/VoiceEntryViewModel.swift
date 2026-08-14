//
//  VoiceEntryViewModel.swift
//  FCTCAttendanceKit
//
//  U7 — owns the sheet's permission, recording, parse, and triage state. It never
//  mutates AttendanceDraft. The caller applies the confirmed DraftProposalSet through
//  ChecklistViewModel.applyProposals, which owns all precedence rules.
//

import Foundation
import Observation

public enum VoiceEntryPhase: Equatable, Sendable {
    case checkingPermissions
    case ready
    case recording
    case processing
    case triage
    case permissionDenied
    case restricted
    case failed(String)
}

@MainActor
@Observable
public final class VoiceEntryViewModel {
    public private(set) var phase: VoiceEntryPhase = .checkingPermissions
    public private(set) var transcript = ""
    public private(set) var proposalSet: DraftProposalSet?
    public private(set) var recognitionMode: TranscriptionMode?

    @ObservationIgnored private var roster: [String]
    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let extractor: any NameExtractor
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var finalizationTask: Task<Void, Never>?

    public init(
        roster: [String],
        transcriber: any Transcriber,
        extractor: any NameExtractor = VoiceEntryExtractor()
    ) {
        self.roster = roster
        self.transcriber = transcriber
        self.extractor = extractor
    }

    public func updateRoster(_ roster: [String]) {
        self.roster = roster
    }

    public func prepare() async {
        phase = .checkingPermissions
        let current = await transcriber.authorizationStatus()
        let resolved = current == .notDetermined
            ? await transcriber.requestAuthorization()
            : current
        setPhase(for: resolved)
    }

    public func refreshAuthorizationIfNeeded() async {
        guard phase == .permissionDenied || phase == .restricted else { return }
        await prepare()
    }

    public func startRecording() async {
        if phase == .permissionDenied || phase == .restricted
            || phase == .checkingPermissions {
            await prepare()
        }
        guard phase == .ready || phase.isRetryable else { return }

        // A new recording replaces all voice-session state. The checklist draft lives
        // outside this object, so manual and already-applied checks remain untouched.
        transcript = ""
        proposalSet = nil
        recognitionMode = nil
        finalizationTask?.cancel()
        let recordingID = UUID()
        self.recordingID = recordingID
        phase = .recording

        do {
            recognitionMode = try await transcriber.start { [weak self] update in
                self?.receive(update, for: recordingID)
            }
        } catch {
            self.recordingID = nil
            transcriber.stop()
            phase = .failed(error.localizedDescription)
        }
    }

    public func stopAndParse() async {
        guard phase == .recording else { return }
        phase = .processing

        do {
            try transcriber.finish()
            scheduleFinalizationFallback()
        } catch {
            recordingID = nil
            transcriber.stop()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Leave triage without applying it. The transcript stays visible until the next
    /// recording starts, at which point it is replaced.
    public func returnToRecording() {
        finalizationTask?.cancel()
        recordingID = nil
        transcriber.stop()
        proposalSet = nil
        recognitionMode = nil
        phase = .ready
    }

    /// Called from dismissal and every non-active scene transition.
    public func stop() {
        finalizationTask?.cancel()
        recordingID = nil
        transcriber.stop()
        if phase == .recording || phase == .processing {
            phase = .ready
        }
    }

    private func receive(_ update: TranscriptionUpdate, for recordingID: UUID) {
        guard self.recordingID == recordingID,
              phase == .recording || phase == .processing
        else { return }
        if let message = update.errorMessage {
            finalizationTask?.cancel()
            self.recordingID = nil
            transcriber.stop()
            phase = .failed(message)
            return
        }
        if transcript != update.transcript {
            transcript = update.transcript
        }
        if update.isFinal {
            phase = .processing
            Task { @MainActor [weak self] in
                await self?.parseTranscript(for: recordingID)
            }
        }
    }

    private func scheduleFinalizationFallback() {
        guard let recordingID else { return }
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.parseTranscript(for: recordingID)
        }
    }

    private func parseTranscript(for recordingID: UUID) async {
        guard self.recordingID == recordingID, phase == .processing else { return }
        finalizationTask?.cancel()
        finalizationTask = nil
        self.recordingID = nil
        transcriber.stop()

        do {
            let result = try await extractor.extract(from: transcript, context: .voice)
            proposalSet = DraftProposalSet(
                entities: result.entities,
                matcher: NameMatcher(roster: roster),
                provenance: .voice
            )
            phase = .triage
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func setPhase(for authorization: TranscriberAuthorization) {
        switch authorization {
        case .authorized:
            phase = .ready
        case .notDetermined:
            phase = .checkingPermissions
        case .denied:
            phase = .permissionDenied
        case .restricted:
            phase = .restricted
        }
    }
}

private extension VoiceEntryPhase {
    var isRetryable: Bool {
        if case .failed = self { return true }
        return false
    }
}
