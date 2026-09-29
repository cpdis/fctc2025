//
//  TabHeader.swift
//  FCTCAttendance
//
//  The title row every tab root draws itself (Runs, Events, Dashboard), in
//  place of the system large title. Runs needs its gear on the title line,
//  which the system bar cannot do, and a system title sits lower than a row in
//  the content, so all three tabs use this one row to put their titles at the
//  same height:
//
//    ┌──────────────────────────────────────┐
//    │ FCTC                           (⚙)   │  ← Runs: Settings
//    │ Events                               │
//    │ Dashboard                  2026 ⌄    │  ← Dashboard: season menu
//    └──────────────────────────────────────┘
//
//  Each root hides its navigation bar; pushed screens keep theirs.
//

import SwiftUI

struct TabHeader<Trailing: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder var trailing: Trailing

    /// The tallest trailing control (the 44 pt gear), so every tab's row, and
    /// so its title, sits at the same height with or without one.
    static var rowHeight: CGFloat { 44 }

    var body: some View {
        HStack(alignment: .center) {
            // Large title metrics, so the header scales with Dynamic Type like
            // the system title it replaces.
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            Spacer()
            trailing
        }
        .frame(minHeight: Self.rowHeight)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: String, identifier: String) {
        self.init(title: title, identifier: identifier) { EmptyView() }
    }
}

extension View {
    /// A `TabHeader` as the first row of an inset-grouped List: flush with the
    /// section edges, on the grouped background. Runs and Events both use it.
    func tabHeaderRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}
