//
//  SetupCodeTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("U8 setup-code import")
struct SetupCodeTests {

    @Test("A setup link becomes an app configuration")
    func validSetupLink() throws {
        let payload = """
        fctc-attendance://setup?endpoint=https%3A%2F%2Fscript.google.com%2Fmacros%2Fs%2Fexample%2Fexec\
        &secret=test-secret-not-real&device=Run%20phone
        """

        let config = try SetupCodeParser().parse(payload)

        #expect(config.endpoint?.absoluteString == "https://script.google.com/macros/s/example/exec")
        #expect(config.secret == "test-secret-not-real")
        #expect(config.deviceName == "Run phone")
    }

    @Test("A setup link without a device name still configures the app")
    func setupLinkWithoutDevice() throws {
        let payload = "fctc-attendance://setup?endpoint=https%3A%2F%2Fexample.test%2Fexec&secret=test-secret-not-real"

        let config = try SetupCodeParser().parse(payload)

        #expect(config.endpoint?.absoluteString == "https://example.test/exec")
        #expect(config.deviceName == nil)
    }

    @Test("A setup link missing the secret is rejected")
    func setupLinkNeedsSecret() {
        #expect(throws: SetupCodeError.invalidPayload) {
            try SetupCodeParser().parse("fctc-attendance://setup?endpoint=https%3A%2F%2Fexample.test%2Fexec")
        }
    }

    @Test("Only the setup host is honoured")
    func rejectsUnknownHost() {
        #expect(throws: SetupCodeError.invalidPayload) {
            try SetupCodeParser().parse(
                "fctc-attendance://elsewhere?endpoint=https%3A%2F%2Fexample.test%2Fexec&secret=test-secret-not-real"
            )
        }
    }

    @Test("Setup links are recognised by scheme alone")
    func recognisesSetupLinks() {
        #expect(SetupCodeParser.isSetupLink("fctc-attendance://setup?secret=x"))
        #expect(SetupCodeParser.isSetupLink("FCTC-Attendance://setup?secret=x"))
        #expect(!SetupCodeParser.isSetupLink("https://script.google.com/macros/s/example/exec"))
        #expect(!SetupCodeParser.isSetupLink(#"{"endpoint":"https://example.test/exec"}"#))
    }

    @Test("Codes handed out before the scheme existed still import")
    func legacyJSONPayload() throws {
        let payload = """
        {"endpoint":"https://script.google.com/macros/s/example/exec","secret":"test-secret-not-real","deviceName":"Run phone"}
        """

        let config = try SetupCodeParser().parse(payload)

        #expect(config.endpoint?.absoluteString == "https://script.google.com/macros/s/example/exec")
        #expect(config.secret == "test-secret-not-real")
        #expect(config.deviceName == "Run phone")
    }

    @Test("Setup codes require HTTPS endpoints")
    func rejectsHTTP() {
        let payload = """
        {"endpoint":"http://example.test/exec","secret":"test-secret-not-real","deviceName":"Run phone"}
        """

        #expect(throws: SetupCodeError.invalidEndpoint) {
            try SetupCodeParser().parse(payload)
        }
        #expect(throws: SetupCodeError.invalidEndpoint) {
            try SetupCodeParser().parse(
                "fctc-attendance://setup?endpoint=http%3A%2F%2Fexample.test%2Fexec&secret=test-secret-not-real"
            )
        }
    }

    @Test("Setup codes reject blank secrets")
    func rejectsBlankSecret() {
        let payload = """
        {"endpoint":"https://example.test/exec","secret":"   ","deviceName":"Run phone"}
        """

        #expect(throws: SetupCodeError.emptySecret) {
            try SetupCodeParser().parse(payload)
        }
    }

    @Test("A blank device name is stored as no name")
    func trimsDeviceName() throws {
        let payload = """
        {"endpoint":"https://example.test/exec","secret":"test-secret-not-real","deviceName":"  "}
        """

        let config = try SetupCodeParser().parse(payload)

        #expect(config.deviceName == nil)
    }

    @Test("Malformed JSON has a human-readable setup error")
    func rejectsMalformedJSON() {
        #expect(throws: SetupCodeError.invalidPayload) {
            try SetupCodeParser().parse("not json")
        }
        #expect(SetupCodeError.invalidPayload.localizedDescription == "This setup code is not valid. Generate a new code and try again.")
    }
}

