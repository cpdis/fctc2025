import Foundation

/// Each transaction includes redirects and connection retries. Evidence is safe
/// only when every recorded transaction stopped before sending any HTTP request.
struct RequestDeliveryEvidence: Sendable {
    struct Transaction: Sendable {
        var requestStarted: Bool = false
        var requestHeaderBytes: Int64 = 0
        var requestBodyBytes: Int64 = 0
        var responseObserved: Bool = false

        var provesRequestWasNotSent: Bool {
            !requestStarted && requestHeaderBytes == 0 && requestBodyBytes == 0 && !responseObserved
        }
    }

    var redirectCount: Int
    var transactions: [Transaction]

    var provesRequestWasNotSent: Bool {
        redirectCount == 0 && !transactions.isEmpty && transactions.allSatisfy(\.provesRequestWasNotSent)
    }
}

/// URLSession collects metrics before its final task completion callback. Missing
/// metrics remain unknown, including cancellation before a transaction exists.
/// The lock protects delegate callbacks and the async caller's completed snapshot.
final class RequestDeliveryTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var evidence: RequestDeliveryEvidence?

    var provesRequestWasNotSent: Bool {
        lock.withLock { evidence?.provesRequestWasNotSent == true }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        let completed = RequestDeliveryEvidence(redirectCount: metrics.redirectCount,
            transactions: metrics.transactionMetrics.map {
                RequestDeliveryEvidence.Transaction(
                    requestStarted: $0.requestStartDate != nil,
                    requestHeaderBytes: $0.countOfRequestHeaderBytesSent,
                    requestBodyBytes: $0.countOfRequestBodyBytesSent,
                    responseObserved: $0.response != nil || $0.responseStartDate != nil ||
                        $0.countOfResponseHeaderBytesReceived != 0 || $0.countOfResponseBodyBytesReceived != 0)
            })
        lock.withLock { evidence = completed }
    }
}
