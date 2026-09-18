import Foundation
import Observation

/// One editor handles a new correction and a correction rejected by the sheet.
/// Only a confirmed result changes the displayed name; attendance is never saved here.
@MainActor @Observable
public final class GuestNameViewModel {
    public var name: String
    public private(set) var guest: SharedGuest?
    public private(set) var operation: GuestOperationSnapshot?
    public private(set) var operationId: UUID?
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    public private(set) var savedGuest: SharedGuest?
    public private(set) var finished = false
    public private(set) var reviewReady = false
    @ObservationIgnored private let engine: any SyncEngineClient
    @ObservationIgnored private var savedChangePending = false
    private var loadedIntent = false

    public init(guest: SharedGuest? = nil, operationId: UUID? = nil, engine: any SyncEngineClient) {
        self.guest = guest; name = guest?.displayName ?? ""
        self.operationId = operationId; self.engine = engine
    }

    public var needsReview: Bool { operation?.phase == .conflict || operation?.phase == .rejected }
    public var isPending: Bool { operation?.phase == .queued || operation?.phase == .checking }
    public var canSave: Bool {
        !isWorking && !finished && reviewReady && guest?.isActive == true &&
        (operationId == nil || needsReview) && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func load() async {
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil
        do { try await refreshEditor() }
        catch { errorMessage = UserFacingError.sync(error) }
        await finishWork()
    }

    private func refreshEditor() async throws {
        try await readOperation()
        guard !finished else { return }
        if let id = operation?.guestId ?? guest?.guestId {
            guest = try await engine.guestHistory(id: id).guest
            reviewReady = true
            if !loadedIntent { name = guest?.displayName ?? name; loadedIntent = true }
        } else {
            throw SheetAPIError.badPayload(message: "This name change could not be found. Reopen the guest and try again.")
        }
    }

    public func save() async {
        guard canSave, let guest else { return }
        isWorking = true; errorMessage = nil
        do {
            let corrected = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let operationId {
                self.operationId = try await engine.replaceGuestRename(id: operationId, guest: guest, name: corrected)
            } else {
                operationId = try await engine.renameGuest(guest, name: corrected)
            }
            reviewReady = false
            try await readOperation()
            // A second organiser can change the name while this editor is open.
            // Keep the typed correction and show the newly saved name beside it.
            if needsReview {
                self.guest = try await engine.guestHistory(id: guest.guestId).guest
                reviewReady = true
            }
        } catch { errorMessage = UserFacingError.sync(error) }
        await finishWork()
    }

    public func keepSavedName() async {
        guard !isWorking, needsReview, let operationId else { return }
        isWorking = true; errorMessage = nil
        do {
            try await engine.discardGuestRename(id: operationId)
            finished = true
        } catch { errorMessage = UserFacingError.sync(error) }
        await finishWork()
    }

    /// Checking reads the original request's outcome. It cannot create a rename.
    public func check() async {
        guard !isWorking, operationId != nil, !finished else { return }
        isWorking = true; errorMessage = nil
        await engine.drain()
        do { try await refreshEditor() }
        catch { errorMessage = UserFacingError.sync(error) }
        await finishWork()
    }

    /// SwiftData changes call this when a background save completes.
    public func observeSavedChange() async {
        guard operationId != nil, !finished else { return }
        savedChangePending = true
        guard !isWorking else { return }
        isWorking = true
        await finishWork()
    }

    /// Coalesce notifications received during a suspended read. Keep one worker
    /// until the latest outcome is read, even when the previous history read failed.
    private func finishWork() async {
        defer { isWorking = false; savedChangePending = false }
        while savedChangePending && !finished {
            savedChangePending = false
            do {
                try await refreshEditor()
                errorMessage = nil
            } catch { errorMessage = UserFacingError.sync(error) }
        }
    }

    private func readOperation() async throws {
        guard let operationId else { return }
        guard let value = try await engine.guestOperation(id: operationId), value.action == "renameGuest" else {
            throw SheetAPIError.badPayload(message: "This name change could not be found. Reopen the guest and try again.")
        }
        operation = value
        if !loadedIntent, let proposed = value.proposedName {
            name = proposed; loadedIntent = true
        }
        if value.phase == .completed {
            // The mutation response updates this cache before publishing completion.
            // Do not wait for a separate run sync or replace the organiser's draft.
            let guests = try await engine.sharedGuests()
            let id = value.guestId ?? guest?.guestId
            savedGuest = guests.first { $0.guestId == id }
            if savedGuest == nil { savedGuest = try value.response?["guest"]?.decoded() }
            guard savedGuest != nil else {
                throw SheetAPIError.badPayload(message: "The name saved. Refresh the guest to load it.")
            }
            finished = true
        } else if value.phase == .superseded {
            finished = true
        }
    }
}
