import SwiftUI
import AVFoundation

@MainActor
final class CameraPreviewModel: ObservableObject {
    @Published var message = "Starting camera…"
    let session = AVCaptureSession()
    private var configured = false

    func start() {
        guard !configured else { return }
        configured = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.message = "Camera access was denied in macOS Privacy & Security settings."; return }
                guard let camera = AVCaptureDevice.default(for: .video) else { self.message = "No camera was found."; return }
                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    self.session.beginConfiguration()
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                    self.session.sessionPreset = .high
                    self.session.commitConfiguration()
                    self.message = "Camera preview · \(camera.localizedName)"
                    self.session.startRunning()
                } catch { self.message = "Could not start camera: \(error.localizedDescription)" }
            }
        }
    }

    func stop() { if session.isRunning { session.stopRunning() } }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        view.layer = preview
        context.coordinator.preview = preview
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { context.coordinator.preview?.frame = view.bounds }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var preview: AVCaptureVideoPreviewLayer? }
}

struct CameraPreviewSheet: View {
    @StateObject private var camera = CameraPreviewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            CameraPreview(session: camera.session).frame(minWidth: 640, minHeight: 420).background(.black)
            HStack {
                Text(camera.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { camera.stop(); dismiss() }.keyboardShortcut(.escape)
            }
        }
        .padding(16).frame(width: 700, height: 500)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
