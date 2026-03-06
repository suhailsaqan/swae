import AVFoundation
import CoreImage.CIFilterBuiltins
import MetalPetal
import Vision

public struct VideoEffectInfo {
    let isFirstAfterAttach: Bool
    let sceneVideoSourceId: UUID
    let detectionJobs: [DetectionJob]
    let detections: [UUID: Detections]
    // periphery:ignore
    let presentationTimeStamp: CMTime
    // periphery:ignore
    let videoUnit: VideoUnit

    func sceneDetections() -> Detections? {
        return detections[sceneVideoSourceId]
    }

    func sceneFaceDetections() -> [VNFaceObservation]? {
        return detections[sceneVideoSourceId]?.face
    }

    func faceDetections(_ videoSourceId: UUID) -> [VNFaceObservation]? {
        return detections[videoSourceId]?.face
    }

    func getCiImage(_ videoSourceId: UUID) -> CIImage? {
        guard let imageBuffer = detectionJobs.first(where: { $0.videoSourceId == videoSourceId })?.imageBuffer
        else {
            return videoUnit.getCiImage(videoSourceId, presentationTimeStamp)
        }
        return CIImage(cvPixelBuffer: imageBuffer)
    }
}

public enum VideoEffectDetectionsMode {
    case off
    case now(UUID?)
    case interval(UUID?, Double)
}

open class VideoEffect: NSObject {
    var effects: [VideoEffect] = []

    open func getName() -> String {
        return ""
    }

    open func needsFaceDetections(_: Double) -> VideoEffectDetectionsMode {
        return .off
    }

    open func needsTextDetections(_: Double) -> VideoEffectDetectionsMode {
        return .off
    }

    open func isEnabled() -> Bool {
        return true
    }

    open func prepare(_: CIImage, _: VideoEffectInfo) {}

    open func executeEarly(_ image: CIImage, _: VideoEffectInfo) -> CIImage {
        return image
    }

    open func execute(_ image: CIImage, _: VideoEffectInfo) -> CIImage {
        return image
    }

    open func executeMetalPetal(_ image: MTIImage?, _: VideoEffectInfo) -> MTIImage? {
        return image
    }

    open func isMetalPetal() -> Bool {
        return false
    }

    open func removed() {}

    open func shouldRemove() -> Bool {
        return false
    }

    func applyEarlyEffects(_ image: CIImage, _ info: VideoEffectInfo) -> CIImage {
        var image = image
        for effect in effects where effect.isEnabled() {
            image = effect.executeEarly(image, info)
        }
        return image
    }

    func applyEffects(_ image: CIImage, _ info: VideoEffectInfo) -> CIImage {
        var image = image
        for effect in effects where effect.isEnabled() {
            image = effect.execute(image, info)
        }
        return image
    }
}
