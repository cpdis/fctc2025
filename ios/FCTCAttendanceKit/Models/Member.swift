//
//  Member.swift
//  FCTCAttendanceKit
//
//  A roster member, mirrored from the season sheet's header row.
//
//  The sheet's SHORT NAME is the canonical key everywhere in this app
//  (`Col`, `Alex Kr`, `Dan B`, `Alex 👑`). There is deliberately no parallel ID
//  scheme: the roster is read live from the header (plan decision #7) and a rename
//  in the sheet is a rename here.
//

import Foundation
import SwiftData

@Model
public final class Member {

    /// Sheet header cell text, verbatim — the canonical member key.
    @Attribute(.unique) public var name: String

    /// 1-based column index in the season sheet, as returned by `getState`.
    /// Advisory only: writes are addressed by name server-side, never by a
    /// client-cached column number.
    public var colIndex: Int

    /// True until an optimistic add-member write appears in the server roster.
    public var isNew: Bool

    /// When this member was last seen in a `getState` roster. Members that vanish
    /// from the header (rare) are kept until a refresh proves them gone.
    public var lastSeenAt: Date

    /// Runs across every season, as counted by the script. Zero for a member the
    /// server has not reported a total for, including an optimistic local add.
    public var lifetimeRuns: Int = 0

    public init(
        name: String,
        colIndex: Int,
        isNew: Bool = false,
        lastSeenAt: Date = .now,
        lifetimeRuns: Int = 0
    ) {
        self.name = name
        self.colIndex = colIndex
        self.isNew = isNew
        self.lastSeenAt = lastSeenAt
        self.lifetimeRuns = lifetimeRuns
    }
}

extension Member {
    /// Alphabetical ordering matching the sheet's member-band convention, so an
    /// optimistically-inserted new member lands where `addMember` will put it.
    public static func sheetOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
