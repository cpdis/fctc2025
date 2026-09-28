//
//  EventsView.swift
//  FCTCAttendance
//
//  The Events tab (R22): what's coming up. It holds the Milestones and Birthdays
//  sections that moved off Runs; U16 builds the rest of the board around them.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

struct EventsView: View {
    let runtime: AppRuntime
    /// The Events tab's stack, owned by RootTabView so an engine swap can reset it.
    @Binding var path: NavigationPath

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query(sort: \Member.name) private var cachedMembers: [Member]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Both sections are always present, including before the first
                // sync, where each falls through to its own empty state rather
                // than vanishing.
                MilestonesSection(
                    totals: activeMemberTotals,
                    emptyPhrase: runtime.milestoneEmptyPhrase
                )

                // BirthdaysSection keeps its own clock (a minute timer, midnight
                // and scene changes), so the window stays current here too.
                BirthdaysSection(birthdays: activeBirthdays)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Events")
        }
    }

    /// The active season's birthdays: live from the sheet state when it has
    /// them, else the members' cached copy for this endpoint and season. Nil
    /// means an older server that sends none, which has its own empty text.
    private var activeBirthdays: [MemberBirthday]? {
        let state = runtime.activeSheetState
        if let birthdays = state?.birthdays { return birthdays }
        let seasonYear = state?.seasonYear ?? runtime.activeRuns(in: cachedRuns).compactMap(\.seasonYear).max()
        let cached = cachedMembers.compactMap {
            $0.birthday(for: runtime.config.endpoint?.absoluteString, seasonYear: seasonYear)
        }
        let hasBirthdayCache = cachedMembers.contains {
            $0.birthdayEndpointIdentity != nil && $0.birthdayEndpointIdentity == runtime.config.endpoint?.absoluteString
                && (seasonYear == nil || $0.birthdaySeasonYear == seasonYear)
        }
        return hasBirthdayCache ? cached : nil
    }

    /// All-time totals for the current roster, falling back to the cached members
    /// before the first `getState` carries `lifetimeTotals`.
    private var activeMemberTotals: [MemberTotal] {
        guard let state = runtime.activeSheetState, !state.lifetimeTotals.isEmpty else {
            return cachedMembers.map { MemberTotal(name: $0.name, runs: $0.lifetimeRuns) }
        }
        let roster = Set(state.roster.map(\.name))
        return state.lifetimeTotals.filter { roster.contains($0.name) }
    }
}
