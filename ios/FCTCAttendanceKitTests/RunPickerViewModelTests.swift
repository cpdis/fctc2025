//
//  RunPickerViewModelTests.swift
//  FCTCAttendanceKitTests
//
//  U4: run picker default selection and sections.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

extension ViewModelTests {
    @Test("Run picker selects the latest unrecorded run at or before now")
    func defaultRunSkipsRecorded() {
        let runs = [
            run(row: 1, dayOffset: -2),
            run(row: 2, dayOffset: -1, attendees: ["Col"]),
            run(row: 3, dayOffset: 0),
            run(row: 4, dayOffset: 1),
        ]

        let selected = RunPickerViewModel.defaultRun(
            from: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(selected?.rowIndex == 3)
    }

    @Test("Run picker falls back to the latest recorded run when none are pending")
    func defaultRunRecordedFallback() {
        let runs = [
            run(row: 1, dayOffset: -2, attendees: ["Aaron"]),
            run(row: 2, dayOffset: 0, plusOnes: 1),
            run(row: 3, dayOffset: 1),
        ]

        let selected = RunPickerViewModel.defaultRun(
            from: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(selected?.rowIndex == 2)
    }

    @Test("Run picker produces Today, This Week, Later, and Past sections")
    func runSections() {
        let viewModel = RunPickerViewModel(engine: ViewModelSyncClient())
        viewModel.update(
            runs: [
                run(row: 1, dayOffset: -1),
                run(row: 2, dayOffset: 0),
                run(row: 3, dayOffset: 1),
                run(row: 4, dayOffset: 10),
            ],
            now: now,
            calendar: utcCalendar
        )

        #expect(viewModel.sections.map(\.kind) == [.today, .thisWeek, .later, .past])
    }
}
