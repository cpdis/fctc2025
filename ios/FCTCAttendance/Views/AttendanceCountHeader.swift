import FCTCAttendanceKit
import SwiftUI

/// Both values come from the full draft, so searching never changes the count.
struct AttendanceCountHeader: View {
    let draft: AttendanceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Attendance")
                    Spacer(minLength: 12)
                    checkedCount
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attendance")
                    checkedCount
                }
            }
            if draft.plusOnes > 0 {
                let total = draft.checks.count + draft.plusOnes
                Text("\(total) \(total == 1 ? "person" : "people") including \(draft.plusOnes) \(draft.plusOnes == 1 ? "guest" : "guests")")
                    .font(.footnote)
                    .fontWeight(.regular)
                    .contentTransition(.numericText(value: Double(total)))
                    .accessibilityIdentifier("attendance-total")
            }
        }
        .textCase(nil)
        .animation(Motion.snappy, value: draft.checks.count)
        .animation(Motion.snappy, value: draft.plusOnes)
    }

    private var checkedCount: some View {
        Text("\(draft.checks.count) checked")
            .monospacedDigit()
            .foregroundStyle(.primary)
            // The count rolls with each tap, echoing the check that caused it.
            .contentTransition(.numericText(value: Double(draft.checks.count)))
            .accessibilityIdentifier("attendance-count")
    }
}
