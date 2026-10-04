import AppKit
@preconcurrency import AVFoundation
import Combine
import SwiftUI

/// Preview only: never installs an audio input, capture output, or recording sink.
@MainActor
final class MirrorController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var message = "A private camera preview. Nothing is recorded or uploaded."
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.notchharbor.mirror", qos: .userInitiated)
    private let activation = PreviewActivation()
    private var errorObserver: NSObjectProtocol?

    init() {
        errorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
                self?.message = "Camera unavailable. It may be in use or disconnected. Try opening the mirror again."
            }
        }
    }

    func start() {
        guard !starting, !running else { return }
        let token = activation.invalidate()
        starting = true
        Task { [self] in
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            guard activation.isCurrent(token) else { return }
            guard granted else {
                starting = false
                message = "Camera access is off. Allow NotchHarbor in System Settings → Privacy & Security → Camera."
                return
            }
            let capture = session
            let activation = activation
            queue.async { [weak self] in
                guard activation.isCurrent(token) else { return }
                var problem: String?
                capture.beginConfiguration()
                for input in capture.inputs { capture.removeInput(input) }
                capture.sessionPreset = .vga640x480
                if let device = AVCaptureDevice.default(for: .video) {
                    do {
                        let input = try AVCaptureDeviceInput(device: device)
                        if capture.canAddInput(input) {
                            capture.addInput(input)
                            try device.lockForConfiguration()
                            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) {
                                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                            }
                            device.unlockForConfiguration()
                        } else { problem = "This camera cannot be used right now." }
                    } catch { problem = "Could not start the camera. Check access or try again." }
                } else { problem = "No camera is connected." }
                capture.commitConfiguration()
                if problem == nil && activation.isCurrent(token) { capture.startRunning() }
                let active = capture.isRunning
                Task { @MainActor in
                    guard let self, activation.isCurrent(token) else { return }
                    self.starting = false
                    self.running = active
                    self.message = problem ?? (active ? "Live mirror · not recording" : "Camera unavailable. Try again.")
                }
            }
        }
    }

    func stop() {
        _ = activation.invalidate()
        starting = false
        running = false
        message = "Camera off. Start Mirror when you’re ready."
        let capture = session
        queue.async {
            if capture.isRunning { capture.stopRunning() }
            capture.beginConfiguration()
            for input in capture.inputs { capture.removeInput(input) }
            capture.commitConfiguration()
        }
    }
}

private final class MirrorPreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); preview.frame = bounds }
}

struct MirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = MirrorPreviewView()
        view.preview.session = session
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let connection = (nsView as? MirrorPreviewView)?.preview.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? MirrorPreviewView)?.preview.session = nil
    }
}
