import AVFoundation
import SwiftUI

struct StreamPreviewView: UIViewRepresentable {
    @EnvironmentObject var model: Model

    func makeUIView(context _: Context) -> PreviewView {
        return model.streamPreviewView
    }

    func updateUIView(_: PreviewView, context _: Context) {}
}

class CameraPreviewUiView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        previewLayer.videoGravity = .resizeAspectFill
    }
}

struct CameraPreviewView: UIViewRepresentable {
    @EnvironmentObject var model: Model

    func makeUIView(context _: Context) -> CameraPreviewUiView {
        return model.cameraPreviewView
    }

    func updateUIView(_: CameraPreviewUiView, context _: Context) {}
}

struct StreamView: View {
    @ObservedObject var show: Show
    let cameraPreviewView: CameraPreviewView
    let streamPreviewView: StreamPreviewView

    var body: some View {
        if show.cameraPreview {
            cameraPreviewView
        } else {
            streamPreviewView
        }
    }
}
