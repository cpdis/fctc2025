//
//  MetricsSubscriber.swift
//  FCTCAttendance
//
//  Receives MetricKit's daily metric and diagnostic payloads and logs a summary.
//

import MetricKit
import os

final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    private static let logger = Logger(subsystem: "com.cpdis.fctc-attendance", category: "metrics")

    /// Daily metrics: log the JSON size only, the payload itself can be large.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let size = payload.jsonRepresentation().count
            Self.logger.info("Metric payload received: \(size, privacy: .public) bytes")
        }
    }

    /// Diagnostics: log which kinds arrived (crash, hang, CPU, disk write).
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpu = payload.cpuExceptionDiagnostics?.count ?? 0
            let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
            let size = payload.jsonRepresentation().count
            Self.logger.info(
                "Diagnostic payload \(size, privacy: .public) bytes: crash \(crashes, privacy: .public), hang \(hangs, privacy: .public), cpu \(cpu, privacy: .public), disk \(disk, privacy: .public)"
            )
        }
    }
}
