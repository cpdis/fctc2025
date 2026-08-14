//
//  AttendanceComponents.swift
//  FCTCAttendance
//
//  Shared member identity and proposal provenance components.
//

import FCTCAttendanceKit
import SwiftUI

struct MemberAvatarView: View {
    let name: String

    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .red, .teal, .indigo,
    ]

    var body: some View {
        Text(MemberAvatar.initials(for: name))
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Self.palette[MemberAvatar.paletteIndex(for: name)], in: .circle)
            .accessibilityHidden(true)
    }
}

enum ProvenanceBadgeKind {
    case model
    case voice
    case screenshot
    case suggested

    init(_ provenance: CheckProvenance) {
        switch provenance {
        case .manual: self = .model
        case .ocr: self = .screenshot
        case .voice: self = .voice
        }
    }
}

struct ProvenanceBadge: View {
    let kind: ProvenanceBadgeKind

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.09), in: .capsule)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch kind {
        case .model: "Proposed"
        case .voice: "Voice"
        case .screenshot: "Screenshot"
        case .suggested: "Suggested"
        }
    }

    private var systemImage: String {
        switch kind {
        case .model: "sparkles"
        case .voice: "waveform"
        case .screenshot: "photo"
        case .suggested: "questionmark.circle"
        }
    }
}

struct FrequentGuestBadge: View {
    var body: some View {
        Text("Frequent guest")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.09), in: .capsule)
    }
}
