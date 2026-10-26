//
//  AppConfigRedactionTests.swift
//  FCTCAttendanceKitTests
//
//  The shared secret must not show in any textual or reflected form of AppConfig.
//

import Foundation
import Testing
@testable import FCTCAttendanceKit

struct AppConfigRedactionTests {
    private let secret = "s3cret-value-9f2c"
    private var config: AppConfig {
        AppConfig(
            endpoint: URL(string: "https://example.test/exec"),
            secret: secret,
            deviceName: "Colin's iPhone"
        )
    }

    @Test func descriptionsHideTheSecret() {
        #expect(!"\(config)".contains(secret))
        #expect(!String(describing: config).contains(secret))
        #expect(!String(reflecting: config).contains(secret))
        #expect("\(config)".contains("<redacted>"))
        #expect("\(config)".contains("https://example.test/exec"))
        #expect("\(config)".contains("Colin's iPhone"))
    }

    @Test func mirrorHidesTheSecret() {
        let mirror = Mirror(reflecting: config)
        for child in mirror.children {
            #expect(!"\(child.value)".contains(secret))
        }
        var dumped = ""
        dump(config, to: &dumped)
        #expect(!dumped.contains(secret))
    }
}
