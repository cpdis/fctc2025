import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Shared guest contract")
struct SharedGuestTests {
    @Test("State preserves shared identities and confirmed history across decoding")
    func sharedStateRoundTrip() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.url("guests/contract.json"))) as! [String: Any]
        let responses = fixture["responses"] as! [String: Any]
        let data = try JSONSerialization.data(withJSONObject: responses["getState"]!)
        let state = try JSONDecoder().decode(SheetState.self, from: data)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        #expect((encoded["guests"] as? [[String: Any]])?.first?["confirmedRuns"] as? Int == 11)
        #expect((encoded["runs"] as? [[String: Any]])?.first?["runId"] as? String == "00000067-2222-4222-8222-222222222222")
    }
}

@Suite("Shared operation encoding")
struct SharedOperationEncodingTests {
    @Test("Every cross-language fixture has the same canonical SHA-256 digest")
    func fixtureDigests() throws {
        let fixture = try JSONDecoder().decode(GuestJSON.self, from: Data(contentsOf: Fixtures.url("guests/contract.json")))
        guard case .object(let requests) = fixture["requests"] else { Issue.record("Missing fixture requests"); return }
        for (_, request) in requests {
            guard case .object(var fields) = request, let digest = fields["requestDigest"]?.string,
                  let id = fields["operationId"]?.string.flatMap(UUID.init(uuidString:)), let action = fields["action"]?.string else { continue }
            fields["requestDigest"] = nil; fields["operationId"] = nil; fields["action"] = nil; fields["apiVersion"] = nil
            let operation = try SharedGuestOperation(id: id, action: action, fields: fields)
            #expect(operation.digest == digest, "Digest mismatch for \(action)")
            #expect(try operation.request.canonical().contains("secret") == false)
        }
    }
    @Test("Canonical JSON matches JS Unicode, escaping and numeric thresholds")
    func canonicalEdges() throws {
        let value = GuestJSON.object(["é": .string("René /\n"), "z": .array([.number(-0), .number(1e-7), .number(1e-6), .number(1e20), .number(1e21)])])
        #expect(try value.canonical() == "{\"z\":[0,1e-7,0.000001,100000000000000000000,1e+21],\"é\":\"René /\\n\"}")
        #expect(throws: (any Error).self) { try GuestJSON.number(.infinity).canonical() }
    }
}
