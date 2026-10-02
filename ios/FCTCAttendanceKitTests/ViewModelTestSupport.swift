//
//  ViewModelTestSupport.swift
//  FCTCAttendanceKitTests
//
//  Fakes shared by the U4 view-model suites.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

struct ResolutionCall: Hashable, Sendable {
    let id: UUID
    let action: ConflictResolutionAction
}

enum ViewModelTestError: LocalizedError, Equatable, Sendable {
    case offline

    var errorDescription: String? { "Offline" }
}

actor ViewModelSyncClient: SyncEngineClient {
    nonisolated var events: AsyncStream<SyncEvent> { eventBroadcaster.stream() }
    private nonisolated let eventBroadcaster = SyncEventBroadcaster()
    private(set) var addedMembers: [String] = []
    private(set) var addedRuns: [AddRunRequest] = []
    private(set) var resolutions: [ResolutionCall] = []
    private(set) var refreshCount = 0
    private var addMemberFailures: Int
    /// Holds each `addMember` open until `resumeAddMember()`.
    private let suspendAddMember: Bool
    private var addMemberContinuation: CheckedContinuation<Void, Never>?
    private var addRunFailures: Int
    private var resolutionFailures: Int
    private let suspendRefresh: Bool
    private var refreshFailures: Int
    /// Waits until cancelled, then fails the way URLSession does: a transport
    /// error, not a CancellationError.
    private let cancellableRefresh: Bool
    private var refreshContinuation: CheckedContinuation<SheetState, Never>?

    init(
        addMemberFailures: Int = 0,
        suspendAddMember: Bool = false,
        addRunFailures: Int = 0,
        resolutionFailures: Int = 0,
        suspendRefresh: Bool = false,
        refreshFailures: Int = 0,
        cancellableRefresh: Bool = false
    ) {
        self.addMemberFailures = addMemberFailures
        self.suspendAddMember = suspendAddMember
        self.addRunFailures = addRunFailures
        self.resolutionFailures = resolutionFailures
        self.suspendRefresh = suspendRefresh
        self.refreshFailures = refreshFailures
        self.cancellableRefresh = cancellableRefresh
    }

    func refreshState() async throws -> SheetState {
        refreshCount += 1
        if refreshFailures > 0 {
            refreshFailures -= 1
            throw SheetAPIError.network("Offline")
        }
        if suspendRefresh {
            return await withCheckedContinuation { refreshContinuation = $0 }
        }
        if cancellableRefresh {
            do { try await Task.sleep(for: .seconds(30)) } catch { throw SheetAPIError.network("cancelled") }
        }
        return SheetState(sheetRevision: "rev-1")
    }

    func waitUntilRefreshRequested() async {
        while refreshCount == 0 { await Task.yield() }
    }

    func resumeRefresh() {
        refreshContinuation?.resume(returning: SheetState(sheetRevision: "rev-1"))
        refreshContinuation = nil
    }

    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { UUID() }

    func enqueue(
        draft: AttendanceDraft,
        mode: SubmissionMode,
        deviceName: String?
    ) async throws -> UUID { UUID() }

    func drain() async {}

    func addMember(name: String) async throws -> AddMemberResult {
        addedMembers.append(name)
        if suspendAddMember { await withCheckedContinuation { addMemberContinuation = $0 } }
        if addMemberFailures > 0 {
            addMemberFailures -= 1
            throw ViewModelTestError.offline
        }
        return AddMemberResult(
            roster: [RosterEntry(name: name, colIndex: 1)],
            sheetRevision: "rev-2"
        )
    }

    func waitUntilAddMemberRequested() async {
        while addMemberContinuation == nil { await Task.yield() }
    }

    func resumeAddMember() {
        addMemberContinuation?.resume()
        addMemberContinuation = nil
    }

    func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        addedRuns.append(request)
        if addRunFailures > 0 {
            addRunFailures -= 1
            throw ViewModelTestError.offline
        }
        return AddRunResult(runs: [], sheetRevision: "rev-2")
    }

    func resolveConflict(
        id: UUID,
        action: ConflictResolutionAction
    ) async throws -> UUID? {
        resolutions.append(ResolutionCall(id: id, action: action))
        if resolutionFailures > 0 {
            resolutionFailures -= 1
            throw ViewModelTestError.offline
        }
        return action == .discard ? nil : UUID()
    }

    func emit(_ event: SyncEvent) {
        eventBroadcaster.yield(event)
    }
}

final class MemoryConfigPersistence: AppConfigPersisting, @unchecked Sendable {
    private var config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func load() throws -> AppConfig { config }

    func save(_ config: AppConfig) throws {
        self.config = config
    }
}

final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    var value: String?

    func readSecret() throws -> String? { value }

    func writeSecret(_ value: String) throws {
        self.value = value
    }
}
