//
//  SyncBanner.swift
//  FCTCAttendanceKit
//
//  The one mapping from a sync outcome to its club-facing copy (CA-28). Home,
//  Outbox, Checklist and the run picker all read their messages from here, so
//  the same event never says two different things on two screens.
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

extension SyncBanner {
    public static let syncedMessage = "Attendance synced."

    /// The banner for a sync outcome, or nil for an event that carries none
    /// (`queued`, `rosterRefreshed`, `syncActivity`). Screens that show only
    /// problems skip the `.success` kind; see `isProblem`.
    public init?(event: SyncEvent) {
        switch event {
        case .written:
            self.init(kind: .success, message: Self.syncedMessage)
        case .conflict:
            self.init(kind: .conflict, message: UserFacingError.conflict)
        case .parked(_, let message):
            // The engine parks an unsent row with the offline copy; any other
            // parked message is a refusal the organiser has to wait out.
            self.init(kind: message == UserFacingError.offline ? .offline : .parked, message: message)
        case .authenticationRequired:
            self.init(kind: .authentication, message: UserFacingError.authentication)
        case .failed(_, let message), .serviceFailed(let message):
            self.init(kind: .error, message: message)
        case .queued, .rosterRefreshed, .syncActivity:
            return nil
        }
    }

    /// True for every outcome that needs the organiser's attention.
    public var isProblem: Bool { kind != .success }
}
