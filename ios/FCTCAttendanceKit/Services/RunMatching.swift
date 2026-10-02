//
//  RunMatching.swift
//  FCTCAttendanceKit
//
//  Which server run a saved submission targets (CA-32). The Outbox diff and
//  the engine's conflict resolution both ask here, so they always compare
//  against the same run.
//

import Foundation

/// The fields a submission carries to say which run it writes to.
/// `PendingSubmission` (the store row) and `PendingSubmissionSnapshot` (what
/// screens see) both have them already.
protocol RunTargeting {
    var runIdentity: RunIdentity? { get }
    var expectedDate: String { get }
    var expectedRun: String { get }
    var rowIndex: Int { get }
}

extension PendingSubmission: RunTargeting {}
extension PendingSubmissionSnapshot: RunTargeting {}

extension SheetState {
    /// The run a submission targets:
    ///
    ///   has identity? yes -> the run with that identity, or nil. Two runs can
    ///                        share a date and name; only the identity tells
    ///                        them apart, and the engine refuses a shared row
    ///                        whose identity is gone, so no guess is made.
    ///                 no  -> date plus run name, then the saved row index
    ///                        (a legacy row whose run moved or was renamed).
    func run(matching submission: some RunTargeting) -> RunRecord? {
        if let identity = submission.runIdentity {
            return runs.first { $0.identity == identity }
        }
        return runs.first { $0.date == submission.expectedDate && $0.run == submission.expectedRun }
            ?? runs.first { $0.rowIndex == submission.rowIndex }
    }
}
