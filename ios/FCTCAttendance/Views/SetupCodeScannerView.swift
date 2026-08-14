//
//  SetupCodeScannerView.swift
//  FCTCAttendance
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Owns camera authorization and keeps the Settings form available when scanning
/// cannot run. Payload validation stays in FCTCAttendanceKit behind its protocol.
struct SetupCodeScannerView: View {
    let onPayload: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var access = CameraAccess.checking
    @State private var scannerID = UUID()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .checking:
                    ProgressView("Checking camera access…")
                case .ready:
                    scanner
                case .denied:
                    unavailable(
                        title: "Camera access is off",
                        detail: "Allow camera access in Settings, or close this screen and enter the setup details manually.",
                        canOpenSettings: true
                    )
                case .unavailable:
                    unavailable(
                        title: "Camera is not available",
                        detail: "Close this screen and enter the setup details manually.",
                        canOpenSettings: false
                    )
                }
            }
            .navigationTitle("Scan Setup Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await prepareCamera() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, access != .checking else { return }
                Task { await prepareCamera() }
            }
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            QRCodeCameraView(
                onCode: receive,
                onUnavailable: { access = .unavailable }
            )
                .id(scannerID)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("Setup code camera")

            VStack(spacing: 8) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.red.opacity(0.9), in: .rect(cornerRadius: 12))
                        .accessibilityIdentifier("setup-code-error")
                }
                Text("Point the camera at Colin's setup QR code.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: .capsule)
            }
            .padding(24)
        }
    }

    private func unavailable(
        title: String,
        detail: String,
        canOpenSettings: Bool
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.fill")
        } description: {
            Text(detail)
        } actions: {
            if canOpenSettings {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
            }
            if canOpenSettings {
                Button("Enter Manually") { dismiss() }
                    .buttonStyle(.bordered)
            } else {
                Button("Enter Manually") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func prepareCamera() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            access = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .ready
        case .notDetermined:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        case .denied, .restricted:
            access = .denied
        @unknown default:
            access = .unavailable
        }
    }

    private func receive(_ payload: String) {
        do {
            try onPayload(payload)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            // Rebuild the one-shot camera coordinator so a corrected QR can scan.
            scannerID = UUID()
        }
    }
}

private enum CameraAccess: Equatable {
    case checking
    case ready
    case denied
    case unavailable
}

private struct QRCodeCameraView: UIViewControllerRepresentable {
    let onCode: @MainActor @Sendable (String) -> Void
    let onUnavailable: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(
            delegate: context.coordinator,
            onConfigurationFailure: onUnavailable
        )
    }

    func updateUIViewController(
        _ uiViewController: QRCodeScannerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        private let onCode: @MainActor @Sendable (String) -> Void
        private var hasScanned = false

        init(onCode: @escaping @MainActor @Sendable (String) -> Void) {
            self.onCode = onCode
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  code.type == .qr,
                  let value = code.stringValue
            else { return }
            hasScanned = true
            Task { @MainActor [onCode] in
                onCode(value)
            }
        }
    }
}

@MainActor
private final class QRCodeScannerViewController: UIViewController {
    private let sessionController: CameraSessionController
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(
        delegate: any AVCaptureMetadataOutputObjectsDelegate,
        onConfigurationFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        sessionController = CameraSessionController(
            metadataDelegate: delegate,
            onConfigurationFailure: onConfigurationFailure
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: sessionController.captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        sessionController.configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionController.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionController.stop()
        super.viewWillDisappear(animated)
    }
}

/// Serializes all capture-session work because camera startup can block.
private final class CameraSessionController: @unchecked Sendable {
    let captureSession = AVCaptureSession()

    private let metadataDelegate: any AVCaptureMetadataOutputObjectsDelegate
    private let onConfigurationFailure: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.cpdis.FCTCAttendance.setup-code-camera")
    private var isConfigured = false

    init(
        metadataDelegate: any AVCaptureMetadataOutputObjectsDelegate,
        onConfigurationFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        self.metadataDelegate = metadataDelegate
        self.onConfigurationFailure = onConfigurationFailure
    }

    func configure() {
        queue.async { [self] in
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }

            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  captureSession.canAddInput(input)
            else {
                reportConfigurationFailure()
                return
            }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(output) else {
                reportConfigurationFailure()
                return
            }
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(metadataDelegate, queue: queue)
            output.metadataObjectTypes = [.qr]
            isConfigured = true
        }
    }

    func start() {
        queue.async { [self] in
            guard isConfigured, !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    func stop() {
        queue.async { [captureSession] in
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func reportConfigurationFailure() {
        Task { @MainActor [onConfigurationFailure] in
            onConfigurationFailure()
        }
    }
}
