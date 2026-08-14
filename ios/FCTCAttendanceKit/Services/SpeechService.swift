//
//  SpeechService.swift
//  FCTCAttendanceKit
//
//  U7 — live speech recognition behind a small test seam. The service stays on the
//  main actor because AVAudioEngine and SFSpeechRecognizer have mutable session state.
//  Their callbacks can arrive elsewhere, so only Sendable values cross back to it.
//

@preconcurrency import AVFAudio
import Foundation
import OSLog
@preconcurrency import Speech

public enum TranscriberAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public enum TranscriptionMode: Equatable, Sendable {
    case onDevice
    case server
}

public struct TranscriptionUpdate: Equatable, Sendable {
    public var transcript: String
    public var isFinal: Bool
    public var errorMessage: String?

    public init(transcript: String, isFinal: Bool, errorMessage: String? = nil) {
        self.transcript = transcript
        self.isFinal = isFinal
        self.errorMessage = errorMessage
    }
}

/// The voice workflow depends on this protocol, not Speech.framework. Tests replay
/// fixture transcripts through a fake implementation.
@MainActor
public protocol Transcriber: AnyObject {
    func authorizationStatus() async -> TranscriberAuthorization
    func requestAuthorization() async -> TranscriberAuthorization
    func start(
        updateHandler: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionMode
    func finish() throws
    func stop()
}

public enum SpeechServiceError: LocalizedError, Sendable, Equatable {
    case permissionRequired
    case recognizerUnavailable
    case audioInputUnavailable
    case audioSession(String)
    case audioSessionDeactivation(String)

    public var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Allow microphone and speech access before dictating attendance."
        case .recognizerUnavailable:
            "Speech recognition is not available right now."
        case .audioInputUnavailable:
            "The microphone did not provide a usable audio format."
        case .audioSession(let message):
            "The microphone could not start: \(message)"
        case .audioSessionDeactivation(let message):
            "The microphone could not stop cleanly: \(message)"
        }
    }
}

/// SFSpeechAudioBufferRecognitionRequest is explicitly designed to receive buffers
/// from the audio tap. The SDK type is not Sendable, so this narrow box documents the
/// one cross-thread use and keeps all other recognition state main-actor isolated.
private final class AudioRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

@MainActor
public final class SpeechService: Transcriber {
    private static let logger = Logger(
        subsystem: "com.fctc.attendance",
        category: "SpeechService"
    )

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var requestBox: AudioRequestBox?
    private var updateHandler: (@MainActor @Sendable (TranscriptionUpdate) -> Void)?
    private var hasInputTap = false
    private var sessionID: UUID?

    public init() {}

    public func authorizationStatus() async -> TranscriberAuthorization {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission

        let speechAuthorization = Self.authorization(from: speech)
        guard speechAuthorization == .authorized else { return speechAuthorization }

        switch microphone {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    public func requestAuthorization() async -> TranscriberAuthorization {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let speechAuthorization = Self.authorization(from: speechStatus)
        guard speechAuthorization == .authorized else { return speechAuthorization }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        return microphoneGranted ? .authorized : .denied
    }

    public func start(
        updateHandler: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionMode {
        guard await authorizationStatus() == .authorized else {
            throw SpeechServiceError.permissionRequired
        }

        stop()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU")),
              recognizer.isAvailable
        else {
            throw SpeechServiceError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        let mode: TranscriptionMode = recognizer.supportsOnDeviceRecognition
            ? .onDevice
            : .server
        request.requiresOnDeviceRecognition = mode == .onDevice

        let box = AudioRequestBox(request)
        let sessionID = UUID()
        self.requestBox = box
        self.updateHandler = updateHandler
        self.sessionID = sessionID

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let isTerminal = result?.isFinal == true || error != nil
            let update = TranscriptionUpdate(
                transcript: result?.bestTranscription.formattedString ?? "",
                isFinal: isTerminal,
                // A recognizer can return its final result and a terminal error
                // together. Preserve the usable result and only surface lone errors.
                errorMessage: result == nil ? error?.localizedDescription : nil
            )
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                if !update.transcript.isEmpty || update.errorMessage != nil {
                    self.updateHandler?(update)
                }
                if update.isFinal || update.errorMessage != nil {
                    self.stop()
                }
            }
        }

        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechServiceError.audioInputUnavailable
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                box.request.append(buffer)
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            return mode
        } catch {
            stop()
            if let speechError = error as? SpeechServiceError { throw speechError }
            throw SpeechServiceError.audioSession(error.localizedDescription)
        }
    }

    /// Stop accepting microphone buffers, but let Speech finish the audio already
    /// submitted. The final callback owns the transition to full teardown.
    public func finish() throws {
        guard recognitionTask != nil else { return }
        try stopAudioCapture()
    }

    /// Idempotent teardown. Every stop, dismissal, final result, and background event
    /// reaches this method so the microphone indicator cannot remain active.
    public func stop() {
        sessionID = nil
        do {
            try stopAudioCapture()
        } catch {
            Self.logger.error(
                "Audio session deactivation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox = nil
        updateHandler = nil
    }

    private func stopAudioCapture() throws {
        let hadActiveSession = audioEngine.isRunning
            || hasInputTap
            || requestBox != nil
            || recognitionTask != nil
        guard hadActiveSession else { return }

        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        requestBox?.request.endAudio()

        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            throw SpeechServiceError.audioSessionDeactivation(error.localizedDescription)
        }
    }

    private static func authorization(
        from status: SFSpeechRecognizerAuthorizationStatus
    ) -> TranscriberAuthorization {
        switch status {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .restricted
        }
    }
}
