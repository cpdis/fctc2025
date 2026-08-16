//
//  SetupCodeTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
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
