import Foundation

/// What a failed outbox step proves, shared by the attendance queue
/// (`drainSharedAttendance`) and the guest queue (`drainGuestOperation`).
/// Each queue maps a case onto its own persistence: attendance rows re-queue
/// or park for review, guest rows re-queue or become `.rejected`.
///
///   error                          before dispatch   after dispatch
///   requestNotSent                 unknown           notSent
///   bad_secret, busy               unknown           refused
///   bad_payload                    rejected          rejected
///   other non-retryable API error  unknown           rejected
///   decoding, internal_error       unknown           unknown
///   saved bytes do not decode      rejected          unknown
///   anything else                  unknown           unknown
///
/// Before dispatch only `bad_payload` and local coding errors are certain: a
/// receipt digest mismatch or an incomplete saved payload. Other codes there
/// come from reads, such as the receipt query, and a later drain can succeed.
enum OutboxFailure: Equatable {
    /// The transport proved the request never left. Send the same bytes again.
    case notSent
    /// The server read the request and refused it before any mutation
    /// (`bad_secret`, `busy`). Send the same bytes again later.
    case refused(SheetAPIError)
    /// A repeat gets the same answer. Stop and show the row for review.
    case rejected(message: String)
    /// Delivery is unknown or the failure may pass. Keep checking the receipt.
    case unknown

    /// - Parameter attemptedDispatch: true once the request entered the
    ///   transport. Only then can a server answer describe this request.
    init(_ error: any Error, attemptedDispatch: Bool) {
        self = attemptedDispatch ? Self.afterDispatch(error) : Self.beforeDispatch(error)
    }

    private static func afterDispatch(_ error: any Error) -> Self {
        guard let error = error as? SheetAPIError else { return .unknown }
        switch error {
        case .requestNotSent: return .notSent
        case .badSecret, .busy: return .refused(error)
        // A decode failure or a script crash says nothing about the write.
        case .decoding, .internalError: return .unknown
        default: return error.isRetryable ? .unknown : .rejected(message: UserFacingError.sync(error))
        }
    }

    private static func beforeDispatch(_ error: any Error) -> Self {
        switch error {
        case SheetAPIError.badPayload, is DecodingError, is EncodingError:
            // The same saved bytes can never succeed, and on the guest queue
            // an unresolved head blocks every later operation.
            return .rejected(message: UserFacingError.sync(error))
        default:
            return .unknown
        }
    }
}
