//
//  UITestSupport.swift
//  FCTCAttendance
//
//  Deterministic, in-memory sheet behavior used only when XCUITest launches with
//  `-ui-testing`. Production launches never construct these values.
//

import CoreGraphics
import FCTCAttendanceKit
import Foundation
import SwiftData

enum UITestSupport {
    private static let coachPreferenceKey = "screenshotImport.hideCoach"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    static var hasScreenshotImportFixture: Bool {
        screenshotFixture != nil
    }

    static var shouldSkipScreenshotCoach: Bool {
        guard let screenshotFixture else { return false }
        return screenshotFixture != .coach
    }

    static func prepareLaunch() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-reset-screenshot-coach") else {
            return
        }
        UserDefaults.standard.removeObject(forKey: coachPreferenceKey)
    }

    static func screenshotParser() -> PollScreenshotParser {
        guard let screenshotFixture else { return PollScreenshotParser() }
        return PollScreenshotParser(
            recognizer: UITestTextRecognizer(lines: screenshotFixture.lines)
        )
    }

    static func screenshotImages() -> [CGImage] {
        guard hasScreenshotImportFixture,
              let context = CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else { return [] }
        return [image]
    }

    private static var screenshotFixture: ScreenshotFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-screenshot-nameless") { return .nameless }
        if arguments.contains("-ui-screenshot-coach") { return .coach }
        if arguments.contains("-ui-screenshot-import") { return .detail }
        return nil
    }

    @MainActor
    static func makeRuntime(modelContainer: ModelContainer) -> AppRuntime {
        let config = AppConfig(
            endpoint: URL(string: "https://ui-test.invalid/exec"),
            secret: "ui-test-secret",
            deviceName: "UI Test iPhone"
        )
        let persistence = UITestConfigPersistence(config: config)
        // "-ui-offline" simulates no connectivity by never draining automatically:
        // a first-write-fails fake races any refresh-triggered drain, which re-sends
        // and hides the queued row before the test can look at it. The outbox's
        // manual Retry is the recovery path under test.
        let offline = ProcessInfo.processInfo.arguments.contains("-ui-offline")
        let engine = SyncEngine(
            modelContainer: modelContainer,
            api: UITestSheetAPI(),
            retryPolicy: RetryPolicy(maxAttempts: 1),
            automaticallyDrains: !offline
        )
        return AppRuntime(
            modelContainer: modelContainer,
            configPersistence: persistence,
            engineOverride: engine,
            configOverride: config
        )
    }
}

private enum ScreenshotFixture {
    case detail
    case nameless
    case coach

    var lines: [String] {
        switch self {
        case .detail, .coach:
            [
                "9:41", "Poll", "FCTC", "Friday run?", "Select one or more",
                "Yes ✓ 3 votes", "Aaron", "Dan", "Priya B", "No 1 vote", "Col",
            ]
        case .nameless:
            [
                "9:41", "Poll", "FCTC", "Friday run?", "Select one or more",
                "Yes 3 votes", "No 1 vote", "4 votes",
            ]
        }
    }
}
private final class UITestConfigPersistence: AppConfigPersisting, @unchecked Sendable {
    private var config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func load() throws -> AppConfig { config }

    func save(_ config: AppConfig) throws {
        self.config = config
    }
}

private actor UITestSheetAPI: SheetAPIClient {
    private var state: SheetState
    private var writeAttempts = 0

    init() {
        state = SheetState(
            roster: [
                RosterEntry(name: "Aaron", colIndex: 6),
                RosterEntry(name: "Col", colIndex: 7),
                RosterEntry(name: "Dan", colIndex: 8),
                RosterEntry(name: "Dan B", colIndex: 9),
            ],
            runs: [
                RunRecord(
                    rowIndex: 42,
                    date: "Fri, 14-Aug",
                    meet: "Il Lido",
                    run: "Soft Sand",
                    approxKm: 7.1,
                    actualKm: 7.1,
                    attendees: ["Col"]
                ),
                RunRecord(
                    rowIndex: 43,
                    date: "Thu, 13-Aug",
                    meet: "Tompkins Park",
                    run: "River Loop",
                    approxKm: 8.2
                ),
            ],
            seasonYear: 2026,
            sheetRevision: "ui-rev-1"
        )
    }

    func getState() async throws -> SheetState { state }

    func submitAttendance(
        _ submission: AttendanceSubmission
    ) async throws -> SubmissionOutcome {
        writeAttempts += 1
        guard let index = state.runs.firstIndex(where: { $0.rowIndex == submission.rowIndex }) else {
            throw SheetAPIError.badPayload(message: "Unknown UI-test row.")
        }
        switch submission.mode {
        case .merge:
            state.runs[index].attendees = Array(
                Set(state.runs[index].attendees).union(submission.attendees)
            ).sorted(by: Member.sheetOrder)
            if let plusOnes = submission.plusOnes {
                state.runs[index].plusOnes = max(state.runs[index].plusOnes, plusOnes)
            }
        case .overwrite:
            state.runs[index].attendees = submission.attendees.sorted(by: Member.sheetOrder)
            if let plusOnes = submission.plusOnes {
                state.runs[index].plusOnes = plusOnes
            }
        }
        if let actualKm = submission.actualKm { state.runs[index].actualKm = actualKm }
        state.sheetRevision = "ui-rev-\(writeAttempts + 1)"
        return .written(cells: 1, sheetRevision: state.sheetRevision)
    }

    func addMember(name: String) async throws -> AddMemberResult {
        if !state.roster.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            state.roster.append(RosterEntry(name: name, colIndex: state.roster.count + 6))
            state.roster.sort { Member.sheetOrder($0.name, $1.name) }
            for index in state.roster.indices { state.roster[index].colIndex = index + 6 }
        }
        state.sheetRevision += "-member"
        return AddMemberResult(roster: state.roster, sheetRevision: state.sheetRevision)
    }

    func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        let row = (state.runs.map(\.rowIndex).max() ?? 1) + 1
        state.runs.append(
            RunRecord(
                rowIndex: row,
                date: request.date,
                meet: request.meet,
                run: request.run,
                approxKm: request.approxKm
            )
        )
        state.sheetRevision += "-run"
        return AddRunResult(runs: state.runs, sheetRevision: state.sheetRevision)
    }
}

/// Fixture OCR lives behind the same seam as Vision. The lines include one strong
/// match, one real roster collision and one unmatched name for the triage UI test.
private actor UITestTextRecognizer: TextRecognizer {
    private let lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        lines.enumerated().reversed().map { index, line in
            RecognizedTextLine(
                text: line,
                boundingBox: CGRect(
                    x: 0,
                    y: 1 - (CGFloat(index + 1) / CGFloat(lines.count + 1)),
                    width: 0.8,
                    height: 0.02
                )
            )
        }
    }
}
