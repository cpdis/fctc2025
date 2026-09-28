//
//  Motion.swift
//  FCTCAttendance
//
//  One small motion vocabulary for the whole app, so every screen moves with the
//  same timing. The rules, in order of importance:
//
//  1. Frequent actions (checking a member, changing a count) get fast, quiet
//     feedback. The state must read correctly on the first frame.
//  2. Rare moments (the first Home appearance, an empty Outbox) may take a little
//     longer and carry a little delight.
//  3. Reduce Motion keeps opacity and color changes and drops travel and scale.
//

import SwiftUI

enum Motion {
    /// State the person just changed: checks, counts, selections.
    static let snappy = Animation.snappy(duration: 0.22)
    /// Press-down feedback. Faster than the change it confirms.
    static let press = Animation.snappy(duration: 0.14)
    /// A state swap that replaces most of a screen, such as voice entry phases.
    static let crossFade = Animation.smooth(duration: 0.3)
    /// Entrance of the Home cards on the first appearance of a launch.
    static let entrance = Animation.smooth(duration: 0.5)
    /// Gap between staggered entrance items. Short, so nothing waits on it.
    static let stagger = 0.06
}

/// Scales a card or tile down slightly while it is pressed, so the tap reads as
/// heard before navigation starts. Reduce Motion keeps only the dimming.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A custom style loses the system disabled look, so it is restored here.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension AnyTransition {
    /// Fades in with a slight scale from `anchor`. Reduce Motion keeps the fade
    /// only, so every scale-in in the app follows rule 3 from one place.
    static func settle(
        scale: CGFloat,
        anchor: UnitPoint = .center,
        reduceMotion: Bool
    ) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: scale, anchor: anchor))
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// A plain button that shrinks a little on press.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Fades and lifts a view into place once, `index` steps after its siblings.
///
///     hasEntered: false ──► true
///     item 0:  ░░▓▓██
///     item 1:    ░░▓▓██
///     item 2:      ░░▓▓██        (Motion.stagger apart)
///
/// The caller owns `hasEntered`, so the stagger plays once per launch rather
/// than every time the screen reappears after a pop.
private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let hasEntered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered || reduceMotion ? 0 : 14)
            .animation(
                Motion.entrance.delay(Double(index) * Motion.stagger),
                value: hasEntered
            )
    }
}

extension View {
    func staggeredEntrance(_ index: Int, hasEntered: Bool) -> some View {
        modifier(StaggeredEntrance(index: index, hasEntered: hasEntered))
    }
}
