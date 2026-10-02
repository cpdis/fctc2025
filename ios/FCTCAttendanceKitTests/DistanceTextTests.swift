//
//  DistanceTextTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

struct DistanceTextTests {
    @Test(arguments: [
        ("12", 12.0), ("12.", 12.0), ("12.5", 12.5), (".5", 0.5), (" 7 ", 7.0),
        // The decimal pad shows a comma in some locales.
        ("12,5", 12.5),
    ])
    func parsesTypedKilometres(text: String, expected: Double) {
        #expect(DistanceText.parse(text) == expected)
    }

    @Test(arguments: ["", "   ", ".", "1.2.3", "1,2.3", "abc", "nan", "inf", "-inf"])
    func blankOrMalformedTextHasNoOpinion(text: String) {
        #expect(DistanceText.parse(text) == nil)
    }

    @Test(arguments: ["8..2", "1.2.3", ".", "abc"])
    func typedTextThatIsNotANumberIsMalformed(text: String) {
        #expect(DistanceText.isMalformed(text))
    }

    @Test(arguments: ["", "   ", "8.2", "12.", "12,5"])
    func blankOrNumericTextIsNotMalformed(text: String) {
        #expect(DistanceText.isMalformed(text) == false)
    }

    @Test func formatsUpToTwoDecimalsAndBlankForNil() {
        #expect(DistanceText.format(nil) == "")
        #expect(DistanceText.format(7) == "7")
        #expect(DistanceText.format(7.1) == "7.1")
        #expect(DistanceText.format(7.126) == "7.13")
        // No grouping separator: "1,234.5" would parse as 1.2345.
        #expect(DistanceText.format(1234.5) == "1234.5")
    }

    /// The seeded field text must never read as malformed, whatever the device
    /// locale, or Confirm would be disabled for the sheet's own distance.
    @Test(arguments: [0.5, 7, 7.1, 12.75, 42.195, 1234.5])
    func formattedDistanceRoundTripsAndIsNeverMalformed(value: Double) {
        let text = DistanceText.format(value)
        #expect(DistanceText.isMalformed(text) == false)
        #expect(DistanceText.parse(text) == (value * 100).rounded() / 100)
    }
}
