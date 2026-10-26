//
//  AddRunDraftTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

struct AddRunDraftTests {
    /// 25 September 2026 at noon in the device zone, a Friday.
    private static let friday: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 25; parts.hour = 12
        return Calendar(identifier: .gregorian).date(from: parts)!
    }()

    @Test("Add needs a meeting place and a run name")
    func addNeedsMeetAndRun() {
        var draft = AddRunDraft(date: Self.friday)
        #expect(draft.canAdd == false)
        draft.meet = "  Tompkins Park "
        #expect(draft.canAdd == false)
        draft.run = "River Loop"
        #expect(draft.canAdd)
    }

    @Test("A typed distance reaches the request with the keyboard still up")
    func typedDistanceReachesTheRequest() {
        var draft = AddRunDraft(date: Self.friday)
        draft.meet = "Tompkins Park"; draft.run = "River Loop"; draft.approxKmText = "6.5"
        #expect(draft.request.approxKm == 6.5)
        #expect(draft.request.meet == "Tompkins Park")
        #expect(draft.request.date == "Fri, 25-Sep")
    }

    @Test("A blank distance is allowed; a malformed one blocks Add", arguments: [
        ("", true, nil as Double?), ("8.2", true, 8.2), ("8,2", true, 8.2), ("8..2", false, nil),
    ])
    func distanceRules(text: String, canAdd: Bool, approxKm: Double?) {
        var draft = AddRunDraft(date: Self.friday)
        draft.meet = "Il Lido"; draft.run = "Soft Sand"; draft.approxKmText = text
        #expect(draft.canAdd == canAdd)
        #expect(draft.distanceIsMalformed == !canAdd)
        #expect(draft.request.approxKm == approxKm)
    }
}
