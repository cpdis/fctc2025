//
//  VoiceEntryView.swift
//  FCTCAttendance
//
//  U7 — Dictate attendance, inspect the live transcript, then send a frozen
//  DraftProposalSet through the shared triage call site.
//

import FCTCAttendanceKit
import SwiftUI
import UIKit

struct VoiceEntryView: View {
    let checklistViewModel: ChecklistViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: VoiceEntryViewModel
    @State private var addPersonError: String?

    init(
        checklistViewModel: ChecklistViewModel,
        transcriber: any Transcriber = SpeechService()
    ) {
        self.checklistViewModel = checklistViewModel
        _addPersonError = State(initialValue: nil)
        _viewModel = State(
            initialValue: VoiceEntryViewModel(
                roster: checklistViewModel.roster,
                transcriber: transcriber
            )
        )
    }

    var body: some View {
        // Split into named pieces: one combined expression with the implicit
        // sync-to-async closure conversions sends the type checker over time.
        content
            .toolbar {
            if viewModel.proposalSet == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.stop()
                        dismiss()
                    }
                }
            }
        }
        .task {
            if viewModel.phase == .checkingPermissions {
                await viewModel.prepare()
            }
        }
        .onChange(of: checklistViewModel.roster) { _, roster in
            viewModel.updateRoster(roster)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshAuthorizationIfNeeded() }
            } else {
                viewModel.stop()
            }
        }
        .onDisappear { viewModel.stop() }
        .alert(
            "Could not add person",
            isPresented: addPersonErrorShown
        ) {
            Button("OK") { addPersonError = nil }
        } message: {
            Text(addPersonError ?? "Try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let set = viewModel.proposalSet, viewModel.phase == .triage {
            triageView(for: set)
        } else {
            captureView
        }
    }

    /// The frozen U6 call site, isolated so its closure conversions type-check
    /// on their own.
    private func triageView(for set: DraftProposalSet) -> some View {
        let apply: ([String]) -> Void = { checks in
            checklistViewModel.applyProposals(checks: checks, from: set)
            dismiss()
        }
        return ProposalTriageView(
            set: set,
            roster: checklistViewModel.roster,
            onApply: apply,
            onAddPerson: addPerson,
            onCancel: viewModel.returnToRecording
        )
    }

    private var addPersonErrorShown: Binding<Bool> {
        Binding(
            get: { addPersonError != nil },
            set: { if !$0 { addPersonError = nil } }
        )
    }

    private var captureView: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                switch viewModel.phase {
                case .checkingPermissions:
                    ProgressView("Checking microphone access…")
                        .frame(maxWidth: .infinity, minHeight: 180)

                case .permissionDenied:
                    permissionDeniedView

                case .restricted:
                    ContentUnavailableView(
                        "Dictation is restricted",
                        systemImage: "mic.slash",
                        description: Text("This device does not allow speech recognition. Use the checklist instead.")
                    )

                case .processing:
                    ProgressView("Finding runners…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 180)

                case .failed(let message):
                    failureView(message)

                case .ready, .recording, .triage:
                    transcriptCard
                    recognitionIndicator
                    recordControl
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dictate Attendance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Say who ran")
                .font(.title2.weight(.semibold))
            Text("Include guests and actual kilometres. You will review every suggestion before it changes the checklist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.phase == .recording ? "Listening" : "Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if viewModel.phase == .recording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Recording")
                }
            }

            if viewModel.transcript.isEmpty {
                Text("Try: “Col, Aaron and Adam came, plus two guests. We did 8.7k.”")
                    .foregroundStyle(.tertiary)
            } else {
                highlightedTranscript
                    .foregroundStyle(.primary)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voice-transcript")
    }

    @ViewBuilder
    private var recognitionIndicator: some View {
        switch viewModel.recognitionMode {
        case .onDevice:
            Label("On-device recognition", systemImage: "iphone.gen3")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .server:
            Label("Apple server recognition", systemImage: "cloud")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHint("Audio may leave this device for recognition.")
        case nil:
            EmptyView()
        }
    }

    private var recordControl: some View {
        Button {
            Task {
                if viewModel.phase == .recording {
                    await viewModel.stopAndParse()
                } else {
                    await viewModel.startRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.phase == .recording ? Color.red : Color.accentColor)
                    .frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                Image(systemName: viewModel.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.phase == .recording ? "Stop recording" : recordLabel)
        .accessibilityIdentifier("voice-record")
    }

    private var recordLabel: String {
        viewModel.transcript.isEmpty ? "Start recording" : "Re-record"
    }

    private var highlightedTranscript: Text {
        let tokens = VoiceTranscriptAnnotator().annotate(viewModel.transcript)
        var transcript = AttributedString()
        for entry in tokens.enumerated() {
            let suffix = entry.offset == tokens.count - 1 ? "" : " "
            var token = AttributedString(entry.element.text + suffix)
            switch entry.element.kind {
            case .plain:
                break
            case .name:
                token.foregroundColor = .accentColor
                token.font = .body.bold()
            case .number:
                token.foregroundColor = .orange
                token.font = .body.bold()
            }
            transcript.append(token)
        }
        return Text(transcript)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "Microphone access is off",
                systemImage: "mic.slash",
                description: Text("Allow Microphone and Speech Recognition access in Settings, then return here.")
            )
            Button("Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("voice-open-settings")
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "Dictation stopped",
                systemImage: "waveform.badge.exclamationmark",
                description: Text(message)
            )
            Button("Try Again") {
                Task { await viewModel.startRecording() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func addPerson(_ name: String) {
        guard !checklistViewModel.isAddingPerson else { return }
        checklistViewModel.quickAddName = name
        Task { @MainActor in
            do {
                try await checklistViewModel.commitQuickAdd()
                viewModel.updateRoster(checklistViewModel.roster)
            } catch {
                addPersonError = UserFacingError.sync(error)
            }
        }
    }
}
