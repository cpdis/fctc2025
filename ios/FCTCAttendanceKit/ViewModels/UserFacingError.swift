//
//  UserFacingError.swift
//  FCTCAttendanceKit
//
//  One vocabulary for UI errors. Framework and server diagnostics never become
//  club-facing copy by accident.
//

import Foundation

public enum SyncBannerKind: Hashable, Sendable {
    case success
    case offline
    case parked
    case conflict
    case authentication
    case error
}

public struct SyncBanner: Hashable, Sendable {
    public var kind: SyncBannerKind
    public var message: String

    public init(kind: SyncBannerKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public enum UserFacingError {
    public static let offline = "The sheet is offline. Your submission is safe in the outbox."
    public static let busy = "The sheet is busy with another update. Wait a moment and try again."
    public static let authentication = "The shared secret was rejected. Open Settings and scan a new setup code."
    public static let conflict = "The sheet changed. Review the conflict in the outbox."
    public static let genericSync = "The app could not update the sheet. Try again from the outbox."
    public static let voiceStopped = "Speech recognition stopped before it finished. Try again."

    public static func sync(_ error: any Error) -> String {
        guard let sheetError = error as? SheetAPIError else { return genericSync }
        switch sheetError {
        case .notConfigured:
            return "Finish setup before you connect to the sheet."
        case .network:
            return offline
        case .badSecret:
            return authentication
        case .duplicateMember:
            return "That person is already on the roster. Refresh and try again."
        case .badPayload:
            return "The sheet could not accept those details. Review them and try again."
        case .sheetUnreadable:
            return "The season sheet could not be read. Check the season setting in Apps Script."
        case .busy:
            return busy
        case .unknownAction, .internalError, .server, .decoding, .notImplemented:
            return genericSync
        }
    }

    public static func voice(_ error: any Error) -> String {
        guard let speechError = error as? SpeechServiceError else {
            return "The app could not understand that recording. Try again or use the checklist."
        }
        switch speechError {
        case .permissionRequired:
            return "Allow microphone and speech access before dictating attendance."
        case .recognizerUnavailable:
            return "Speech recognition is not available right now. Try again or use the checklist."
        case .audioInputUnavailable:
            return "The microphone is not available. Close other audio apps and try again."
        case .audioSession:
            return "The microphone could not start. Close other audio apps and try again."
        case .audioSessionDeactivation:
            return "The microphone stopped, but iOS did not release it cleanly. Close and reopen this screen."
        }
    }

    public static func screenshot(_ error: any Error) -> String {
        switch error {
        case is PollScreenshotParserError:
            return "The screenshot could not be prepared. Choose a clear View votes screenshot and try again."
        default:
            return "The app could not read that screenshot. Choose a clear View votes screenshot and try again."
        }
    }
}
