//
//  NicknameTable.swift
//  FCTCAttendanceKit
//
//  U5 — long-forms, ASR homophones and OCR variants mapped ONTO the sheet's short
//  names. Direction matters: the sheet is canonical, so every VALUE here must be a
//  real header cell ("Col", "Cam", "Alex Kr"), and every KEY is written in
//  `NormalizedName.core` form (lowercase, single-spaced, no punctuation).
//
//  It is a plain dictionary on purpose: adding "whoever the club calls Chartt this
//  season" is a one-line change, no code.
//
//  Note the deliberate non-resolutions: "Alexander" maps to `Alex`, which is a first
//  name three members share — so it comes back AMBIGUOUS, exactly as a bare "Alex"
//  does. A nickname is allowed to narrow the field; it is never allowed to pick a
//  person the roster itself cannot distinguish.
//

import Foundation

public enum NicknameTable {

    /// Variant (normalized) → canonical sheet name.
    public static let defaults: [String: String] = [
        // Long forms of the sheet's short keys.
        "colin": "Col",
        "collin": "Col",
        "cameron": "Cam",
        "daniel": "Dan",
        "danny": "Dan",
        "timothy": "Tim",
        "timmy": "Tim",
        "alexander": "Alex",
        "alexandra": "Alex",
        "samuel": "Sam",
        "sammy": "Sam",
        "joseph": "Joe",
        "joey": "Joe",
        "wesley": "Wes",
        "william": "Liam",
        "dean": "Deano",
        "scotty": "Scott",
        "katie": "Kate B",
        "katherine": "Kate B",
        "kathryn": "Kate B",

        // Contact display names WhatsApp shows in full.
        "alex kravchenko": "Alex Kr",

        // ASR homophones / near-misses heard on the beach.
        "colm": "Col",
        "cole": "Col",
        "camm": "Cam",
        "kam": "Cam",
        "tarq": "Tarquin",
        "tark": "Tarquin",
        "reece": "Rhys",
        "reese": "Rhys",
        "rees": "Rhys",
        "shayne": "Shane",
        "clare": "Claire",
        "clair": "Claire",
        "frazer": "Fraser",
        "frazier": "Fraser",
        "tobey": "Toby",
        "tobias": "Toby",
        "aron": "Aaron",
        "arron": "Aaron",
        "annie": "Anna",
        "darran": "Darren",
        "daren": "Darren",

        // OCR variants that fuzzy scoring alone would leave in the suggestion tier.
        "scot": "Scott",
        "celest": "Celeste",
    ]
}
