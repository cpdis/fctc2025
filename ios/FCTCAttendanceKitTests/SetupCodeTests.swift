//
//  SetupCodeTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("U8 setup-code import")
struct SetupCodeTests {

    @Test("A valid setup code becomes an app configuration")
    func validPayload() throws {
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