/// Every Apps Script endpoint shares one host, so the setup-link confirmation
/// names the deployment instead. These pin the label and the comparison.
@Suite("Setup-link deployment review")
struct SetupDeploymentTests {
    // Shaped like real deployment IDs: the shared `AKfycb` prefix, unique tails.
    static let clubID = "AKfycbzClubDeployment000000000000000000000x9Qc"
    static let otherID = "AKfycbzOtherDeployment00000000000000000000a1B2"

    static func appsScript(_ id: String) -> URL {
        URL(string: "https://script.google.com/macros/s/\(id)/exec")!
    }

    static func config(_ endpoint: URL?, secret: String = "test-secret-not-real", device: String? = "Run phone") -> AppConfig {
        AppConfig(endpoint: endpoint, secret: secret, deviceName: device)
    }

    @Test("An Apps Script endpoint is named by its deployment ID")
    func appsScriptDeployment() throws {
        let deployment = try #require(SheetDeployment(endpoint: Self.appsScript(Self.clubID)))

        #expect(deployment.id == Self.clubID)
        #expect(deployment.label == "AKfy…x9Qc")
        // Workspace accounts put the domain before the same deployment ID.
        let workspace = SheetDeployment(
            endpoint: URL(string: "https://script.google.com/a/macros/club.example/s/\(Self.clubID)/exec")
        )
        #expect(workspace == deployment)
    }

