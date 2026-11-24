@preconcurrency import AVFoundation
import SwiftUI
import UIKit
import VisionKit

public struct QRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let onScannedCode: @MainActor (String) -> Void

    @State private var isTorchEnabled = false
    @State private var scanHapticTrigger = 0
    @State private var cameraPermissionDenied = false

    public init(onScannedCode: @escaping @MainActor (String) -> Void) {
        self.onScannedCode = onScannedCode
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cameraPermissionDenied {
                    ContentUnavailableView(
                        "Camera Access Required",
                        systemImage: "camera.fill",
                        description: Text("Enable camera access for PrismDM in iOS Settings to scan QR code URLs.")
                    )
                } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    VisionKitQRScannerRepresentable { code in
                        handleScan(code)
                    }
                    .ignoresSafeArea()
                } else {
                    AVFoundationQRScannerRepresentable(isTorchEnabled: isTorchEnabled) { code in
                        handleScan(code)
                    }
                    .ignoresSafeArea()
                }

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(PrismBrandPalette.crimsonAccent, lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .background(.clear)
                    Spacer()

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 14) {
                            Button {
                                toggleTorch()
                            } label: {
                                Label(
                                    isTorchEnabled ? "Torch On" : "Torch",
                                    systemImage: isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill"
                                )
                            }
                            .buttonStyle(.glass)

                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Scan QR URL")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: scanHapticTrigger)
            .task {
                await verifyCameraPermission()
            }
            .onDisappear {
                setTorch(false)
            }
        }
    }

    private func handleScan(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scanHapticTrigger += 1
        setTorch(false)
        onScannedCode(trimmed)
        dismiss()
    }

    private func verifyCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionDenied = !granted
        default:
            cameraPermissionDenied = true
        }
    }

    private func toggleTorch() {
        isTorchEnabled.toggle()
        setTorch(isTorchEnabled)
    }

    private func setTorch(_ enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Torch unavailable on current capture device
        }
    }
}

// MARK: - VisionKit DataScanner Bridge

private struct VisionKitQRScannerRepresentable: UIViewControllerRepresentable {
    let onDetect: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetect: onDetect)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetect: @MainActor (String) -> Void
        private var didDeliver = false

        init(onDetect: @escaping @MainActor (String) -> Void) {
            self.onDetect = onDetect
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didDeliver else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty {
                    didDeliver = true
                    dataScanner.stopScanning()
                    onDetect(payload)
                    return
                }
            }
        }
    }
}

// MARK: - AVFoundation Fallback Bridge

private struct AVFoundationQRScannerRepresentable: UIViewControllerRepresentable {
    let isTorchEnabled: Bool
    let onDetect: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> FallbackScannerViewController {
        FallbackScannerViewController(onDetect: onDetect)
    }

    func updateUIViewController(_ uiViewController: FallbackScannerViewController, context: Context) {}

    final class FallbackScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let onDetect: @MainActor (String) -> Void
        private let captureSession = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didDeliver = false

        init(onDetect: @escaping @MainActor (String) -> Void) {
            self.onDetect = onDetect
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input) else {
                return
            }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(output) else { return }
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer

            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue, !value.isEmpty else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self, !self.didDeliver else { return }
                self.didDeliver = true
                let session = self.captureSession
                DispatchQueue.global(qos: .userInitiated).async {
                    session.stopRunning()
                }
                self.onDetect(value)
            }
        }
    }
}
