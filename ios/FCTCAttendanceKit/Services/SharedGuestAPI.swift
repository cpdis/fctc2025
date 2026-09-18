import Foundation

extension SheetAPIClient {
    public var endpointIdentity: String? { nil }
    public func getState(seasonSheetId: Int?) async throws -> SheetState {
        guard seasonSheetId == nil else { throw SheetAPIError.notImplemented }
        return try await getState()
    }
    public func sharedRead(action: String, fields: [String: GuestJSON]) async throws -> GuestJSON {
        throw SheetAPIError.notImplemented
    }
    public func perform(_ operation: SharedGuestOperation) async throws -> GuestJSON { throw SheetAPIError.notImplemented }
    public func operationStatus(id: UUID) async throws -> GuestOperationReceipt? { throw SheetAPIError.notImplemented }
}

extension SheetAPI {
    public nonisolated var endpointIdentity: String? { config.endpoint?.absoluteString }
    public func getState(seasonSheetId: Int?) async throws -> SheetState {
        var fields: [String: GuestJSON] = ["apiVersion": .number(2)]
        if let seasonSheetId { fields["seasonSheetId"] = .number(Double(seasonSheetId)) }
        return try await sharedRead(action: "getState", fields: fields).decoded()
    }
    public func sharedRead(action: String, fields: [String: GuestJSON] = [:]) async throws -> GuestJSON {
        var request = fields
        request["action"] = .string(action); request["secret"] = .string(config.secret)
        let response = try await send(GuestJSON.object(request), as: GuestJSON.self)
        try throwConflict(response)
        return response
    }
    public func perform(_ operation: SharedGuestOperation) async throws -> GuestJSON {
        let response = try await send(operation.wireRequest(secret: config.secret), as: GuestJSON.self)
        try throwConflict(response)
        return response
    }
    public func operationStatus(id: UUID) async throws -> GuestOperationReceipt? {
        let response = try await sharedRead(action: "getOperationStatus", fields: ["operationId": .string(id.uuidString.lowercased())])
        guard let value = response["operation"], value != .null else { return nil }
        return try value.decoded()
    }
    private func throwConflict(_ response: GuestJSON) throws {
        if let conflict = response["conflict"], conflict != .null { throw try conflict.decoded(SharedGuestConflict.self) }
    }
}