    @Test("The same deployment matches; another deployment on the same host does not")
    func deploymentComparison() {
        let club = SheetDeployment(endpoint: Self.appsScript(Self.clubID))

        #expect(club == SheetDeployment(
            endpoint: URL(string: "https://SCRIPT.google.com/macros/s/\(Self.clubID)/exec?v=2")
        ))
        #expect(club != SheetDeployment(endpoint: Self.appsScript(Self.otherID)))
    }

    @Test("Other HTTPS endpoints fall back to host plus path")
    func nonAppsScriptDeployment() throws {
        let deployment = try #require(SheetDeployment(endpoint: URL(string: "https://Sheet.Example:8443/api/exec/")))

        #expect(deployment.id == "sheet.example:8443/api/exec")
        #expect(deployment.label == deployment.id)
        #expect(SheetDeployment(endpoint: URL(string: "https://ui-test.invalid/exec"))?.label == "ui-test.invalid/exec")
        #expect(
            SheetDeployment(endpoint: URL(string: "https://example.test/exec"))
                != SheetDeployment(endpoint: URL(string: "https://example.test/other"))
        )
    }

    @Test("Malformed endpoints have no deployment, or show their full path")
    func malformedDeployment() {
        #expect(SheetDeployment(endpoint: nil) == nil)
        #expect(SheetDeployment(endpoint: URL(string: "not a url")) == nil)
        #expect(SheetDeployment(endpoint: URL(string: "/macros/s/\(Self.clubID)/exec")) == nil)
        // No ID after `/s`, so there is nothing to abbreviate.
        #expect(
            SheetDeployment(endpoint: URL(string: "https://script.google.com/macros/s"))?.label
                == "script.google.com/macros/s"
        )
        // A look-alike ID is not a deployment ID. It shows encoded, in full.
        #expect(
            SheetDeployment(endpoint: URL(string: "https://script.google.com/macros/s/AKfy%E2%80%A6x9Qc/exec"))?.label
                == "script.google.com/macros/s/AKfy%E2%80%A6x9Qc/exec"
        )
    }

    @Test("A phone with no connection sees a first connection")
    func firstConnectionReview() throws {
        let review = try #require(SetupCodeReview(
            incoming: Self.config(Self.appsScript(Self.clubID)),
            current: AppConfig(),
            waitingSubmissions: 0
        ))

        #expect(review.change == .firstConnection)
        #expect(review.title == "Connect this phone?")
        #expect(review.confirmTitle == "Connect")
        #expect(!review.isDestructive)
        #expect(review.message == """
        Sheet: AKfy…x9Qc
        Device: Run phone

        Connect only if you recognise this sheet.
        """)
    }

    @Test("A code for the current deployment only updates the connection")
    func sameSheetReview() throws {
        let review = try #require(SetupCodeReview(
            incoming: Self.config(Self.appsScript(Self.clubID), secret: "rotated-secret", device: nil),
            current: Self.config(Self.appsScript(Self.clubID)),
            waitingSubmissions: 3
        ))

        #expect(review.change == .sameSheet)
        #expect(review.title == "Update this connection?")
        // Same endpoint text, so SyncEngine keeps sending the waiting rows.
        #expect(review.strandedSubmissions == 0)
        #expect(!review.isDestructive)
        #expect(review.message == """
        Sheet: AKfy…x9Qc
        Device: no name

        This phone already uses this sheet. The code updates the secret and device name.
        """)
    }

    @Test("A code for another deployment warns about the replacement and stranded rows")
    func replacementReview() throws {
        let current = Self.config(Self.appsScript(Self.clubID))
        let incoming = Self.config(Self.appsScript(Self.otherID), device: "Col's phone")

        let one = try #require(SetupCodeReview(incoming: incoming, current: current, waitingSubmissions: 1))
        let many = try #require(SetupCodeReview(incoming: incoming, current: current, waitingSubmissions: 2))
        let none = try #require(SetupCodeReview(incoming: incoming, current: current, waitingSubmissions: 0))

        let club = try #require(SheetDeployment(endpoint: current.endpoint))
        #expect(one.change == .replacesSheet(current: club))
        #expect(one.title == "Replace the sheet connection?")
        #expect(one.confirmTitle == "Replace")
        #expect(one.isDestructive && none.isDestructive)
        #expect(one.message == """
        Sheet: AKfy…a1B2
        Device: Col's phone

        This replaces the current sheet, AKfy…x9Qc. The app will not send 1 submission that is waiting to sync. \
        It stays in Outbox for review. Replace only if you recognise the new sheet.
        """)
        #expect(many.message.contains("The app will not send 2 submissions that are waiting to sync. They stay in Outbox for review."))
        #expect(!none.message.contains("waiting to sync"))
    }

    @Test("Changed endpoint text strands rows even for the same deployment")
    func sameDeploymentDifferentText() throws {
        let review = try #require(SetupCodeReview(
            incoming: Self.config(URL(string: "https://script.google.com/macros/s/\(Self.clubID)/exec?v=2")),
            current: Self.config(Self.appsScript(Self.clubID)),
            waitingSubmissions: 2
        ))

        #expect(review.change == .sameSheet)
        #expect(review.strandedSubmissions == 2)
        #expect(review.isDestructive)
    }

    @Test("Only outstanding rows for the given endpoint are counted")
    @MainActor
    func outstandingCount() throws {
        let container = try ModelContainer(
            for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let club = Self.appsScript(Self.clubID).absoluteString
        func row(_ status: SubmissionStatus, _ endpoint: String?) {
            let pending = PendingSubmission(rowIndex: 42, expectedDate: "Fri, 11-Sep", expectedRun: "Soft Sand", attendees: ["Col"], status: status)
            pending.endpointIdentity = endpoint
            context.insert(pending)
        }
        row(.queued, club)
        row(.inFlight, club)
        row(.conflict, club)
        row(.done, club)
        row(.queued, "https://example.test/exec")
        row(.queued, nil)
        try context.save()

        #expect(try PendingSubmission.outstandingCount(endpointIdentity: club, in: context) == 3)
        #expect(try PendingSubmission.outstandingCount(endpointIdentity: nil, in: context) == 0)
    }
}
