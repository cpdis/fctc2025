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

            Section {
                LabeledContent {
                    Text("Setup release")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Import QR Code", systemImage: "qrcode.viewfinder")
                }
                .accessibilityHint("QR import arrives in U8.")
                .accessibilityIdentifier("settings-qr-seam")
            } footer: {
                Text("The QR scanner will use the same validated import seam as this form.")
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
