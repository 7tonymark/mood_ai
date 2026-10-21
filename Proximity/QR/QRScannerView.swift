import AVFoundation
import SwiftUI
import UIKit

/// A camera view that reports every QR code it sees.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
        controller.onFailure = onFailure
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "proximity.qr-session")
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var lastCode: String?
    private var lastCodeAt = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configure()
                    } else {
                        self.onFailure?("CAMERA ACCESS DENIED")
                    }
                }
            }
        default:
            onFailure?("CAMERA ACCESS DENIED")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard configured else { return }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onFailure?("NO CAMERA FOUND")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onFailure?("CAMERA UNAVAILABLE")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        configured = true

        sessionQueue.async { [session] in
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        // The same code is reported many times a second; only pass it on once in a while.
        if code == lastCode, Date().timeIntervalSince(lastCodeAt) < 2 { return }
        lastCode = code
        lastCodeAt = Date()
        onCode?(code)
    }
}
