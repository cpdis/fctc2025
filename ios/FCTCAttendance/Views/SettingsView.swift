//
//  SettingsView.swift
//  FCTCAttendance
//

import FCTCAttendanceKit
import SwiftUI

struct SettingsView: View {
    let runtime: AppRuntime
    let configurationRequired: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @State private var showingSetupScanner = false

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

            Section("This device") {
                TextField("Device name", text: $viewModel.deviceName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Device name")
                    .accessibilityIdentifier("settings-device-name")
            }

            Section("Theme") {
                accentPicker
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
                Text("Refresh replaces the local cache with the current sheet roster and runs.")
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

    /// Reminders-style accent swatches: one tap sets and persists the tint.
    private var accentPicker: some View {
        HStack(spacing: 14) {
            ForEach(AccentChoice.allCases, id: \.self) { choice in
                Button {
                    runtime.setAccent(choice)
                } label: {
                    ZStack {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 32, height: 32)
                        if runtime.accent == choice {
                            Circle()
                                .strokeBorder(.primary.opacity(0.35), lineWidth: 3)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.label) accent")
                .accessibilityAddTraits(runtime.accent == choice ? .isSelected : [])
                .accessibilityIdentifier("accent-\(choice.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
