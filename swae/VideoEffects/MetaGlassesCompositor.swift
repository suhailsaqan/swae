import AVFoundation
import CoreImage.CIFilterBuiltins
import MetalPetal

/// Composites the Meta Glasses camera feed as a PiP overlay onto the
/// phone camera stream. Follows the same pattern as GuestVideoCompositor.
/// Registered via media.registerEffect() when PiP mode is enabled,
/// unregistered when disabled. Returns input unchanged when no glasses frame is available.
final class MetaGlassesCompositor: VideoEffect {
    // Latest pixel buffer from glasses — written by SDK thread, read by pipeline thread.
    private var latestBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    // PiP layout — percentage-based (0–100)
    private var x: Double = 70.0
    private var y: Double = 5.0
    private var widgetWidth: Double = 25.0
    private var widgetHeight: Double = 35.0

    private let compositeFilter = CIFilter.sourceOverCompositing()

    override func getName() -> String {
        return "Meta Glasses PiP"
    }

    /// Called from the SDK video frame callback (any thread).
    func updateFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestBuffer = pixelBuffer
        bufferLock.unlock()
    }

    /// Update position/size from the widget system.
    func setSceneWidget(sceneWidget: SettingsSceneWidget?) {
        if let sw = sceneWidget {
            x = sw.x
            y = sw.y
            widgetWidth = sw.width
            widgetHeight = sw.height
        }
    }

    // MARK: - CIImage Path

    override func execute(_ image: CIImage, _: VideoEffectInfo) -> CIImage {
        bufferLock.lock()
        let buffer = latestBuffer
        bufferLock.unlock()

        guard let buffer else { return image }

        let outputSize = image.extent.size
        let glassesImage = CIImage(cvPixelBuffer: buffer)

        let pipWidth = outputSize.width * CGFloat(widgetWidth) / 100.0
        let pipHeight = outputSize.height * CGFloat(widgetHeight) / 100.0

        let scaleX = pipWidth / glassesImage.extent.width
        let scaleY = pipHeight / glassesImage.extent.height
        let scale = min(scaleX, scaleY)
        let scaled = glassesImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let px = outputSize.width * CGFloat(x) / 100.0
        let py = outputSize.height - outputSize.height * CGFloat(y) / 100.0 - scaled.extent.height
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: px, y: py))

        let cropped = positioned.cropped(to: CGRect(
            x: px, y: py,
            width: scaled.extent.width,
            height: scaled.extent.height
        ))

        compositeFilter.inputImage = cropped
        compositeFilter.backgroundImage = image
        return (compositeFilter.outputImage ?? image).cropped(to: image.extent)
    }

    // MARK: - MetalPetal Path

    override func executeMetalPetal(_ image: MTIImage?, _: VideoEffectInfo) -> MTIImage? {
        bufferLock.lock()
        let buffer = latestBuffer
        bufferLock.unlock()

        guard let image, let buffer else { return image }

        let glassesImage = MTIImage(cvPixelBuffer: buffer, alphaType: .alphaIsOne)

        let pipWidth = image.size.width * CGFloat(widgetWidth) / 100.0
        let pipHeight = image.size.height * CGFloat(widgetHeight) / 100.0

        let scaledGlasses = glassesImage.resized(to: CGSize(width: pipWidth, height: pipHeight))
        guard let scaledGlasses else { return image }

        let centerX = image.size.width * CGFloat(x) / 100.0 + pipWidth / 2
        let centerY = image.size.height * CGFloat(y) / 100.0 + pipHeight / 2

        let filter = MTIMultilayerCompositingFilter()
        filter.inputBackgroundImage = image
        filter.layers = [
            .init(content: scaledGlasses, position: CGPoint(x: centerX, y: centerY)),
        ]
        return filter.outputImage ?? image
    }
}
