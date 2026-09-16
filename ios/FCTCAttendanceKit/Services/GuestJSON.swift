import Foundation
import CryptoKit

/// A small typed JSON tree makes the exact credential-free request durable.
public enum GuestJSON: Codable, Hashable, Sendable {
    case object([String: GuestJSON]), array([GuestJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([GuestJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: GuestJSON].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> GuestJSON? { if case .object(let v) = self { v[key] } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var int: Int? { if case .number(let v) = self, v.isFinite, v >= Double(Int.min), v < Double(Int.max) { Int(v) } else { nil } }
    public func decoded<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
    public static func value<T: Encodable>(_ value: T) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }
    /// JS JSON.stringify sorts object keys by UTF-16 units in the contract.
    public func canonical() throws -> String {
        switch self {
        case .object(let values):
            return "{" + (try values.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.map {
                try Self.quoted($0) + ":" + values[$0]!.canonical()
            }).joined(separator: ",") + "}"
        case .array(let values): return "[" + (try values.map { try $0.canonical() }).joined(separator: ",") + "]"
        case .string(let value): return Self.quoted(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .number(let value): return try Self.numberText(value)
        }
    }
    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 0..<32: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
    private static func numberText(_ value: Double) throws -> String {
        guard value.isFinite else { throw SheetAPIError.badPayload(message: "Use finite numbers.") }
        if value == 0 { return "0" }
        // Swift and JavaScript use shortest round-tripping digits; normalize their
        // exponent formatting and JavaScript's decimal/exponent thresholds.
        let negative = value < 0, magnitude = abs(value)
        let parts = String(magnitude).lowercased().split(separator: "e")
        let exponent = parts.count == 2 ? Int(parts[1])! : 0
        let mantissa = String(parts[0])
        let decimalIndex = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count
        var digits = mantissa.replacingOccurrences(of: ".", with: "")
        var point = decimalIndex + exponent
        while digits.first == "0" { digits.removeFirst(); point -= 1 }
        while digits.last == "0" { digits.removeLast() }
        let sign = negative ? "-" : ""
        if magnitude >= 1e-6 && magnitude < 1e21 {
            if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
            if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
            let split = digits.index(digits.startIndex, offsetBy: point)
            return sign + digits[..<split] + "." + digits[split...]
        }
        let power = point - 1
        let tail = digits.dropFirst()
        return sign + String(digits.prefix(1)) + (tail.isEmpty ? "" : "." + tail) + "e" + (power >= 0 ? "+" : "") + String(power)
    }
}

public struct SharedGuestOperation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var request: GuestJSON
    public var digest: String
    public init(id: UUID = UUID(), action: String, fields: [String: GuestJSON]) throws {
        guard fields["secret"] == nil, fields["requestDigest"] == nil,
              fields["operationId"] == nil, fields["action"] == nil, fields["apiVersion"] == nil else {
            throw SheetAPIError.badPayload(message: "Operation fields contain reserved keys.")
        }
        let allowed: [String: Set<String>] = [
            "createGuest": ["guestId", "displayName", "confirmDistinct"],
            "renameGuest": ["guestId", "displayName", "baseGuestRevision"],
            "submitAttendance": ["spreadsheetId", "seasonSheetId", "runId", "rowIndex", "expectedDate", "expectedRun", "attendees", "namedGuestIds", "unnamedGuests", "actualKm", "mode", "baseRevision"],
            "importGuestHistory": ["guestId", "baseGuestRevision", "entries", "baseRevision"],
            "commitPromotion": ["guestId", "memberName", "targetMode", "previewToken"],
            "addMember": ["name", "seasonSheetId", "baseRevision"],
            "addRun": ["date", "meet", "run", "approxKm", "spreadsheetId", "seasonSheetId", "baseRevision"]
        ]
        guard let permitted = allowed[action], Set(fields.keys).isSubset(of: permitted) else {
            throw SheetAPIError.badPayload(message: "Unsupported operation fields.")
        }
        var values = fields
        values["apiVersion"] = .number(2); values["action"] = .string(action)
        values["operationId"] = .string(id.uuidString.lowercased())
        self.id = id; request = .object(values)
        digest = SHA256.hash(data: Data(try request.canonical().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var action: String { request["action"]?.string ?? "" }
    public func wireRequest(secret: String) -> GuestJSON {
        guard case .object(var values) = request else { return .null }
        values["secret"] = .string(secret); values["requestDigest"] = .string(digest)
        return .object(values)
    }
}

public struct GuestOperationReceipt: Codable, Hashable, Sendable {
    public var operationId: String
    public var requestDigest: String
    public var status: String
    public var response: GuestJSON?

    public init(operationId: String, requestDigest: String, status: String, response: GuestJSON? = nil) {
        self.operationId = operationId
        self.requestDigest = requestDigest
        self.status = status
        self.response = response
    }
}
