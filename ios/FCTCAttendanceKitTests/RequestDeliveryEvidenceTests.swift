import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Request delivery evidence")
struct RequestDeliveryEvidenceTests {
    @Test("Missing or empty metrics never authorize another dispatch")
    func missingMetrics() {
        #expect(!RequestDeliveryTracker().provesRequestWasNotSent)
        #expect(!RequestDeliveryEvidence(redirectCount: 0, transactions: []).provesRequestWasNotSent)
        #expect(RequestDeliveryEvidence(redirectCount: 0, transactions: [.init()]).provesRequestWasNotSent)
    }

    @Test("Any started transaction, bytes, response, or redirect makes delivery unknown")
    func deliverySignals() {
        let sent: [RequestDeliveryEvidence.Transaction] = [
            .init(requestStarted: true), .init(requestHeaderBytes: 1),
            .init(requestBodyBytes: 1), .init(responseObserved: true)
        ]
        for transaction in sent {
            // The last transaction may fail before sending while an earlier one
            // committed successfully. Check the complete transaction chain.
            #expect(!RequestDeliveryEvidence(redirectCount: 0,
                transactions: [transaction, .init()]).provesRequestWasNotSent)
        }
        #expect(!RequestDeliveryEvidence(redirectCount: 1, transactions: [.init()]).provesRequestWasNotSent)
    }

    @Test("Network error codes without completed metrics cannot prove non-delivery",
          arguments: [URLError.Code.timedOut, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost])
    func bareNetworkError(code: URLError.Code) async {
        let api = SheetAPI(config: configuredAPI, transport: UnobservedFailureTransport(code: code))
        do {
            _ = try await api.getState()
            Issue.record("Expected the transport error")
        } catch let error as SheetAPIError {
            #expect(error.code == "network")
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}

private struct UnobservedFailureTransport: HTTPTransport {
    let code: URLError.Code
    func post(_ body: Data) async throws -> Data { throw URLError(code) }
}
