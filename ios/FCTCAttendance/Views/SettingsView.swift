//
//  SettingsView.swift
//  FCTCAttendance
//

import FCTCAttendanceKit
import SwiftUI
import UIKit

struct SettingsView: View {
    let runtime: AppRuntime
    let configurationRequired: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @State private var showingSetupScanner = false
    @State private var currentAlternateIcon: String?
    /// The selection rings slide between choices rather than jumping.
    @Namespace private var selectionRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(runtime: AppRuntime, configurationRequired: Bool = false) {
        self.runtime = runtime
        self.configurationRequired = configurationRequired
        _viewModel = State(
            initialValue: SettingsViewModel(
                persistence: runtime.configPersistence,
                engine: runtime.engine
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            if configurationRequired {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect the attendance sheet")
                                .font(.headline)
                            Text("Enter the Apps Script endpoint and shared secret to start.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checklist")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section("Sheet connection") {
                Button {
                    showingSetupScanner = true
                } label: {
                    Label("Scan setup code", systemImage: "qrcode.viewfinder")
                }
                .accessibilityHint("Scans the endpoint, shared secret, and device name.")
                .accessibilityIdentifier("settings-scan-setup-code")

                TextField("Endpoint URL", text: $viewModel.endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Sheet endpoint URL")
                    .accessibilityIdentifier("settings-endpoint")

                SecureField("Shared secret", text: $viewModel.secret)
                    .textContentType(.password)
                    .accessibilityLabel("Shared secret")
                    .accessibilityIdentifier("settings-secret")
            }

            Section("Guest history") {
                NavigationLink { GuestRecoveryView(runtime: runtime) } label: {
                    Label("Recover guest history", systemImage: "person.crop.circle.badge.clock")
                }.accessibilityIdentifier("settings-recover-guests")
            }

            Section("This device") {
                TextField("Device name", text: $viewModel.deviceName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Device name")
                    .accessibilityIdentifier("settings-device-name")
            }

            Section {
                Toggle(
                    "Run reminders",
                    isOn: Binding(
                        get: { runtime.runRemindersEnabled },
                        set: { enabled in
                            Task { await runtime.setRunRemindersEnabled(enabled) }
                        }
                    )
                )
                .accessibilityIdentifier("settings-run-reminders")
            } footer: {
                Text(runtime.reminderMessage ?? "Get a local reminder after each future run.")
            }

            Section("Theme") {
                accentPicker
                appIconPicker
            }

            Section {
                Button {
                    Task { try? await viewModel.refreshRoster() }
                } label: {
                    HStack {
                        Label("Re-fetch Roster", systemImage: "arrow.clockwise")
                        Spacer()
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Refreshing roster")
                        }
                    }
                }
                .disabled(viewModel.isRefreshing || !runtime.config.isConfigured)
                .accessibilityIdentifier("settings-refresh-roster")
            } footer: {
                Text("Refresh updates the current season. Saved guest history remains available.")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } else if let success = viewModel.successMessage {
                Section {
                    Label(success, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            // Always last, so it sits at the bottom of the form.
            Section {} footer: {
                Text(appVersion)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("settings-app-version")
            }
        }
        .navigationTitle(configurationRequired ? "Set Up FCTC" : "Settings")
        .navigationBarTitleDisplayMode(configurationRequired ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("settings-save")
            }
        }
        .sheet(isPresented: $showingSetupScanner) {
            SetupCodeScannerView { payload in
                let config = try viewModel.importAndSaveSetupCode(payload)
                runtime.apply(config)
                viewModel.replaceEngine(runtime.engine)
            }
        }
    }

    /// Two-choice icon picker; setAlternateIconName persists across launches
    /// on its own and shows the system's confirmation alert.
    private var appIconPicker: some View {
        HStack(spacing: 14) {
            appIconOption(title: "Perth", assetName: nil, preview: "AppIconPreview")
            appIconOption(title: "Spring", assetName: "AppIconAlt", preview: "AppIconAltPreview")
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .onAppear { currentAlternateIcon = UIApplication.shared.alternateIconName }
    }

    private func appIconOption(
        title: String,
        assetName: String?,
        preview: String
    ) -> some View {
        let selected = currentAlternateIcon == assetName
        return Button {
            UIApplication.shared.setAlternateIconName(assetName)
            withAnimation(Motion.snappy) { currentAlternateIcon = assetName }
        } label: {
            VStack(spacing: 6) {
                Image(preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.tint, lineWidth: 3)
                                .matchedGeometryEffect(id: ringID("app-icon", title), in: selectionRing)
                        }
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("app-icon-\(title.lowercased())")
    }

    /// Reminders-style accent swatches: one tap sets and persists the tint.
    /// Sized so all seven slots fit the section's content width; 40-point slots
    /// overflowed and clipped the first ring (Colin's review).
    private var accentPicker: some View {
        HStack(spacing: 0) {
            ForEach(AccentChoice.allCases, id: \.self) { choice in
                Button {
                    // Animating the choice also eases the app-wide tint change.
                    withAnimation(Motion.snappy) { runtime.setAccent(choice) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 28, height: 28)
                        if runtime.accent == choice {
                            Circle()
                                .strokeBorder(.primary.opacity(0.35), lineWidth: 2.5)
                                .frame(width: 36, height: 36)
                                .matchedGeometryEffect(id: ringID("accent", choice.rawValue), in: selectionRing)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.label) accent")
                .accessibilityAddTraits(runtime.accent == choice ? .isSelected : [])
                .accessibilityIdentifier("accent-\(choice.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    /// One shared id lets a ring slide to the new choice. Under Reduce Motion
    /// each choice gets its own id, so nothing matches and the rings cross-fade.
    private func ringID(_ group: String, _ choice: String) -> String {
        reduceMotion ? "\(group)-\(choice)" : group
    }

    /// "Version 0.1.0 (6)": the marketing version and build, so a TestFlight
    /// report names the exact build.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    private func save() {
        do {
            let config = try viewModel.save()
            runtime.apply(config)
            viewModel.replaceEngine(runtime.engine)
            if !configurationRequired { dismiss() }
        } catch {}
    }
}
