import AVFoundation
import Observation
import UIKit

/// The only way a photo gets into the app: taken live, right now, with this camera.
///
/// There is no photo-library code anywhere in the app and no library permission in Info.plist,
/// so nothing from the camera roll can be posted. Captured photos are resized and re-encoded,
/// which also drops their metadata (location, device, original timestamp), and they are never
/// written to the camera roll.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    private(set) var isReady = false
    private(set) var isCapturing = false
    private(set) var error: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "proximity.camera")
    @ObservationIgnored private var position: AVCaptureDevice.Position = .back
    @ObservationIgnored private var pending: CheckedContinuation<CapturedPhoto?, Never>?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            error = "CAMERA ACCESS DENIED"
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configure()
                self.session.startRunning()
                DispatchQueue.main.async { self.isReady = true }
            } catch {
                DispatchQueue.main.async { self.error = "NO CAMERA FOUND" }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            session.stopRunning()
        }
    }

    func flip() {
        guard isReady else { return }
        position = position == .back ? .front : .back
        queue.async { [weak self] in
            try? self?.configure()
        }
    }

    func capture() async -> CapturedPhoto? {
        guard isReady, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            pending = continuation
            queue.async { [weak self] in
                guard let self else { return }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    /// Runs on `queue`.
    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        for existing in session.inputs {
            session.removeInput(existing)
        }
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { throw CameraError.unavailable }
            session.addOutput(output)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result = error == nil ? photo.fileDataRepresentation().flatMap(PhotoProcessing.prepare) : nil
        DispatchQueue.main.async {
            self.pending?.resume(returning: result)
            self.pending = nil
        }
    }

    private enum CameraError: Error {
        case unavailable
    }
}

enum PhotoProcessing {
    static let maxDimension: CGFloat = 1440

    /// Downscales and re-encodes as JPEG. Drawing into a fresh context applies the orientation
    /// and leaves every bit of the original metadata behind.
    static func prepare(_ data: Data) -> CapturedPhoto? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return nil }
        return CapturedPhoto(jpeg: jpeg, width: Int(size.width), height: Int(size.height))
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
