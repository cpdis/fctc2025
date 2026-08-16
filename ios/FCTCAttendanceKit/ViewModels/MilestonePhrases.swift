//
//  MilestonePhrases.swift
//  FCTCAttendanceKit
//
//  What the Milestones section says when nobody is close.
//
//  The draw happens once per app launch and is held, never recomputed in a view
//  body: a fresh roll on every state change would flicker the line while the app
//  is in use.
//

import Foundation

public enum MilestonePhrases {

    /// The empty-state lines, in a fixed order so an index is a stable identity.
    public static let all: [String] = [
        """
        Not a milestone in sight, not a one, not a two.
        The scoundrels are running, but they're not nearly through.
        """,
        """
        No fifties, no hundreds, no landmarks to chase.
        Just legs in the soft sand and salt on each face.
        """,
        """
        Nobody's close. Not a soul. Not a smidge.
        The next round number is over the ridge.
        """,
        """
        The milestones are sleeping, they've wandered off far.
        Go run a few more and we'll see where you are.
        """,
        """
        No one is near, not by ten, not by nine.
        Lace up, you scoundrels. You'll get there in time.
        """,
        """
        No milestones brewing. The pot has gone cold.
        Run out a few more and the story gets told.
        """,
        """
        Not a runner in range, not a one on the cusp.
        The numbers are quiet. The rest is on us.
        """,
        """
        The fifties are far and the hundreds are farther.
        No one is close, so run harder, run smarter.
        """,
        """
        Zero in reach and zero on deck.
        Come back on Friday and let's have a check.
        """,
        """
        No landmarks today, not a hint, not a hunch.
        Check in again once you've knocked out a bunch.
        """,
    ]

    /// Pick a line, avoiding `previous`.
    ///
    /// With ten lines a plain random draw repeats back-to-back about one launch in
    /// ten, which reads as a bug rather than as chance. Drawing from the other nine
    /// and mapping back costs nothing and removes it.
    ///
    /// - Parameters:
    ///   - previous: the index shown last launch, or nil on a first run.
    ///   - generator: injected so tests are deterministic.
    /// - Returns: the chosen index, to persist as the next call's `previous`.
    public static func nextIndex(
        avoiding previous: Int?,
        using generator: inout some RandomNumberGenerator
    ) -> Int {
        guard let previous, all.indices.contains(previous), all.count > 1 else {
            return Int.random(in: all.indices, using: &generator)
        }
        // Draw from the remaining lines, then shift past the excluded one.
        let drawn = Int.random(in: 0..<(all.count - 1), using: &generator)
        return drawn < previous ? drawn : drawn + 1
    }

    /// The line at an index, tolerating a stored index from a shorter old list.
    public static func phrase(at index: Int) -> String {
        all.indices.contains(index) ? all[index] : all[0]
    }

    /// UserDefaults key holding the index shown last launch.
    static let lastIndexKey = "fctc.milestonePhraseIndex"

    /// Draw this launch's line and remember it for the next one.
    ///
    /// Call once, at startup, and hold the result. Calling it from a view body
    /// would re-roll on every state change and flicker the line as the app is used.
    public static func drawForLaunch(
        defaults: UserDefaults = .standard,
        generator: inout some RandomNumberGenerator
    ) -> String {
        let previous = defaults.object(forKey: lastIndexKey) as? Int
        let index = nextIndex(avoiding: previous, using: &generator)
        defaults.set(index, forKey: lastIndexKey)
        return phrase(at: index)
    }
}
