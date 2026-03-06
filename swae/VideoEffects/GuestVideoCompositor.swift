//
//  GuestVideoCompositor.swift
//  swae
//
//  VideoEffect subclass that composites the remote guest's video as a
//  Picture-in-Picture overlay onto the host's camera feed for RTMP broadcast.
//
//  CIImage path: CIFilter.sourceOverCompositing (same as NostrChatEffect)
//  MetalPetal path: MTIMultilayerCompositingFilter (same as NostrChatEffect)
//
//  Registered via media.registerEffect() when a guest connects,
//  unregistered via media.unregisterEffect() when they disconnect.
//  When no guest buffer is available, returns the input image unchanged.
//

import AVFoundation
import CoreImage.CIFilterBuiltins
import MetalPetal

final class GuestVideoCompositor: VideoEffect {

    // Remote video source — written by WebRTC decoder thread, read by pipeline thread.
    private weak var remoteVideoRenderer: PixelBufferVideoRenderer?

    // PiP layout — percentage-based (0–100), set by widget system via setSceneWidget()
    private var x: Double = 70.0
    private var y: Double = 5.0
    private var widgetWidth: Double = 25.0
    private var widgetHeight: Double = 35.0
    private var pipCornerRadius: CGFloat = 12

    // CIImage path
    private let compositeFilter = CIFilter.sourceOverCompositing()

    init(remoteVideoRenderer: PixelBufferVideoRenderer) {
        self.remoteVideoRenderer = remoteVideoRenderer
        super.init()
    }

    override func getName() -> String {
        return "Guest Video PiP"
    }

    /// Update position/size from the widget system. Called by ModelScene on scene updates.
    func setSceneWidget(sceneWidget: SettingsSceneWidget?) {
        if let sw = sceneWidget {
            x = sw.x
            y = sw.y
            widgetWidth = sw.width
            widgetHeight = sw.height
        }
    }

    // MARK: - CIImage Path

    private var _compositeLogCount: Int = 0

    override func execute(_ image: CIImage, _: VideoEffectInfo) -> CIImage {
        guard let guestBuffer = remoteVideoRenderer?.getLatestBuffer() else {
            _compositeLogCount += 1
            if _compositeLogCount <= 3 || _compositeLogCount % 300 == 0 {
                print("🎥🎥🎥 COMPOSITOR: no remote buffer (renderer=\(remoteVideoRenderer != nil ? "alive" : "NIL")) frame #\(_compositeLogCount)")
            }
            return image
        }

        let outputSize = image.extent.size
        let guestImage = CIImage(cvPixelBuffer: guestBuffer)
        _compositeLogCount += 1
        if _compositeLogCount <= 5 || _compositeLogCount % 300 == 0 {
            print("🎥🎥🎥 COMPOSITING PIP #\(_compositeLogCount) — guest=\(Int(guestImage.extent.width))x\(Int(guestImage.extent.height)), output=\(Int(outputSize.width))x\(Int(outputSize.height))")
        }

        // Calculate PiP size from percentage-based widget dimensions
        let pipWidth = outputSize.width * CGFloat(widgetWidth) / 100.0
        let pipHeight = outputSize.height * CGFloat(widgetHeight) / 100.0

        // Scale guest to PiP size (aspect-fit)
        let scaleX = pipWidth / guestImage.extent.width
        let scaleY = pipHeight / guestImage.extent.height
        let scale = min(scaleX, scaleY)
        let scaled = guestImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Position from percentage-based x/y (CIImage origin is bottom-left)
        let px = outputSize.width * CGFloat(x) / 100.0
        let py = outputSize.height - outputSize.height * CGFloat(y) / 100.0 - scaled.extent.height
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: px, y: py))

        // Crop to PiP bounds
        let cropped = positioned.cropped(to: CGRect(
            x: px, y: py,
            width: scaled.extent.width,
            height: scaled.extent.height
        ))

        // Composite over host video
        compositeFilter.inputImage = cropped
        compositeFilter.backgroundImage = image
        return (compositeFilter.outputImage ?? image).cropped(to: image.extent)
    }

    // MARK: - MetalPetal Path

    override func executeMetalPetal(_ image: MTIImage?, _: VideoEffectInfo) -> MTIImage? {
        guard let image, let guestBuffer = remoteVideoRenderer?.getLatestBuffer() else {
            return image
        }

        let guestImage = MTIImage(cvPixelBuffer: guestBuffer, alphaType: .alphaIsOne)

        // Calculate PiP size from percentage-based widget dimensions
        let pipWidth = image.size.width * CGFloat(widgetWidth) / 100.0
        let pipHeight = image.size.height * CGFloat(widgetHeight) / 100.0

        // Scale guest to PiP size
        let scaledGuest = guestImage.resized(to: CGSize(width: pipWidth, height: pipHeight))
        guard let scaledGuest else { return image }

        // Position center point from percentage-based x/y
        // MetalPetal uses top-left origin, position is the center of the layer
        let centerX = image.size.width * CGFloat(x) / 100.0 + pipWidth / 2
        let centerY = image.size.height * CGFloat(y) / 100.0 + pipHeight / 2

        let filter = MTIMultilayerCompositingFilter()
        filter.inputBackgroundImage = image
        filter.layers = [
            .init(content: scaledGuest, position: CGPoint(x: centerX, y: centerY)),
        ]
        return filter.outputImage ?? image
    }

    // MARK: - Configuration

    /// Update PiP size as a fraction of output width (0.0–1.0). Default: 0.2 (20%).
    func setPipSize(widthFraction: CGFloat) {
        widgetWidth = Double(max(0.1, min(1.0, widthFraction)) * 100)
    }

    /// Update PiP margin from edge in pixels. Default: 20.
    func setPipMargin(_ margin: CGFloat) {
        // No-op — margin is now controlled by widget x/y position
    }
}
